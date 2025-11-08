# cart-service

FastAPI microservice for shopping cart operations with Redis backend (in-memory fallback).

- Endpoints:
  - `GET /healthz`
  - `GET /cart/{userId}`
  - `POST /cart/{userId}/items` body: `{ productId, quantity, price }`
  - `PUT /cart/{userId}/items/{productId}` body: `{ quantity }`
  - `DELETE /cart/{userId}/items/{productId}`
  - `POST /cart/{userId}/checkout` (limpia el carrito y devuelve el snapshot)

## Env vars

- `HOST` (default `127.0.0.1`)
- `PORT` (default `8080`)
- `CART_USE_REDIS` (default `0`)
- `CART_REDIS_URL` (default `redis://localhost:6379/0`)
- No usa RabbitMQ (servicio síncrono)

A sample `.env` is included.

## Run locally

```bash
# from microservices/cart-service
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
uvicorn src.main:app --host 127.0.0.1 --port 8080
```

## Try it

```bash
# health
curl -s http://127.0.0.1:8080/healthz | jq

# add item
curl -s -X POST http://127.0.0.1:8080/cart/u1/items \
  -H 'Content-Type: application/json' \
  -d '{"productId":"p1","quantity":2,"price":10.5}' | jq

# update quantity
curl -s -X PUT http://127.0.0.1:8080/cart/u1/items/p1 \
  -H 'Content-Type: application/json' \
  -d '{"quantity":3}' | jq

# checkout
curl -s -X POST http://127.0.0.1:8080/cart/u1/checkout | jq
```

## Docker

```bash
# build
docker build -t cart-service:local .
# run
docker run --rm -p 8080:8080 -e HOST=0.0.0.0 -e PORT=8080 cart-service:local
```

## Kubernetes

Update the `image:` in `k8s/deployment.yaml` and apply:

```bash
kubectl apply -f k8s/deployment.yaml
```
