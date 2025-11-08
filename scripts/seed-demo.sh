#!/usr/bin/env bash
set -euo pipefail

NAMESPACE=${NAMESPACE:-bookstore}
PG_SECRET=${PG_SECRET:-catalog-service-db}
PG_KEY=${PG_KEY:-DATABASE_URL}
AWS_REGION=${AWS_REGION:-us-east-1}
DDB_TABLE=${DDB_TABLE:-bookstore-inventory}
REPO_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CATALOG_JOB=${CATALOG_JOB:-seed-catalog}

if ! command -v kubectl >/dev/null 2>&1; then
  echo "kubectl is required to fetch secrets" >&2
  exit 1
fi

if ! command -v base64 >/dev/null 2>&1; then
  echo "base64 utility is required" >&2
  exit 1
fi

pg_url=$(kubectl -n "$NAMESPACE" get secret "$PG_SECRET" -o jsonpath="{.data.$PG_KEY}" 2>/dev/null | base64 --decode)
if [[ -z "${pg_url}" ]]; then
  echo "Failed to resolve PostgreSQL URL from secret ${PG_SECRET} in namespace ${NAMESPACE}" >&2
  exit 1
fi

sql_payload=$(base64 -w0 "$REPO_HOME/scripts/db-seed.sql")

echo "[seed-demo] Seeding PostgreSQL catalog data from inside the cluster..."
kubectl -n "$NAMESPACE" delete pod "$CATALOG_JOB" --ignore-not-found >/dev/null
kubectl -n "$NAMESPACE" run "$CATALOG_JOB" \
  --restart=Never \
  --image=postgres:16 \
  --env="PGURL=${pg_url}" \
  --env="SQL_B64=${sql_payload}" \
  --command -- bash -c 'set -euo pipefail; echo "$SQL_B64" | base64 -d > /tmp/db-seed.sql; psql "$PGURL" -f /tmp/db-seed.sql'
kubectl -n "$NAMESPACE" wait --for=condition=Ready pod/$CATALOG_JOB --timeout=120s >/dev/null 2>&1 || true
kubectl -n "$NAMESPACE" logs "$CATALOG_JOB"

catalog_status=""
for _ in {1..30}; do
  catalog_status=$(kubectl -n "$NAMESPACE" get pod "$CATALOG_JOB" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
  if [[ "$catalog_status" == "Succeeded" ]]; then
    break
  fi
  if [[ "$catalog_status" == "Failed" ]]; then
    echo "Catalog seed pod exited with status: $catalog_status" >&2
    kubectl -n "$NAMESPACE" describe pod "$CATALOG_JOB" >&2
    kubectl -n "$NAMESPACE" logs "$CATALOG_JOB" >&2 || true
    kubectl -n "$NAMESPACE" delete pod "$CATALOG_JOB" >/dev/null 2>&1 || true
    exit 1
  fi
  sleep 2
done

if [[ "$catalog_status" != "Succeeded" ]]; then
  echo "Catalog seed pod did not complete successfully (status='$catalog_status')" >&2
  kubectl -n "$NAMESPACE" describe pod "$CATALOG_JOB" >&2
  kubectl -n "$NAMESPACE" logs "$CATALOG_JOB" >&2 || true
  kubectl -n "$NAMESPACE" delete pod "$CATALOG_JOB" >/dev/null 2>&1 || true
  exit 1
fi
kubectl -n "$NAMESPACE" delete pod "$CATALOG_JOB" >/dev/null

echo "[seed-demo] Seeding DynamoDB inventory data via inventory-service pod..."
inventory_pod=$(kubectl -n "$NAMESPACE" get pods -l app=inventory-service -o jsonpath='{.items[0].metadata.name}')
if [[ -z "${inventory_pod}" ]]; then
  echo "Unable to find a running inventory-service pod" >&2
  exit 1
fi

set +e
kubectl -n "$NAMESPACE" exec -i "$inventory_pod" -- env AWS_REGION="$AWS_REGION" DDB_TABLE="$DDB_TABLE" python - <<'PY'
import datetime
import os

import boto3
from botocore.exceptions import ClientError

AWS_REGION = os.environ.get('AWS_REGION', 'us-east-1')
DDB_TABLE = os.environ.get('DDB_TABLE', 'bookstore-inventory')

items = [
    {"sku": "BOOK-001", "stock": 45},
    {"sku": "BOOK-002", "stock": 32},
    {"sku": "BOOK-003", "stock": 27},
    {"sku": "BOOK-004", "stock": 60},
    {"sku": "BOOK-005", "stock": 80},
    {"sku": "BOOK-006", "stock": 22},
]

session = boto3.session.Session(region_name=AWS_REGION)
client = session.client('dynamodb')
ts = datetime.datetime.utcnow().replace(microsecond=0).isoformat() + 'Z'

for item in items:
    try:
        client.update_item(
            TableName=DDB_TABLE,
            Key={'sku': {'S': item['sku']}},
            UpdateExpression='SET #stock = :stock, updated_at = :ts',
            ExpressionAttributeNames={'#stock': 'stock'},
            ExpressionAttributeValues={
                ':stock': {'N': str(item['stock'])},
                ':ts': {'S': ts},
            },
        )
    except ClientError as exc:
        code = exc.response.get('Error', {}).get('Code')
        raise SystemExit(f"Failed to seed DynamoDB item {item['sku']}: {code}") from exc

print(f"Seeded {len(items)} inventory items into {DDB_TABLE} ({AWS_REGION})", flush=True)
PY
ddb_status=$?
set -e

if [[ $ddb_status -ne 0 ]]; then
  echo "[seed-demo] WARNING: DynamoDB seed failed (exit code $ddb_status)." >&2
  echo "[seed-demo] If your IAM role blocks write access, seed manually with:" >&2
  echo "    TABLE_NAME=${DDB_TABLE} AWS_REGION=${AWS_REGION} ./scripts/seed-dynamodb.sh" >&2
else
  echo "[seed-demo] DynamoDB seed complete."
fi

echo "[seed-demo] Seed complete."
