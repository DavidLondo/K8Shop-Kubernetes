#!/usr/bin/env bash
set -euo pipefail

TABLE_NAME=${TABLE_NAME:-bookstore-inventory}
AWS_REGION=${AWS_REGION:-us-east-1}

if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI is required to seed DynamoDB" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to build the seed payload" >&2
  exit 1
fi

items_json=$(cat <<'JSON'
[
  {"sku": "BOOK-001", "stock": 45},
  {"sku": "BOOK-002", "stock": 32},
  {"sku": "BOOK-003", "stock": 27},
  {"sku": "BOOK-004", "stock": 60},
  {"sku": "BOOK-005", "stock": 80},
  {"sku": "BOOK-006", "stock": 22}
]
JSON
)

tmpfile=$(mktemp)
payload_file=$(mktemp)
trap 'rm -f "$tmpfile" "$payload_file"' EXIT

echo "$items_json" > "$tmpfile"

timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

jq --arg table "$TABLE_NAME" --arg ts "$timestamp" '
  {($table): map({
    PutRequest: {
      Item: {
        sku:   {S: .sku},
        stock: {N: (.stock | tostring)},
        updated_at: {S: $ts}
      }
    }
  })}
' "$tmpfile" > "$payload_file"

aws dynamodb batch-write-item \
  --region "$AWS_REGION" \
  --request-items "file://$payload_file"
