# Greenplum 7 (Docker, for local testing)

A Docker image that runs a single-node Greenplum 7 cluster in one container.
It bundles MADlib, PostGIS, PXF, and NLTK, and is ready to run SQL as soon as it
starts.

This is for local learning and testing, not for production use.

## Bundled components

| Component | Version (default) |
|---|---|
| Greenplum Database | 7.8.1 |
| PostGIS | 3.3.2 |
| MADlib | 2.2.0 |
| PXF (Platform Extension Framework) | 8.0.0 |
| OpenJDK (for PXF) | 21 |
| NLTK | latest (pip), with punkt_tab + stopwords corpora |

The cluster is single-node (1 coordinator + 1 primary segment). The coordinator
listens on port 5432 and the segment on port 6000.

## Prerequisites

- Binaries are downloaded from Broadcom (Tanzu Network / pivnet). Building
  requires a pivnet API token obtained with a valid Broadcom ID.
- The image is `linux/amd64`. On Apple Silicon it runs under Rosetta emulation
  (pass `--platform=linux/amd64`).

## Build

```
docker buildx build --platform=linux/amd64 \
  --build-arg PIVNET_API_TOKEN=<broadcom download token> \
  -t gp7 .
```

On an x86_64 host (or any environment without `buildx`), `docker build` also
works.

```
docker build --build-arg PIVNET_API_TOKEN=<broadcom download token> -t gp7 .
```

### Build arguments

| Argument | Default | Description |
|---|---|---|
| `PIVNET_API_TOKEN` | (none, required) | Broadcom download token |
| `GP_RELEASE_VERSION` | `7.8.1` | Release version of Greenplum core, MADlib, and PostGIS |
| `PXF_RELEASE_VERSION` | `8.0.0` | PXF release version (pivnet product `greenplum-pxf`). PXF 8 requires Java 17/21 |

Example using a different version:

```
docker buildx build --platform=linux/amd64 \
  --build-arg PIVNET_API_TOKEN=<token> \
  --build-arg GP_RELEASE_VERSION=7.8.0 \
  -t gp7:7.8.0 .
```

## Run

```
docker run -d --platform=linux/amd64 -p 5432:5432 --name gp7 gp7
```

On startup the container automatically:

- starts the Greenplum cluster (`gpstart`)
- starts PXF (`pxf cluster start`)
- creates a database and user (defaults: `test` / `test`)

The container is ready once `--- Ready. Tailing logs... ---` appears in
`docker logs gp7`.

Stop and remove:

```
docker stop gp7
docker rm gp7
```

### Environment variables

You can change the database and user created on startup.

| Variable | Default |
|---|---|
| `POSTGRES_DB` | `test` |
| `POSTGRES_USER` | `test` |
| `POSTGRES_PASSWORD` | `test` |

```
docker run -d --platform=linux/amd64 -p 5432:5432 \
  -e POSTGRES_DB=demo -e POSTGRES_USER=app -e POSTGRES_PASSWORD=secret \
  --name gp7 gp7
```

## Basic usage

### Databases and users

- `gpadmin`: the admin OS user and a superuser role. Its default database is
  also `gpadmin`.
- `test` (default): the database and superuser (password `test`) created on
  startup.
- The `postgis`, `madlib`, and `pxf` extensions are created in `template1`, so
  any new database (including `test`) has them available from the start.

### Connecting from inside the container

The `gpadmin` environment variables (`GPHOME`, `PXF_BASE`, `JAVA_HOME`, etc.) are
loaded by the login shell, so connect with `-u gpadmin` and a login shell
(`bash -l` / `-it ... bash`).

```
docker exec -u gpadmin -it gp7 bash
# inside the container
psql -d test -c "select version();"
```

### Connecting from the host (if psql is available)

```
psql -h localhost -p 5432 -U test -d test   # password: test
```

`pg_hba.conf` allows connections from all hosts for testing convenience.

## Using PostGIS

The `postgis` extension is already created. The `geometry` / `geography` types
and spatial functions are available directly.

```sql
-- check version
SELECT postgis_full_version();

-- create a table with latitude/longitude points
DROP TABLE IF EXISTS cities;
CREATE TABLE cities (id int, name text, geom geometry(Point,4326)) DISTRIBUTED BY (id);
INSERT INTO cities VALUES
  (1, 'Tokyo',   ST_SetSRID(ST_MakePoint(139.6917, 35.6895), 4326)),
  (2, 'Osaka',   ST_SetSRID(ST_MakePoint(135.5023, 34.6937), 4326)),
  (3, 'Sapporo', ST_SetSRID(ST_MakePoint(141.3545, 43.0618), 4326));

-- compute geodesic distance (km) from Tokyo
SELECT a.name,
       round((ST_Distance(a.geom::geography, b.geom::geography)/1000)::numeric, 1) AS km_from_tokyo
FROM cities a, cities b
WHERE b.name = 'Tokyo' AND a.name <> 'Tokyo'
ORDER BY km_from_tokyo;
--   name   | km_from_tokyo
-- ---------+---------------
--  Osaka   |         397.2
--  Sapporo |         830.9
```

## Using MADlib

The `madlib` extension is already created. Call functions in the `madlib`
schema directly.

```sql
-- check version
SELECT madlib.version();

-- linear regression example: train on data following y = 3 + 2x
DROP TABLE IF EXISTS lr_data, lr_model, lr_model_summary;
CREATE TABLE lr_data (id int, x float8, y float8) DISTRIBUTED BY (id);
INSERT INTO lr_data VALUES (1,1,5),(2,2,7),(3,3,9),(4,4,11),(5,5,13);

SELECT madlib.linregr_train('lr_data', 'lr_model', 'y', 'ARRAY[1, x]');

-- estimated coefficients (intercept, slope) and R-squared
SELECT coef, r2 FROM lr_model;
--          coef          | r2
-- -----------------------+----
--  {3.0000000,2.0000000} |  1

-- prediction (x=10 -> 23)
SELECT madlib.linregr_predict(coef, ARRAY[1, 10]) FROM lr_model;
```

Running from a file:

```
docker exec -u gpadmin -it gp7 bash -lc 'psql -d test -f /path/to/madlib_example.sql'
```

## Using PXF

PXF is registered at build time (`pxf cluster register`), and the `pxf`
extension is created in `template1`. The PXF server (JVM) starts automatically
on container startup.

```
docker exec -u gpadmin gp7 bash -lc 'pxf cluster status'
# PXF is running on 1 out of 1 hosts
```

To access an external data source, create a server definition. The example
below defines a `localfs` server that reads local files (CSV) inside the
container.

### 1. Create the server definition

Server definitions go under `$PXF_BASE/clusters/default/servers/<server-name>/`
(this PXF build keeps its configuration there).

```
docker exec -u gpadmin -it gp7 bash
# the following runs inside the container (as gpadmin)

SRV=$PXF_BASE/clusters/default/servers/localfs
mkdir -p $SRV

# point at the local filesystem
cat > $SRV/core-site.xml <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <property><name>fs.defaultFS</name><value>file:///</value></property>
</configuration>
XML

# base path allowed for access (pxf.fs.basePath is required since PXF 6)
cat > $SRV/pxf-site.xml <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <property><name>pxf.fs.basePath</name><value>/home/gpadmin</value></property>
  <property><name>pxf.service.user.impersonation</name><value>false</value></property>
</configuration>
XML

# apply the configuration
pxf cluster sync
pxf cluster restart
```

### 2. Place sample data

```
mkdir -p /home/gpadmin/pxfdata
printf '1,Alice,30\n2,Bob,25\n3,Carol,41\n' > /home/gpadmin/pxfdata/people.csv
```

### 3. Create an external table and read it

The `LOCATION` path is relative to `pxf.fs.basePath` (`/home/gpadmin` in the
example above).

```sql
CREATE EXTERNAL TABLE people_ext (id int, name text, age int)
  LOCATION ('pxf://pxfdata/people.csv?PROFILE=hdfs:csv&SERVER=localfs')
  FORMAT 'CSV';

SELECT * FROM people_ext ORDER BY id;
--  id | name  | age
-- ----+-------+-----
--   1 | Alice |  30
--   2 | Bob   |  25
--   3 | Carol |  41

SELECT count(*), round(avg(age),1) FROM people_ext;
```

For other data sources such as HDFS, S3, or JDBC, place the corresponding
configuration files (`core-site.xml`, `jdbc-site.xml`, etc.) under the same
`$PXF_BASE/clusters/default/servers/<server-name>/` directory, then apply them
with `pxf cluster sync` and `pxf cluster restart`.

## Using NLTK

NLTK (Natural Language Toolkit) is a Python library for natural language
processing. It is installed into the Python interpreter that Greenplum's
PL/Python (`plpython3u`) uses, so you can call it from SQL functions and run
text processing in the database.

```sql
CREATE EXTENSION IF NOT EXISTS plpython3u;

-- import works out of the box
CREATE OR REPLACE FUNCTION nltk_version() RETURNS text AS $$
    import nltk
    return nltk.__version__
$$ LANGUAGE plpython3u;

SELECT nltk_version();   -- e.g. 3.9.4
```

### Corpora

The `punkt_tab` tokenizer and the `stopwords` corpus are bundled (in
`/home/gpadmin/nltk_data`), so the examples below work without any download.

Other corpora and models are not included. Download the ones you need as the
`gpadmin` OS user; functions that need missing data fail with a `LookupError`
until it is present:

```
docker exec -u gpadmin gp7 bash -lc 'python3.11 -m nltk.downloader wordnet averaged_perceptron_tagger_eng'
```

This image is single-node, so downloading on the one host is enough. On a
multi-host cluster the data must exist on every segment host (or set the
`NLTK_DATA` environment variable to a shared path).

### Example

```sql
-- tokenize text (needs the punkt_tab tokenizer)
CREATE OR REPLACE FUNCTION tokenize(t text) RETURNS text[] AS $$
    import nltk
    return nltk.word_tokenize(t)
$$ LANGUAGE plpython3u;

SELECT tokenize('Greenplum runs NLTK inside the database.');
--                  tokenize
-- ---------------------------------------------
--  {Greenplum,runs,NLTK,inside,the,database,.}

-- keep content words only (needs the stopwords corpus)
CREATE OR REPLACE FUNCTION content_words(t text) RETURNS text[] AS $$
    import nltk
    from nltk.corpus import stopwords
    sw = set(stopwords.words('english'))
    return [w for w in nltk.word_tokenize(t.lower()) if w.isalpha() and w not in sw]
$$ LANGUAGE plpython3u;

SELECT content_words('Greenplum runs NLTK inside the database and it is fast');
--               content_words
-- --------------------------------------------
--  {greenplum,runs,nltk,inside,database,fast}
```

## Notes

- On Apple Silicon the amd64 binaries run under Rosetta. GP7's `gppkg` (which
  uses libssh2) cannot establish an SSH connection under emulation, so MADlib
  and PostGIS are installed by unpacking their packages, and PXF is installed
  separately.
- `gpinitsystem` occasionally hangs under emulation, so the build runs it with a
  timeout and retries up to 3 times.
