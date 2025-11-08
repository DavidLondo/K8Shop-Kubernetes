# payment-service

Minimal Go service to simulate payments via HTTP. Optionally publishes results to RabbitMQ when enabled.

## Local development

1. Ensure Go 1.22+ is installed.
2. Copy `.env` (already provided) or adjust as needed. Publishing is disabled by default.
3. Run:

```bash
cd microservices/payment-service
go run ./cmd/payment-service
```

It will start on http://127.0.0.1:8080.

### Endpoints

- GET `/healthz` – returns `{ "ok": true }`
- POST `/payments` – body:

```json
{
  "order_id": "123",
  "user_id": "u1",
  "total_amount": 25.0
}
```

Response:

```json
{ "order_id": "123", "status": "payment.succeeded" }
```

The result is randomized (default 20% failure). Control with `PAYMENT_FAIL_PROB`.

### Event publishing (optional)

- Set `PAYMENT_PUBLISH_ENABLED=1` and `PAYMENT_RABBIT_URL` to publish to queues `payment.succeeded` or `payment.failed`.
- Set `PAYMENT_PUBLISH_STRICT=1` to fail the request if publishing fails.

## Docker

```bash
cd microservices/payment-service
docker build -t payment-service:local .
```

Run:

```bash
docker run --rm -p 8080:8080 --env-file .env payment-service:local
```
