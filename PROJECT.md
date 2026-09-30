# SuccessfulSuccess — project structure

What lives where, the API contract between frontend and backend, the versions
in use, and how the local services start. Behaviour, design and deployment
details are in `SPEC.md` and `README.md`.

## Why a monorepo

- **Atomic changes.** Backend, frontend, database migrations, infrastructure and
  CI live in one repository, so a change that crosses them (a new API field, its
  migration, the UI that shows it, the pipeline that ships it) is one commit and
  one review, and can never be half-deployed across repositories.
- **The repo is the agent's context window.** A coding agent sees one checkout.
  With the API contract, both sides of it, the compose file and the workflows in
  the same tree, it can read and change all of them together instead of guessing
  at a repository it cannot see.

## Folders

| Path | Purpose |
|------|---------|
| `backend/` | FastAPI API, its Dockerfiles and tests |
| `backend/app/api/` | HTTP layer only: routes under `/api/v1`, request parsing, response models |
| `backend/app/services/` | Business rules: validation, the "today" window in `APP_TIMEZONE` |
| `backend/app/repositories/` | SQLAlchemy queries, no HTTP concerns |
| `backend/app/models/` | ORM models (`Meeting`, `Participant`) |
| `backend/app/schemas/` | Pydantic request/response models, separate from the ORM models |
| `backend/app/` (files) | `main.py` app factory + `/health`, `config.py` settings from env, `db.py` engine/session, `errors.py` error envelope, `seed.py` demo data, `lambda_handler.py` AWS Lambda entry point |
| `backend/alembic/` | Database migrations (`versions/0001_create_meetings.py`) |
| `backend/tests/` | pytest suite, run against a real Postgres |
| `frontend/` | Next.js app |
| `frontend/app/` | Routes: `/` (today's meetings), `/meetings/new` (create dialog open) |
| `frontend/components/` | Page components; `components/ui/` holds the generated shadcn/ui primitives |
| `frontend/lib/` | `api.ts` typed fetch client, `types.ts` mirror of the backend schemas, date helpers |
| `frontend/hooks/` | TanStack Query hooks |
| `infra/` | CloudFormation templates for AWS (`ecr.yml`, `backend.yml`, `frontend.yml`, `github-oidc.yml`) and `certificate.sh` |
| `.github/workflows/` | `style.yml` (lint, every push), `deploy-backend.yml` (lint, test, deploy on `main`) |
| root | `docker-compose.yml`, `Makefile`, `.env.example`, `SPEC.md`, `README.md`, this file |

## API contract

Base path `/api/v1`, JSON only. **Dates:** every timestamp is ISO 8601 **with a
UTC offset** (`2026-09-10T10:00:00+03:00`); inputs without an offset are
rejected with `422`. Responses give timestamps in `APP_TIMEZONE`
(default `Europe/Kyiv`). The `date` query parameter is a plain `YYYY-MM-DD`.

### `GET /api/v1/meetings`

Meetings that **overlap** one calendar day of `APP_TIMEZONE`, sorted by
`starts_at`, then `name`.

| Query | Type | Default | Rule |
|-------|------|---------|------|
| `date` | `YYYY-MM-DD` | today in `APP_TIMEZONE` | |
| `q` | string | – | ≤ 200 chars, case-insensitive match on name/description |
| `limit` | int | 100 | 1–500 |
| `offset` | int | 0 | ≥ 0 |

`200` body:

| Field | Type |
|-------|------|
| `items` | array of `Meeting` |
| `total` | int |
| `limit` | int |
| `offset` | int |
| `date` | string, `YYYY-MM-DD` |

`Meeting`:

| Field | Type |
|-------|------|
| `id` | UUID string |
| `name` | string |
| `description` | string or `null` |
| `location` | string or `null` |
| `starts_at`, `ends_at` | ISO 8601 with offset |
| `participants` | array of `{ id: UUID, name: string, email: string or null, position: int }`, ordered by `position` (0-based) |
| `created_at`, `updated_at` | ISO 8601 with offset |

### `POST /api/v1/meetings`

Request body:

| Field | Type | Rule |
|-------|------|------|
| `name` | string | required, 1–200 chars after trimming |
| `description` | string or `null` | optional, ≤ 2000 chars |
| `location` | string or `null` | optional, ≤ 200 chars |
| `starts_at` | ISO 8601 with offset | required |
| `ends_at` | ISO 8601 with offset | required, later than `starts_at` |
| `participants` | array of `{ name: string, email?: string or null }` | optional; ≤ 50; `name` 1–120 chars; `email` a valid address; no duplicate (name, email) pairs |

`201` with a `Meeting` body and a `Location: /api/v1/meetings/{id}` header;
`422` on validation failure.

### Other endpoints

`GET /api/v1/meetings/{id}` → `200` `Meeting` or `404`.
`DELETE /api/v1/meetings/{id}` → `204` or `404`.
`GET /health` → `200` `{ "status": "ok", "database": "ok", "version": "1.0.0" }`,
`503` when the database is unreachable.

### Errors

Every non-2xx response:

```json
{ "error": { "code": "validation_error", "message": "…", "details": [{ "field": "ends_at", "message": "…" }] } }
```

Codes: `validation_error` (422), `not_found` (404), `internal_error` (500),
`service_unavailable` (503).

## Versions

| What | Version | Where |
|------|---------|-------|
| PostgreSQL | `postgres:17-alpine` | `docker-compose.yml` |
| Python | `python:3.12-slim` (local), `public.ecr.aws/lambda/python:3.12` (AWS) | `backend/Dockerfile`, `backend/Dockerfile.lambda` |
| uv | `0.12.21` | both backend Dockerfiles |
| Node.js | `node:22-alpine` | `frontend/Dockerfile`; Node 22 in CI |
| ruff | `0.16.6` | CI (`style.yml`, `deploy-backend.yml`) |
| Next.js / React | `16.3.4` / `19.2.8` (exact) | `frontend/package.json` |
| Prettier / eslint-config-prettier / eslint-config-next | `3.9.9` / `10.1.8` / `16.3.4` (exact) | `frontend/package.json` |

The other frontend packages use `^` ranges; `frontend/package-lock.json` fixes
the exact versions installed. Backend libraries (FastAPI, SQLAlchemy 2, asyncpg,
Alembic, Pydantic 2, Mangum, …) are declared as minimum versions in
`backend/pyproject.toml`, with no lockfile.

## Local services (`docker-compose.yml`)

| Service | Image / build | Port (host:container) | Depends on | Readiness check |
|---------|---------------|-----------------------|------------|-----------------|
| `db` | `postgres:17-alpine` | `${POSTGRES_PORT:-5432}:5432` | – | `pg_isready -U app -d meetings`, every 5 s, 5 s timeout, 10 retries |
| `backend` | `./backend` (`INSTALL_DEV=true`) | `${BACKEND_PORT:-8000}:8000` | `db`: `service_healthy` | `curl -fsS http://localhost:8000/health`, every 10 s, 5 s timeout, 10 retries, 20 s start period |
| `frontend` | `./frontend`, target `dev` | `${FRONTEND_PORT:-3000}:3000` | `backend`: `service_healthy` | – |

Start order is therefore: `db` healthy → `backend` starts, runs
`alembic upgrade head` from `entrypoint.sh` (when `RUN_MIGRATIONS_ON_START=true`),
then serves → `backend` healthy → `frontend` starts. Postgres data lives in the
named volume `pgdata`; `./backend` and `./frontend` are bind-mounted for live
reload. All values come from `.env` (copied from `.env.example`).
