# order-service

FastAPI microservice for creating orders. Publishes an `order.created` event to RabbitMQ when enabled.

## Local development

1. Copy or adjust the provided `.env` (already created). By default, event publishing is disabled to avoid needing RabbitMQ locally.

2. Create a virtual environment and install dependencies:

```bash
python3 -m venv .venv
./.venv/bin/pip install -r src/requirements.txt
```

3. Run the service:

```bash
./.venv/bin/python src/main.py
```

The server starts on http://127.0.0.1:8000 by default. Change HOST/PORT in `.env` if needed.

### Endpoints

- GET `/healthz` – liveness probe
- POST `/orders` – create an order, returns `{ orderId, status, total }`

Example request:

```bash
curl -s http://127.0.0.1:8000/orders \
  -H 'content-type: application/json' \
  -d '{
    "userId": "user-123",
    "items": [
      {"sku": "SKU-1", "qty": 2, "price": 10.5},
      {"sku": "SKU-2", "qty": 1, "price": 3.0}
    ]
  }' | jq
```

### Event publishing

- Controlled by environment variables:
  - `ORDER_PUBLISH_ENABLED` (default `1`) – set to `0` to disable
  - `ORDER_PUBLISH_STRICT` (default `0`) – when `1`, failures to publish will raise errors
  - `RABBIT_URL` – AMQP URL (e.g., `amqp://user:pass@rabbitmq:5672/%2f`)
  - `ORDERS_EXCHANGE` – exchange name (default `orders`)

With the default `.env`, publishing is disabled so you can run without RabbitMQ.

## Docker (optional)

A `Dockerfile` is provided for container builds. For local dev, prefer running with the venv as above.
