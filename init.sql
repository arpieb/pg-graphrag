CREATE EXTENSION IF NOT EXISTS age;
CREATE EXTENSION IF NOT EXISTS vector;

-- Lets you call cypher() and use agtype without schema-qualifying them
ALTER DATABASE app SET search_path = ag_catalog, "$user", public;

LOAD 'age';
SET search_path = ag_catalog, "$user", public;
SELECT create_graph('my_graph');