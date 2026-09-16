#!/bin/bash
# Boot sequence for ApostropheCMS on Railway.
#
#   1. prepare the volume and drop the app to an unprivileged uid
#   2. supply defaults Railway can only know at run time (base URL, session
#      secret, cluster size, heap ceiling)
#   3. migrate and seed the first administrator before anything listens
#   4. exec the server
set -euo pipefail

log() { echo "[entrypoint] $*"; }

APP_DIR=/app
DATA_DIR="${APP_DIR}/data"
RUN_USER=node
RUN_UID=$(id -u "$RUN_USER")
RUN_GID=$(id -g "$RUN_USER")

# ---------------------------------------------------------------- volume ----
# The volume arrives root-owned and empty apart from lost+found, so every
# directory the app writes to is created and chowned here rather than by the
# app, which runs unprivileged.
mkdir -p "${DATA_DIR}/uploads" "${DATA_DIR}/temp/uploadfs"
if [ ! -L "${APP_DIR}/public/uploads" ]; then
  ln -sfn "${DATA_DIR}/uploads" "${APP_DIR}/public/uploads"
fi
if [ "$(stat -c %u "${DATA_DIR}/uploads")" != "$RUN_UID" ]; then
  log "taking ownership of ${DATA_DIR}"
  chown -R "${RUN_UID}:${RUN_GID}" "${DATA_DIR}"
fi
chown -h "${RUN_UID}:${RUN_GID}" "${APP_DIR}/public/uploads" || true

# -------------------------------------------------------------- database ----
if [ -z "${APOS_DB_URI:-}" ] && [ -z "${APOS_MONGODB_URI:-}" ]; then
  log "FATAL: set APOS_DB_URI to a MongoDB connection string, e.g."
  log "       \${{MongoDB.MONGO_URL}}/apostrophe?authSource=admin"
  exit 1
fi

# -------------------------------------------------------------- base URL ----
# Apostrophe builds absolute URLs (sitemaps, oembed, e-mail, the login
# redirect) from this. Railway injects the public hostname without a scheme.
if [ -z "${APOS_BASE_URL:-}" ] && [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ]; then
  export APOS_BASE_URL="https://${RAILWAY_PUBLIC_DOMAIN}"
  log "APOS_BASE_URL defaulted to ${APOS_BASE_URL}"
fi

# --------------------------------------------------------- session secret ----
# Session cookies are signed with this, so it has to survive a redeploy: a
# fresh value on every boot logs every editor out. A deployer-supplied value
# always wins; otherwise one is generated once and kept on the volume.
if [ -z "${APOS_SESSION_SECRET:-}" ]; then
  SECRET_FILE="${DATA_DIR}/session-secret"
  if [ ! -s "$SECRET_FILE" ]; then
    log "generating a persistent session secret at ${SECRET_FILE}"
    node -e 'process.stdout.write(require("crypto").randomBytes(32).toString("hex"))' > "$SECRET_FILE"
    chown "${RUN_UID}:${RUN_GID}" "$SECRET_FILE"
    chmod 600 "$SECRET_FILE"
  fi
  APOS_SESSION_SECRET="$(cat "$SECRET_FILE")"
  export APOS_SESSION_SECRET
fi

# ------------------------------------------------------------- cgroup fit ----
# cluster.processes falls back to os.cpus(), which reports the *host's* 48
# cores on Railway, and Node sizes its old-space heap from host RAM the same
# way. Both are derived from the cgroup instead.
cgroup_cpus() {
  local quota period
  if [ -r /sys/fs/cgroup/cpu.max ]; then
    read -r quota period < /sys/fs/cgroup/cpu.max || true
    if [ "${quota:-max}" != "max" ] && [ -n "${period:-}" ]; then
      echo $(( (quota + period - 1) / period ))
      return
    fi
  fi
  nproc
}
cgroup_mem_mb() {
  local max
  if [ -r /sys/fs/cgroup/memory.max ]; then
    max=$(cat /sys/fs/cgroup/memory.max)
    if [ "$max" != "max" ]; then
      echo $(( max / 1024 / 1024 ))
      return
    fi
  fi
  echo 1024
}

CPUS=$(cgroup_cpus)
MEM_MB=$(cgroup_mem_mb)

# Apostrophe's own floor is 2 processes whenever cluster mode is on. Two is
# also the right default here: each process is a complete Apostrophe, so the
# ceiling is memory, not cores. Raise APOS_CLUSTER_PROCESSES after raising the
# service's memory limit.
if [ -z "${APOS_CLUSTER_PROCESSES:-}" ]; then
  export APOS_CLUSTER_PROCESSES=2
fi
if [ "$APOS_CLUSTER_PROCESSES" -gt "$CPUS" ]; then
  log "capping APOS_CLUSTER_PROCESSES to the cgroup's ${CPUS} cpus"
  export APOS_CLUSTER_PROCESSES="$CPUS"
fi

if [ -z "${NODE_OPTIONS:-}" ]; then
  # Leave headroom for the primary process and for sharp's off-heap buffers.
  HEAP=$(( MEM_MB * 2 / 3 / (APOS_CLUSTER_PROCESSES + 1) ))
  [ "$HEAP" -lt 256 ] && HEAP=256
  export NODE_OPTIONS="--max-old-space-size=${HEAP}"
fi
log "cgroup: ${CPUS} cpus, ${MEM_MB} MB; cluster processes=${APOS_CLUSTER_PROCESSES}; ${NODE_OPTIONS}"

export HOME=/home/node
as_app_user() {
  setpriv --reuid="$RUN_UID" --regid="$RUN_GID" --init-groups "$@"
}

# ------------------------------------------------------------- bootstrap ----
# Railway has no service ordering, so the database may still be starting.
# Every step below is idempotent and is retried rather than assumed.
run_task() {
  local label="$1"; shift
  local i
  for i in $(seq 1 30); do
    if as_app_user node app "$@"; then
      return 0
    fi
    log "${label} failed (attempt ${i}); retrying in 10s"
    sleep 10
  done
  log "FATAL: ${label} did not succeed"
  return 1
}

run_task "migration" @apostrophecms/migration:migrate
run_task "admin bootstrap" railway:create-admin

log "starting apostrophe on port ${PORT:-3000}"
exec setpriv --reuid="$RUN_UID" --regid="$RUN_GID" --init-groups node app
