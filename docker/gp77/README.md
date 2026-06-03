# Greenplum 7 (Docker, ローカルテスト用)

単一ノードの Greenplum 7 クラスタを 1 コンテナで動かすための Docker イメージです。
MADlib・PostGIS・PXF・NLTK を同梱し、起動するとすぐに SQL を実行できます。

本番用途ではなく、ローカルでの学習・検証用です。

## 同梱コンポーネント

| コンポーネント | バージョン（既定） |
|---|---|
| Greenplum Database | 7.8.1 |
| PostGIS | 3.3.2 |
| MADlib | 2.2.0 |
| PXF (Platform Extension Framework) | 8.0.0 |
| OpenJDK (PXF 用) | 21 |
| NLTK | 最新 (pip) |

構成は単一ノード（coordinator 1 + primary segment 1）。coordinator はポート 5432、
segment はポート 6000 を使います。

## 前提

- バイナリは Broadcom (Tanzu Network / pivnet) からダウンロードします。ビルドには
  有効な Broadcom ID で取得した pivnet API トークンが必要です。
- イメージは `linux/amd64` です。Apple Silicon では Rosetta エミュレーションで動作します
  （`--platform=linux/amd64` を指定）。

## ビルド方法

```
docker buildx build --platform=linux/amd64 \
  --build-arg PIVNET_API_TOKEN=<broadcom download token> \
  -t gp7 .
```

`buildx` を使わない環境（x86_64 ホストなど）では `docker build` でもビルドできます。

```
docker build --build-arg PIVNET_API_TOKEN=<broadcom download token> -t gp7 .
```

### ビルド引数

| 引数 | 既定値 | 説明 |
|---|---|---|
| `PIVNET_API_TOKEN` | （なし・必須） | Broadcom のダウンロードトークン |
| `GP_RELEASE_VERSION` | `7.8.1` | Greenplum 本体・MADlib・PostGIS のリリースバージョン |
| `PXF_RELEASE_VERSION` | `8.0.0` | PXF のリリースバージョン（pivnet 製品 `greenplum-pxf`）。PXF 8 は Java 17/21 が必須 |

別バージョンを使う例:

```
docker buildx build --platform=linux/amd64 \
  --build-arg PIVNET_API_TOKEN=<token> \
  --build-arg GP_RELEASE_VERSION=7.8.0 \
  -t gp7:7.8.0 .
```

## 起動方法

```
docker run -d --platform=linux/amd64 -p 5432:5432 --name gp7 gp7
```

起動時に次の処理が自動で行われます。

- Greenplum クラスタの起動（`gpstart`）
- PXF の起動（`pxf cluster start`）
- データベースとユーザーの作成（既定は `test` / `test`）

`docker logs gp7` に `--- Ready. Tailing logs... ---` が出れば利用可能です。

停止・削除:

```
docker stop gp7
docker rm gp7
```

### 環境変数

起動時に作成するデータベースとユーザーを変更できます。

| 環境変数 | 既定値 |
|---|---|
| `POSTGRES_DB` | `test` |
| `POSTGRES_USER` | `test` |
| `POSTGRES_PASSWORD` | `test` |

```
docker run -d --platform=linux/amd64 -p 5432:5432 \
  -e POSTGRES_DB=demo -e POSTGRES_USER=app -e POSTGRES_PASSWORD=secret \
  --name gp7 gp7
```

## 基本的な使い方

### データベース・ユーザー

- `gpadmin`: 管理用 OS ユーザー兼スーパーユーザーロール。既定の接続先データベースも `gpadmin`。
- `test` (既定): 起動時に作成されるデータベースとスーパーユーザー（パスワード `test`）。
- `postgis` / `madlib` / `pxf` 拡張は `template1` に作成済みのため、`test` を含む新規データベースは
  これらを最初から利用できます。

### コンテナ内から接続する

`gpadmin` の環境変数（`GPHOME` / `PXF_BASE` / `JAVA_HOME` など）はログインシェルで読み込まれるため、
`-u gpadmin` かつログインシェル（`bash -l` / `-it ... bash`）で入るのが確実です。

```
docker exec -u gpadmin -it gp7 bash
# コンテナ内
psql -d test -c "select version();"
```

### ホストから接続する（psql がある場合）

```
psql -h localhost -p 5432 -U test -d test   # パスワード: test
```

`pg_hba.conf` は検証用に全ホストからの接続を許可しています。

## PostGIS の使い方

`postgis` 拡張は作成済みです。`geometry` / `geography` 型と空間関数をそのまま利用できます。

```sql
-- バージョン確認
SELECT postgis_full_version();

-- 緯度経度を持つテーブルを作成する
DROP TABLE IF EXISTS cities;
CREATE TABLE cities (id int, name text, geom geometry(Point,4326)) DISTRIBUTED BY (id);
INSERT INTO cities VALUES
  (1, 'Tokyo',   ST_SetSRID(ST_MakePoint(139.6917, 35.6895), 4326)),
  (2, 'Osaka',   ST_SetSRID(ST_MakePoint(135.5023, 34.6937), 4326)),
  (3, 'Sapporo', ST_SetSRID(ST_MakePoint(141.3545, 43.0618), 4326));

-- Tokyo からの距離 (km) を測地距離で計算する
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

## MADlib の使い方

`madlib` 拡張は作成済みです。スキーマ `madlib` の関数をそのまま呼び出せます。

```sql
-- バージョン確認
SELECT madlib.version();

-- 線形回帰の例: y = 3 + 2x のデータを学習する
DROP TABLE IF EXISTS lr_data, lr_model, lr_model_summary;
CREATE TABLE lr_data (id int, x float8, y float8) DISTRIBUTED BY (id);
INSERT INTO lr_data VALUES (1,1,5),(2,2,7),(3,3,9),(4,4,11),(5,5,13);

SELECT madlib.linregr_train('lr_data', 'lr_model', 'y', 'ARRAY[1, x]');

-- 推定された係数（切片, 傾き）と決定係数
SELECT coef, r2 FROM lr_model;
--          coef          | r2
-- -----------------------+----
--  {3.0000000,2.0000000} |  1

-- 予測 (x=10 -> 23)
SELECT madlib.linregr_predict(coef, ARRAY[1, 10]) FROM lr_model;
```

実行例:

```
docker exec -u gpadmin -it gp7 bash -lc 'psql -d test -f /path/to/madlib_example.sql'
```

## PXF の使い方

PXF はビルド時に登録（`pxf cluster register`）され、`pxf` 拡張は `template1` に作成済みです。
PXF サーバー（JVM）は起動時に自動で開始します。

```
docker exec -u gpadmin gp7 bash -lc 'pxf cluster status'
# PXF is running on 1 out of 1 hosts
```

外部データソースにアクセスするには「サーバー定義」を作成します。以下はコンテナ内の
ローカルファイル（CSV）を読む `localfs` サーバーの例です。

### 1. サーバー定義を作成する

サーバー定義は `$PXF_BASE/clusters/default/servers/<サーバー名>/` に置きます
（このビルドの PXF では設定はここに集約されます）。

```
docker exec -u gpadmin -it gp7 bash
# 以下はコンテナ内（gpadmin）

SRV=$PXF_BASE/clusters/default/servers/localfs
mkdir -p $SRV

# ローカルファイルシステムを参照する
cat > $SRV/core-site.xml <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <property><name>fs.defaultFS</name><value>file:///</value></property>
</configuration>
XML

# アクセスを許可する基準パス（pxf.fs.basePath は PXF 6 以降で必須）
cat > $SRV/pxf-site.xml <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <property><name>pxf.fs.basePath</name><value>/home/gpadmin</value></property>
  <property><name>pxf.service.user.impersonation</name><value>false</value></property>
</configuration>
XML

# 設定を反映
pxf cluster sync
pxf cluster restart
```

### 2. サンプルデータを置く

```
mkdir -p /home/gpadmin/pxfdata
printf '1,Alice,30\n2,Bob,25\n3,Carol,41\n' > /home/gpadmin/pxfdata/people.csv
```

### 3. 外部テーブルを作成して読む

`LOCATION` のパスは `pxf.fs.basePath`（上の例では `/home/gpadmin`）からの相対パスです。

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

HDFS・S3・JDBC など他のデータソースを使う場合も、同じく
`$PXF_BASE/clusters/default/servers/<サーバー名>/` に対応する設定ファイル
（`core-site.xml`、`jdbc-site.xml` など）を置き、`pxf cluster sync` と
`pxf cluster restart` で反映します。

## 補足

- Apple Silicon では amd64 バイナリを Rosetta で実行します。GP7 の `gppkg`（libssh2 使用）は
  エミュレーション下で SSH 接続できないため、MADlib・PostGIS はパッケージ展開で導入しています。
  PXF は別途インストールしています。
- `gpinitsystem` はエミュレーション下でまれにハングするため、ビルドはタイムアウト付きで最大 3 回
  リトライします。
