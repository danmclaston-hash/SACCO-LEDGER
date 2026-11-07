#!/bin/bash
# Why: proves the money rules on a real Postgres. Needs local Postgres, set PGHOST PGUSER PGPASSWORD.
# Success: last line shows failed = 0. Failure: it prints which rule broke.
set -eo pipefail
cd "$(dirname "$0")"
dropdb --if-exists sacco_test; createdb sacco_test
psql -q -c "do \$\$ begin create role anon nologin; exception when duplicate_object then null; end \$\$; do \$\$ begin create role authenticated nologin; exception when duplicate_object then null; end \$\$;"
sed "/^create role/d" auth_stub.sql | psql sacco_test -q -v ON_ERROR_STOP=1
psql sacco_test -q -v ON_ERROR_STOP=1 -f ../migrations/20261106000000_init.sql
psql sacco_test -q -v ON_ERROR_STOP=1 -f run_tests.sql 2>&1 | grep -vE 'create_goal|close_goal|set_payment_goal|record_sign_in|update_my_profile|request_account|cancel_account|complete_account|^\s*$|^-+$|^\(1 row\)|set_config|as_user|^ +ok *$|^ +fails *$|^ +put *$|review_payment|record_payment|^ +[0-9a-f-]{36}$|^ +\{|open_meeting|^ +t$|close_meeting|execute_shareout|set_attendance|reverse_journal|disburse_loan|approve_loan' | tail -8
