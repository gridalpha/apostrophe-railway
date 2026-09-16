# ApostropheCMS on Railway.
#
# ApostropheCMS publishes no server image: the deployable artifact is a project
# you scaffold and build, so this repository *is* the project. It is the
# official Essentials starter kit plus the pieces a hosted deployment needs —
# a boot-time admin bootstrap, a health route, and an entrypoint that sizes the
# cluster from the container's cgroup rather than the host's 48 cores.
FROM node:22-bookworm-slim

# tini: Apostrophe's cluster mode forks worker processes and Railway's pid 1 is
#   its own init, so tini is registered as a subreaper (-s) to reap them.
# ca-certificates: node:*-slim purges the bundle during its own build; Node has
#   an internal store but nothing else in the image does.
RUN apt-get update \
 && apt-get install -y --no-install-recommends tini ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && command -v tini > /dev/null \
 && command -v setpriv > /dev/null

WORKDIR /app

# devDependencies carry autoprefixer, which postcss.config.js loads during the
# asset build, so NODE_ENV stays unset until the install is done.
COPY package.json ./
RUN npm install --include=dev --no-audit --no-fund

COPY . .

# Uploads live on the Railway volume mounted at /app/data. public/uploads is a
# symlink into it so Apostrophe's own static route keeps serving /uploads/...,
# and uploadfs' temp directory (rootDir/data/temp/uploadfs) lands there too.
RUN mkdir -p /app/data/uploads /app/data/temp/uploadfs \
 && ln -sfn /app/data/uploads /app/public/uploads

ENV NODE_ENV=production

# Built assets are served from /apos-frontend/releases/<release id>/, so the id
# has to be identical at build time and at run time: a file in the image is the
# only form that cannot drift. The asset build boots Apostrophe, which needs a
# database — SQLite (shipped by @apostrophecms/db-connect) provides one here
# with no service to wait on.
RUN date +%s > release-id \
 && APOS_DB_URI=sqlite:///tmp/apos-build.sqlite node app @apostrophecms/asset:build \
 && rm -f /tmp/apos-build.sqlite \
 && test -d "public/apos-frontend/releases/$(cat release-id)"

# Fail the build, not a container, on a typo in the shipped scripts.
RUN bash -n docker-entrypoint.sh \
 && node --check app.js

ENTRYPOINT ["/usr/bin/tini", "-s", "--", "/app/docker-entrypoint.sh"]
