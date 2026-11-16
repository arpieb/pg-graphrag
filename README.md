# pg-graphrag

A single PostgreSQL server that can act as the whole storage layer for a graph-RAG system:

- **[Apache AGE](https://age.apache.org/)** for the knowledge graph, queried with openCypher
- **[pgvector](https://github.com/pgvector/pgvector)** for embeddings and approximate-nearest-neighbour search (HNSW / IVFFlat)
- Ordinary Postgres tables for documents, chunks and metadata

Keeping all three in one database means one connection, one backup, and SQL joins between vector hits and graph traversals. You don't have to sync separate vector and graph stores.

## Quick start

```bash
docker compose up -d --build
```

The first build compiles AGE from source and takes a few minutes. After that the server listens on `localhost:5432`.

| Setting  | Value |
|----------|-------|
| Host     | `localhost` |
| Port     | `5432` |
| Database | `app` (**not** `postgres`) |
| User     | `app` |
| Password | `app` |

```bash
docker compose exec db psql -U app -d app
```

## What's in the box

| File | Purpose |
|------|---------|
| `Dockerfile` | `postgres:${PG_MAJOR}` (default 16) with pgvector (apt, PGDG) and AGE built from the matching `PG<N>` branch of the AGE repo |
| `init.sql` | Runs **once**, on first start with an empty volume. Creates both extensions, sets the database's default `search_path` to include `ag_catalog`, and creates the graph `my_graph` |
| `docker-compose.yml` | Single `db` service with AGE preloaded (`shared_preload_libraries=age`) and data in the `pgdata` named volume |

## Using it

Every session that runs Cypher needs `ag_catalog` on its `search_path`. The database default sets this, but some clients override it. DBeaver is one; see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

```sql
SET search_path = ag_catalog, "$user", public;
```

### Graph (openCypher)

```sql
SELECT * FROM cypher('my_graph', $$
  CREATE (:Doc {id: 1, title: 'hello'})-[:CITES]->(:Doc {id: 2, title: 'world'})
$$) AS (r agtype);
```

Every `cypher()` call needs an `AS (...)` column list typed as `agtype`.

### Vectors

```sql
CREATE TABLE doc_embeddings (doc_id int PRIMARY KEY, embedding vector(3));
INSERT INTO doc_embeddings VALUES (1, '[1,0,0]'), (2, '[0.9,0.1,0]');
CREATE INDEX ON doc_embeddings USING hnsw (embedding vector_cosine_ops);
```

Use your embedding model's dimension in place of `3`, for example `vector(1536)`.

### Graph-RAG: vector search, then graph expansion

```sql
WITH nearest AS (
  SELECT doc_id FROM doc_embeddings
  ORDER BY embedding <=> '[1,0,0]' LIMIT 5
)
SELECT * FROM cypher('my_graph', $$
  MATCH (a:Doc)-[:CITES]->(b:Doc) RETURN a.id, b.title
$$) AS (a_id agtype, b_title agtype)
WHERE a_id::text::int IN (SELECT doc_id FROM nearest);
```

**Design rule:** store embeddings in regular tables, not in graph node properties. AGE properties are `agtype`, which pgvector can't index. Link the two with a shared id (here `Doc.id` ↔ `doc_embeddings.doc_id`).

## Lifecycle

```bash
docker compose down        # stop; data is kept
docker compose down -v     # stop AND delete all data; init.sql runs again next start
docker compose build --no-cache   # rebuild the image from scratch
```

## Changing the Postgres version

The version is set in one place: `ARG PG_MAJOR=16` at the top of the `Dockerfile`. It controls the base image, the pgvector package and the AGE branch. AGE publishes one branch per Postgres major version (`PG13` through `PG17`, as of this writing), so pick a version that has a branch.

Edit the default, or override it for a single build:

```bash
docker compose build --build-arg PG_MAJOR=17
```

Then run `docker compose down -v && docker compose up -d`. Data directories don't carry across major versions, so this deletes your data. Dump it first if you need to keep it.

## Security note

The credentials are dev defaults and the port is bound on all interfaces. Before deploying anywhere shared, change the password, consider binding to `127.0.0.1:5432:5432`, and move credentials into an `.env` file.

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
