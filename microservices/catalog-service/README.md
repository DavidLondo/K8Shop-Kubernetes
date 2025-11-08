# catalog-service

Node.js service for listing products and product details. Purely synchronous (no RabbitMQ).

## Local development

```bash
cd microservices/catalog-service
npm install
npm start
```

Default: http://127.0.0.1:8080

### Endpoints
- GET `/healthz` → `{ "ok": true }`
- GET `/catalog` → list products, supports filters:
  - `q` (search in title or sku)
  - `min` (min price)
  - `max` (max price)
  - `tag` (filter by tag)

Example:
```bash
curl 'http://127.0.0.1:8080/catalog?q=mouse&max=30'
```

- GET `/catalog/:id` → by product `id` or `sku` (e.g., `p-100` or `SKU-100`)

## Docker

```bash
cd microservices/catalog-service
docker build -t catalog-service:local .
docker run --rm -p 8080:8080 --env-file .env catalog-service:local
```

## Kubernetes (EKS)

Update image in `k8s/deployment.yaml` and apply:
```bash
kubectl apply -f microservices/catalog-service/k8s/deployment.yaml
```
