# CLAUDE.md

## Purpose

A one-stop Docker setup for a single PostgreSQL server that serves as the storage layer for a graph-RAG system: Apache AGE (openCypher graph) and pgvector (embeddings) in one database. Keep it minimal. It is infrastructure, not an application.

## Layout

- `Dockerfile`: `postgres:${PG_MAJOR}` + `postgresql-${PG_MAJOR}-pgvector` (PGDG apt) + AGE compiled from the `PG${PG_MAJOR}` branch of github.com/apache/age (default 16). Build deps are purged in the same `RUN` layer.
- `init.sql`: first-start only. Creates the extensions, sets the `app` database's `search_path`, and creates graph `my_graph`.
- `docker-compose.yml`: service `db`, AGE in `shared_preload_libraries`, named volume `pgdata`, credentials `app`/`app`/`app`.
- `README.md`: user-facing setup and usage. `TROUBLESHOOTING.md`: known failures and fixes.

## Commands

```bash
docker compose up -d --build                     # build and start
docker compose exec db psql -U app -d app        # shell
docker compose down -v && docker compose up -d   # reset data; re-runs init.sql
```

Smoke test after any change:

```bash
docker compose exec db psql -U app -d app -c \
  "SELECT extname, extversion FROM pg_extension; SELECT name FROM ag_catalog.ag_graph;"
```

## Invariants and gotchas

- **Keep `ca-certificates` in the apt install list.** With `--no-install-recommends` it isn't pulled in, and the AGE `git clone` then fails TLS verification.
- **Postgres version is set only by `ARG PG_MAJOR` at the top of the `Dockerfile`.** It drives the base image, the pgvector package and the AGE branch. Never hardcode a version number elsewhere. The `ARG` has to be declared before `FROM` and declared again after it. Only use versions AGE has a `PG<N>` branch for.
- **`init.sql` runs only on an empty volume.** Changes to it need `down -v` (destroys data) or a manual migration.
- **The database is `app`, not `postgres`.** Extensions exist only in `app`.
- **`cypher()`/`agtype` live in `ag_catalog`.** Sessions need it on `search_path`, or need to schema-qualify. `shared_preload_libraries` only loads the library; it doesn't affect name resolution.
- **Every `cypher()` call needs `AS (col agtype, ...)`.** Cast results with `::text::int` etc. before joining to regular columns.
- **Embeddings go in regular tables with `vector(N)` columns, never in graph node properties** (`agtype` can't be indexed by pgvector). Link to nodes by a shared id property.

## Conventions

- When you fix a new failure mode, add it to `TROUBLESHOOTING.md` (symptom → cause → fix).
- Don't commit real credentials. The defaults are for local development only.
