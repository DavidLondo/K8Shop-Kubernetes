#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${DATABASE_URL:-}" ]]; then
  echo "DATABASE_URL must be set (postgres connection string with admin privileges)" >&2
  exit 1
fi

psql "${DATABASE_URL}" -f "$(dirname "$0")/db-bootstrap.sql" \
  -v catalog_password="${DB_PASS_CATALOG:-changeme_catalog}" \
  -v order_password="${DB_PASS_ORDER:-changeme_order}" \
  -v payment_password="${DB_PASS_PAYMENT:-changeme_payment}" \
  -v recommendation_password="${DB_PASS_RECOMMENDATION:-changeme_recommendation}"

psql "${DATABASE_URL}" -f "$(dirname "$0")/db-seed.sql"
