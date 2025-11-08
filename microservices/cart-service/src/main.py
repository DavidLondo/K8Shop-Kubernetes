import logging
import os
import ssl
from typing import List
from urllib.parse import urlparse

from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from dotenv import load_dotenv

from .store import InMemoryCartStore, RedisCartStore

try:
    import redis  # type: ignore
    from redis.exceptions import RedisError  # type: ignore
except Exception:  # pragma: no cover
    redis = None

    class RedisError(Exception):
        """Fallback Redis error when redis client is unavailable."""
        pass

# No RabbitMQ publisher for cart-service (synchronous only)


load_dotenv()


def _setup_logging() -> logging.Logger:
    level_name = os.getenv("LOG_LEVEL", "INFO").upper()
    level = getattr(logging, level_name, logging.INFO)
    logging.basicConfig(level=level, format="[cart-service] %(levelname)s %(message)s")
    return logging.getLogger("cart-service")


logger = _setup_logging()


def getenv_bool(key: str, default: bool = False) -> bool:
    val = os.getenv(key)
    if val is None:
        return default
    return val.lower() in ("1", "true", "yes", "on")


def getenv_float(key: str, default: float) -> float:
    val = os.getenv(key)
    if val is None:
        return default
    try:
        return float(val)
    except ValueError:
        return default


HOST = os.getenv("HOST", "127.0.0.1")
PORT = int(os.getenv("PORT", "8080"))
CART_USE_REDIS = getenv_bool("CART_USE_REDIS", False)
CART_REDIS_URL = os.getenv("CART_REDIS_URL", "redis://localhost:6379/0")
CART_REDIS_SKIP_VERIFY = getenv_bool("CART_REDIS_SKIP_VERIFY", True)
CART_REDIS_SOCKET_TIMEOUT = getenv_float("CART_REDIS_SOCKET_TIMEOUT", 2.0)
DATABASE_URL = os.getenv("DATABASE_URL", "")


class AddItemRequest(BaseModel):
    productId: str = Field(..., min_length=1)
    quantity: int = Field(..., ge=1)
    price: float = Field(..., ge=0)


class UpdateQuantityRequest(BaseModel):
    quantity: int = Field(..., ge=0)


class CartItemOut(BaseModel):
    productId: str
    quantity: int
    price: float
    total: float


class CartResponse(BaseModel):
    userId: str
    items: List[CartItemOut]
    itemCount: int
    subtotal: float


def _mask_url(url: str) -> str:
    try:
        parsed = urlparse(url)
        host = parsed.hostname or ""
        port = f":{parsed.port}" if parsed.port else ""
        return f"{parsed.scheme}://{host}{port}"
    except Exception:
        return url


def _build_store():
    if not CART_USE_REDIS:
        logger.info("Redis disabled, using in-memory cart store")
        return InMemoryCartStore(), "memory"

    if redis is None:
        logger.warning("redis library unavailable, falling back to in-memory store")
        return InMemoryCartStore(), "memory"

    redis_kwargs = {
        "decode_responses": False,
        "socket_timeout": CART_REDIS_SOCKET_TIMEOUT,
        "socket_connect_timeout": CART_REDIS_SOCKET_TIMEOUT,
        "health_check_interval": 30,
        "retry_on_timeout": True,
    }

    if CART_REDIS_SKIP_VERIFY:
        redis_kwargs["ssl_cert_reqs"] = ssl.CERT_NONE

    try:
        client = redis.from_url(CART_REDIS_URL, **redis_kwargs)
        store_impl = RedisCartStore(client)
        store_impl.ping()
        logger.info("Using Redis cart store at %s", _mask_url(CART_REDIS_URL))
        if CART_REDIS_SKIP_VERIFY:
            logger.warning("TLS certificate validation disabled for Redis connection")
        return store_impl, "redis"
    except RedisError as exc:
        logger.error("Failed to initialize Redis backend: %s", exc, exc_info=True)
    except Exception as exc:  # pragma: no cover - defensive
        logger.error("Unexpected error initializing Redis backend: %s", exc, exc_info=True)

    logger.warning("Falling back to in-memory cart store")
    return InMemoryCartStore(), "memory"


store, STORE_BACKEND = _build_store()
app = FastAPI(title="cart-service")


def _cart_to_response(user_id: str) -> CartResponse:
    raw = store.get_cart(user_id)
    items: List[CartItemOut] = []
    item_count = 0
    subtotal = 0.0
    for pid, item in raw.items():
        q = int(item.get("quantity", 0))
        p = float(item.get("price", 0.0))
        t = q * p
        item_count += q
        subtotal += t
        items.append(CartItemOut(productId=pid, quantity=q, price=p, total=t))
    return CartResponse(userId=user_id, items=items, itemCount=item_count, subtotal=round(subtotal, 2))


@app.get("/healthz")
def healthz():
    try:
        if store:
            store.ping()
        return {"ok": True, "backend": STORE_BACKEND}
    except RedisError as exc:
        logger.error("Redis health check failed: %s", exc, exc_info=True)
        return JSONResponse(status_code=503, content={"ok": False, "backend": STORE_BACKEND, "error": "backend unavailable"})
    except Exception as exc:  # pragma: no cover - defensive
        logger.error("Health check failed: %s", exc, exc_info=True)
        return JSONResponse(status_code=503, content={"ok": False, "backend": STORE_BACKEND, "error": "unexpected failure"})


@app.get("/cart/{user_id}", response_model=CartResponse)
def get_cart(user_id: str):
    try:
        return _cart_to_response(user_id)
    except RedisError as exc:
        logger.error("Failed to fetch cart %s: %s", user_id, exc, exc_info=True)
        raise HTTPException(status_code=503, detail="cart backend unavailable") from exc


@app.post("/cart/{user_id}/items", response_model=CartResponse)
def add_item(user_id: str, body: AddItemRequest):
    try:
        store.add_item(user_id, body.productId, body.quantity, body.price)
        return _cart_to_response(user_id)
    except RedisError as exc:
        logger.error("Failed to add item to cart %s: %s", user_id, exc, exc_info=True)
        raise HTTPException(status_code=503, detail="cart backend unavailable") from exc


@app.put("/cart/{user_id}/items/{product_id}", response_model=CartResponse)
def update_item(user_id: str, product_id: str, body: UpdateQuantityRequest):
    try:
        store.update_item(user_id, product_id, body.quantity)
        return _cart_to_response(user_id)
    except RedisError as exc:
        logger.error("Failed to update item %s in cart %s: %s", product_id, user_id, exc, exc_info=True)
        raise HTTPException(status_code=503, detail="cart backend unavailable") from exc


@app.delete("/cart/{user_id}/items/{product_id}", response_model=CartResponse)
def delete_item(user_id: str, product_id: str):
    try:
        store.remove_item(user_id, product_id)
        return _cart_to_response(user_id)
    except RedisError as exc:
        logger.error("Failed to delete item %s from cart %s: %s", product_id, user_id, exc, exc_info=True)
        raise HTTPException(status_code=503, detail="cart backend unavailable") from exc


@app.post("/cart/{user_id}/checkout", response_model=CartResponse)
def checkout(user_id: str):
    try:
        cart = _cart_to_response(user_id)
        store.clear(user_id)
        return cart
    except RedisError as exc:
        logger.error("Failed to checkout cart %s: %s", user_id, exc, exc_info=True)
        raise HTTPException(status_code=503, detail="cart backend unavailable") from exc


@app.on_event("shutdown")
def shutdown_event():  # pragma: no cover - I/O only
    try:
        if store:
            store.close()
    except Exception:
        pass


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host=HOST, port=PORT)
