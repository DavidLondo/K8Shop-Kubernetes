# notification-service

Node.js notification microservice with optional RabbitMQ consumer and HTTP endpoints for local testing.

## Local development

```bash
cd microservices/notification-service
npm install
npm start
```

- Default host/port: http://127.0.0.1:8080
- The consumer is disabled by default via `.env` → set `NOTIF_CONSUME_ENABLED=1` and `NOTIF_RABBIT_URL` to enable.

### Endpoints
- GET `/healthz` → `{ "ok": true }`
- POST `/notify` → Simulate sending a notification without RabbitMQ

Body:
```json
{ "order_id": "o-123", "status": "payment.succeeded" }
```
Or:
```json
{ "order_id": "o-123", "type": "failure" }
```

## Docker

```bash
cd microservices/notification-service
docker build -t notification-service:local .
# Run locally
docker run --rm -p 8080:8080 --env-file .env notification-service:local
```

## Kubernetes (EKS)

Update the image in `k8s/deployment.yaml` and apply:

```bash
kubectl apply -f microservices/notification-service/k8s/deployment.yaml
```

Make sure the `rabbitmq` Service is available in the namespace and adjust `NOTIF_RABBIT_URL` accordingly if needed.
