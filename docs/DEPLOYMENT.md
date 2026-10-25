# Production deployment runbook

This repository is prepared for a three-part deployment: Flutter Web on Firebase
Hosting, the existing FastAPI application on a model-capable host, and managed
PostgreSQL. This document intentionally does not create resources, authenticate,
restore data, or deploy anything.

## Architecture and sizing

Use Firebase Hosting for `frontend/build/web`. Host FastAPI on a persistent
4-vCPU, 16-GB RAM Linux VM with at least 100 GB of SSD storage. The current
application loads DistilBERT, Whisper, Coqui TTS, MediaPipe, FaceNet/PyTorch,
and uses a local Ollama service; it is not a good fit for an ephemeral,
small-memory serverless instance. Use a single FastAPI worker initially because
each worker would load its own model set.

Keep the care data in managed PostgreSQL. Keep the current file-backed
authentication and session files on encrypted persistent storage for this
deployment; they are not migrated by this runbook. Do not put either file in a
container image, Git repository, or public object storage.

## Before any cloud action

1. Keep the existing local PostgreSQL database untouched.
2. Retain `~/Documents/memorycare-backups/memorycare-before-deployment.dump` as
   the recovery source. Do not restore it until an empty managed PostgreSQL
   target and a verified rollback plan have been approved.
3. Store `AUTH_ENCRYPT_KEY` and the database password in the provider secret
   manager. Do not place them in `.env.production.example`, Firebase Hosting,
   source control, image build arguments, or command history.
4. Copy `.env.production.example` into the host's protected secret/configuration
   mechanism and replace placeholders there only.

## Required production configuration

`ENVIRONMENT=production` makes FastAPI refuse to start without a database URL,
explicit browser origins, and a non-default `AUTH_ENCRYPT_KEY`.

Set `CORS_ORIGINS` to the exact Firebase Hosting and custom-domain HTTPS origins,
separated by commas. Do not use `*` in production. `DATABASE_POOL_SIZE` and
`DATABASE_MAX_OVERFLOW` default to 5 each; keep total connection demand within
the managed PostgreSQL connection limit.

The configured `OLLAMA_HOST` and `DUCKLING_URL` must be reachable from FastAPI.
For the recommended co-located VM deployment, they remain loopback endpoints.
The client-facing API must be served via HTTPS, for example
`https://api.example.com`; use that value in the Flutter release build:

```bash
flutter build web --release --dart-define=API_BASE=https://api.example.com
```

## Database safety gate

The only approved migration command for a new, empty managed database is:

```bash
DATABASE_URL='postgresql+psycopg://...' .venv/bin/alembic upgrade head
```

Do not run it against the local database. Do not run `alembic downgrade`,
`Base.metadata.drop_all`, `pg_restore`, or the JSON migration script without a
separate approval that identifies the exact target database.

Before a future restore, inspect the backup and target only:

```bash
pg_restore --list ~/Documents/memorycare-backups/memorycare-before-deployment.dump
psql "$DATABASE_URL" -c 'select version();'
```

The actual restore must be reviewed separately because it writes patient data.

## Firebase Hosting safety gate

`firebase.json` serves the Flutter release directory and rewrites unmatched
paths to `index.html`. Flutter recognizes only `/`, `/login`, `/register`,
`/dashboard`, `/voice`, and `/face`; unknown paths fall back to the landing
screen.

After an explicit Firebase login and project selection, validate configuration
before deploying:

```bash
firebase hosting:channel:deploy preview --expires 7d
```

Do not run that command until the user approves authentication and a preview
deployment. Production deployment and custom-domain setup require separate
approval.

## Production verification checklist

1. Confirm `https://api.example.com/health` returns HTTPS and does not expose
   credentials.
2. Verify CORS preflight and authenticated API requests from each allowed web
   origin.
3. Verify `/`, `/login`, `/register`, `/dashboard`, `/voice`, and `/face` load
   correctly after a direct visit and refresh.
4. Verify browser microphone and camera upload flows. Do not use
   `/v1/vision/recognize-camera` in cloud production: it attempts to access the
   server's own webcam.
5. Verify PostgreSQL connection health, existing patient records, and the
   file-backed auth/session persistence on the encrypted host volume.
