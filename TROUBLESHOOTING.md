# Troubleshooting

## Build: `git clone` fails with "Problem with the SSL CA cert"

```
fatal: unable to access 'https://github.com/apache/age.git/': Problem with the SSL CA cert (path? access rights?)
```

**Cause:** `--no-install-recommends` skips `ca-certificates`, so git can't verify GitHub's certificate. `apt-get update` still works because Debian mirrors use plain HTTP.

**Fix:** keep `ca-certificates` in the Dockerfile's `apt-get install` list. It is already there.

**Still failing?** You are probably behind a corporate proxy or VPN that inspects TLS traffic and re-signs certificates with your company's own root CA. Put that CA (PEM `.crt`) next to the Dockerfile and add, before the main `RUN`:

```dockerfile
COPY corp-root-ca.crt /usr/local/share/ca-certificates/
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
 && update-ca-certificates
```

Alternatively, clone AGE on the host, where the CA is already trusted, and `COPY` the source into the image instead of cloning during the build.

## `function cypher(unknown, unknown) does not exist`

**Cause:** `ag_catalog`, the schema that holds `cypher()` and `agtype`, isn't on your session's `search_path`.

`shared_preload_libraries=age` does **not** fix this. Preloading loads AGE's C library into each backend; `search_path` controls name lookup. They are separate settings.

**Fix:** pick one:

- Per session: `SET search_path = ag_catalog, "$user", public;`
- Per role: `ALTER ROLE app SET search_path = ag_catalog, "$user", public;`
- Schema-qualify names: `ag_catalog.cypher(...) AS (r ag_catalog.agtype)`

`init.sql` already sets the database default, but some clients override it when they connect (see DBeaver below).

## `relation "ag_catalog.ag_graph" does not exist`

**Cause:** the AGE extension isn't installed in the database you're connected to.

1. Check `SELECT current_database();`. If it returns `postgres`, you're in the wrong database. Connect to `app`.
2. If you *are* in `app`, `init.sql` didn't run, most likely because the volume already existed:

   ```bash
   docker compose logs db | grep -iE "init.sql|error|skipping"
   docker compose down -v && docker compose up -d   # deletes all data
   ```

## Verifying the server without a GUI client

```bash
docker compose exec db psql -U app -d app -c \
  "SELECT extname, extversion FROM pg_extension; SELECT name FROM ag_catalog.ag_graph;"
```

You should see `age`, `vector` and `my_graph`. If you do, the server is fine and any remaining problem is in the client's settings.

## DBeaver

DBeaver has two defaults that cause both of the errors above:

1. **It connects to the `postgres` database.** Edit the connection → *Main* → set *Database* to `app`.
2. **It sets `search_path` to its "active schema"**, overriding the database and role defaults. Edit the connection → *Connection settings → Initialization → Bootstrap queries* and add:

   ```sql
   SET search_path = ag_catalog, "$user", public;
   ```

   `LOAD 'age';` isn't needed because AGE is preloaded.

## Changes to `init.sql` have no effect

The Postgres image runs `/docker-entrypoint-initdb.d/` scripts only when the data directory is empty. Rebuild and reset the volume:

```bash
docker compose down -v && docker compose up -d --build
```

Or apply the change by hand with `psql` if you need to keep the data.
