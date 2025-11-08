# inventory-service

FastAPI service that simulates inventory updates. Optionally publishes `inventory.updated` events to RabbitMQ.

## Local development

```bash
cd microservices/inventory-service
python3 -m venv .venv
./.venv/bin/pip install -r requirements.txt
./.venv/bin/python src/main.py
```

By default it binds to http://127.0.0.1:8080 and publishing is disabled.

### Endpoints

- GET `/healthz` → `{ "ok": true }`
- POST `/inventory/apply`

Request body:
```json
{
  "order_id": "o-123",
  "items": [ { "sku": "SKU-1", "qty": 2 } ]
}
```
Response:
```json
{ "order_id": "o-123", "status": "inventory.updated" }
```
Note: 75% success probability. When it fails → `inventory.failed`.

### Event publishing (optional)
- `INVENTORY_PUBLISH_ENABLED=1` to publish to queue `inventory.updated`.
- `RABBIT_URL=amqp://user:pass@host:5672/%2f`
- `INVENTORY_PUBLISH_STRICT=1` to fail on publish errors.

## Docker

A simple Dockerfile is provided; for local dev, prefer running via venv.
