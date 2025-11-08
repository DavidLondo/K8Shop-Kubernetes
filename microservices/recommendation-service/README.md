# recommendation-service

A small Go HTTP service that returns product recommendations.

- Endpoints:
  - `GET /healthz` → `{ "ok": true }`
  - `GET /recommendations?productId=<id>&userId=<id>&strategy=<popular|related>&limit=<n>`

## Env vars

- `HOST` (default `127.0.0.1`)
- `PORT` (default `8080`)
- `REC_STRATEGY` default recommendation strategy (`popular` or `related`, default `popular`)
- `REC_LIMIT` default number of items (default `5`)

A sample `.env` is included for local runs.

## Run locally

```bash
# from microservices/recommendation-service
cp .env .env.local 2>/dev/null || true
# optional: tweak .env.local

# run
go build ./cmd/recommendation-service && ./recommendation-service
# or
HOST=127.0.0.1 PORT=8080 go run ./cmd/recommendation-service
```

## Try it

```bash
# health
curl -s http://127.0.0.1:8080/healthz | jq

# recommendations (popular)
curl -s 'http://127.0.0.1:8080/recommendations?limit=3' | jq

# recommendations related to a product
curl -s 'http://127.0.0.1:8080/recommendations?productId=sku-123&strategy=related&limit=5' | jq
```

## Docker

```bash
# build image
docker build -t recommendation-service:local .

# run container
docker run --rm -p 8080:8080 -e HOST=0.0.0.0 -e PORT=8080 recommendation-service:local
```

## Kubernetes

Edit the `image:` field in `k8s/deployment.yaml` to your registry and apply:

```bash
kubectl apply -f k8s/deployment.yaml
```
