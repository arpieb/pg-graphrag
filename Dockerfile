# Single source of truth for the Postgres major version. AGE must have a
# matching PG<N> branch. Override with: docker compose build --build-arg PG_MAJOR=17
ARG PG_MAJOR=16

FROM postgres:${PG_MAJOR}

# Re-declare so the value is visible after FROM (ARGs before FROM are scoped to FROM only)
ARG PG_MAJOR

# pgvector from PGDG apt; build deps for AGE
RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates \
      postgresql-${PG_MAJOR}-pgvector \
      build-essential git flex bison \
      postgresql-server-dev-${PG_MAJOR} \
 && git clone --depth 1 --branch PG${PG_MAJOR} https://github.com/apache/age.git /tmp/age \
 && cd /tmp/age && make && make install \
 && rm -rf /tmp/age \
 && apt-get purge -y build-essential git flex bison postgresql-server-dev-${PG_MAJOR} \
 && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

COPY init.sql /docker-entrypoint-initdb.d/
