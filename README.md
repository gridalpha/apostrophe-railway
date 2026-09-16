# ApostropheCMS on Railway

A deploy-ready [ApostropheCMS 4](https://apostrophecms.com) project: the official
[Essentials starter kit](https://github.com/apostrophecms/starter-kit-essentials)
(MIT, vendored at commit `2fee4b7`) plus the pieces a hosted deployment needs.

ApostropheCMS publishes no server image — the deployable artifact is a project you
scaffold and build — so this repository *is* the project. Fork it and build your
site in `modules/` and `views/` exactly as you would locally.

## What was added to the starter kit

| File | Why |
|---|---|
| `Dockerfile` | Builds the production asset bundle at image build time against a throwaway SQLite database, so no database service has to exist during the build. Writes a `release-id` file, because built assets are served from `/apos-frontend/releases/<id>/` and that id must be identical at build and run time. |
| `docker-entrypoint.sh` | Prepares the volume, drops to an unprivileged uid, defaults the base URL and session secret, sizes the cluster and the Node heap from the container's cgroup, runs migrations, seeds the first administrator, then execs the server. |
| `modules/railway/index.js` | A `/healthz` route that reads a document (a real database check for Railway's anonymous prober) and an idempotent `railway:create-admin` task. |
| `modules/@apostrophecms/express/index.js` | `trustProxy` plus a `Secure` session cookie, which Apostrophe leaves off by default. |

## Environment variables

| Variable | Required | Default | Notes |
|---|---|---|---|
| `APOS_DB_URI` | yes | — | `${{MongoDB.MONGO_URL}}/apostrophe?authSource=admin`. SQLite and PostgreSQL URIs are also accepted by Apostrophe 4.32+, but MongoDB is the supported production backend. |
| `ADMIN_PASSWORD` | yes | — | Password for the first administrator. Read only while that account does not exist; change it afterwards in the admin UI. |
| `ADMIN_USERNAME` | no | `admin` | Login name for that account. |
| `APOS_BASE_URL` | no | `https://$RAILWAY_PUBLIC_DOMAIN` | Absolute URLs Apostrophe emits. Set it explicitly when you attach a custom domain. |
| `APOS_SESSION_SECRET` | no | generated once onto the volume | Signs session cookies. A value that changes between boots logs every editor out. |
| `APOS_CLUSTER_PROCESSES` | no | `2` | Worker processes. Each one is a complete Apostrophe, so raise the service's memory before raising this. Capped to the container's CPU quota. |
| `APOS_COOKIE_SECURE` | no | on | Set to `0` only when serving over plain HTTP on purpose. |
| `PORT` | no | `3000` | Set by Railway. |
| `NODE_OPTIONS` | no | derived | Heap ceiling, computed from the cgroup memory limit. Set it yourself to override. |

## Storage

Uploads are stored on the filesystem, on a Railway volume mounted at `/app/data`;
`public/uploads` is a symlink into it. Apostrophe also supports S3-compatible
storage through `APOS_S3_BUCKET`/`APOS_S3_KEY`/`APOS_S3_SECRET`/`APOS_S3_REGION`/
`APOS_S3_ENDPOINT`, but uploadfs builds unsigned object URLs, so that mode needs a
bucket that allows anonymous reads.

## Running it locally

```sh
npm install
export APOS_DB_URI=sqlite://./data/apostrophe.sqlite
npm run dev
node app @apostrophecms/user:add admin admin   # prompts for a password
```

Upstream documentation: <https://docs.apostrophecms.org>.
