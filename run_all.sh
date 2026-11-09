#!/usr/bin/env bash
# One command rebuilds everything: database -> data -> schema -> cleaning -> analysis -> optimisation -> charts.
# Usage:  ./run_all.sh                      (uses libpq defaults / PG* environment variables)
#         PGHOST=/tmp PGPORT=5433 PGUSER=postgres ./run_all.sh
# Needs: PostgreSQL 13+ (tested on 16), psql on PATH, Python 3 with pandas + numpy (+ matplotlib for charts).
set -euo pipefail
cd "$(dirname "$0")"
export PGDATABASE="${PGDATABASE:-olist_retention}"
ADMIN_DB="${ADMIN_DB:-postgres}"
DB_LOCALE="${DB_LOCALE:-C.UTF-8}"     # on macOS/Windows try DB_LOCALE=en_US.UTF-8
P="psql -X -q -P pager=off -v ON_ERROR_STOP=1"
mkdir -p results/plans data

echo "[0/8] (re)creating database $PGDATABASE"
psql -X -q -d "$ADMIN_DB" -c "DROP DATABASE IF EXISTS \"$PGDATABASE\" WITH (FORCE)"   # FORCE needs PostgreSQL 13+
psql -X -q -d "$ADMIN_DB" -c "CREATE DATABASE \"$PGDATABASE\" TEMPLATE template0 ENCODING 'UTF8' LC_COLLATE '$DB_LOCALE' LC_CTYPE '$DB_LOCALE'" 2>/dev/null \
 || psql -X -q -d "$ADMIN_DB" -c "CREATE DATABASE \"$PGDATABASE\" TEMPLATE template0 ENCODING 'UTF8'"

echo "[1/8] data: using data/*.csv if present, otherwise generating synthetic data"
[ -f data/orders.csv ] || python3 00_data/generate_synthetic_olist.py data

echo "[2/8] schema + load"
$P -f 01_schema/01_staging.sql
$P -f 01_schema/02_load_staging.sql
$P -f 01_schema/03_schema.sql

echo "[3/8] cleaning + validation"
$P -f 02_cleaning/01_dq_checks.sql   > results/02a_data_quality_report_raw.txt
$P -f 02_cleaning/02_transform.sql
$P -f 02_cleaning/03_validation.sql  > results/02c_validation_after_cleaning.txt

echo "[4/8] analysis queries -> results/"
$P -f 03_analysis/00_base_views.sql
for f in 03_analysis/q*.sql; do
  name=$(basename "$f" .sql)
  PGOPTIONS='-c statement_timeout=120000' $P -f "$f" > "results/$name.txt"
  echo "      $name"
done

echo "[5/8] engineering layer (materialised view, functions, transaction demo)"
$P -f 04_optimization/01_materialized_view.sql
$P -f 04_optimization/02_functions.sql > results/04b_functions_demo.txt
$P -f 04_optimization/03_transaction_demo.sql > results/04c_transaction_demo.txt

echo "[6/8] index benchmark: EXPLAIN ANALYZE before vs after"
python3 04_optimization/bench_explain.py

echo "[7/8] charts"
python3 05_charts/make_charts.py || echo "      (charts skipped: matplotlib missing?)"
echo "[8/8] independent verification (pandas vs PostgreSQL)"
python3 tests/verify_with_pandas.py | tee results/verification_pandas_vs_postgres.txt
echo "done. Outputs are in results/ and docs/"
