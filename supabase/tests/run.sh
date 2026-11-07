#!/bin/bash
# Why: proves the money rules on a real Postgres. Needs local Postgres, set PGHOST PGUSER PGPASSWORD.
# Success: the last line says how many checks passed. Failure: it stops and prints which rule broke.
set -eo pipefail
cd "$(dirname "$0")"
dropdb --if-exists sacco_test; createdb sacco_test
psql sacco_test -q -v ON_ERROR_STOP=1 -f auth_stub.sql
psql sacco_test -q -v ON_ERROR_STOP=1 -f ../migrations/20261106000000_init.sql
# Query results are only noise here. Errors still show, because they go to stderr.
PGOPTIONS="-c client_min_messages=warning" psql sacco_test -q -v ON_ERROR_STOP=1 -f run_tests.sql > /dev/null
psql sacco_test -tAq -c "select 'passed: ' || count(*) from t.res"
