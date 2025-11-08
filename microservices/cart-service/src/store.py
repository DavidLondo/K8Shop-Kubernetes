import json
from typing import Dict, Any, Optional


class InMemoryCartStore:
    def __init__(self):
        # { user_id: { product_id: {"quantity": int, "price": float} } }
        self._data: Dict[str, Dict[str, Dict[str, Any]]] = {}

    def get_cart(self, user_id: str) -> Dict[str, Dict[str, Any]]:
        return self._data.get(user_id, {}).copy()

    def add_item(self, user_id: str, product_id: str, quantity: int, price: float):
        user_cart = self._data.setdefault(user_id, {})
        item = user_cart.get(product_id)
        if item:
            item["quantity"] += quantity
            item["price"] = price
        else:
            user_cart[product_id] = {"quantity": quantity, "price": price}

    def update_item(self, user_id: str, product_id: str, quantity: int):
        user_cart = self._data.get(user_id)
        if not user_cart:
            return
        if quantity <= 0:
            user_cart.pop(product_id, None)
            return
        if product_id in user_cart:
            user_cart[product_id]["quantity"] = quantity

    def remove_item(self, user_id: str, product_id: str):
        user_cart = self._data.get(user_id)
        if not user_cart:
            return
        user_cart.pop(product_id, None)

    def clear(self, user_id: str):
        self._data.pop(user_id, None)

    def ping(self) -> bool:
        return True

    def close(self) -> None:  # pragma: no cover - no-op for in-memory store
        return


class RedisCartStore:
    def __init__(self, redis_client):
        self.r = redis_client

    def _key(self, user_id: str) -> str:
        return f"cart:{user_id}"

    def get_cart(self, user_id: str) -> Dict[str, Dict[str, Any]]:
        data = self.r.hgetall(self._key(user_id))
        # decode bytes to str and parse json
        cart: Dict[str, Dict[str, Any]] = {}
        for k, v in data.items():
            pid = k.decode() if isinstance(k, (bytes, bytearray)) else str(k)
            try:
                item = json.loads(v)
            except Exception:
                continue
            cart[pid] = item
        return cart

    def add_item(self, user_id: str, product_id: str, quantity: int, price: float):
        key = self._key(user_id)
        current_raw: Optional[bytes] = self.r.hget(key, product_id)
        if current_raw:
            try:
                item = json.loads(current_raw)
            except Exception:
                item = {"quantity": 0, "price": price}
            item["quantity"] = int(item.get("quantity", 0)) + quantity
            item["price"] = price
        else:
            item = {"quantity": quantity, "price": price}
        self.r.hset(key, product_id, json.dumps(item))

    def update_item(self, user_id: str, product_id: str, quantity: int):
        key = self._key(user_id)
        if quantity <= 0:
            self.r.hdel(key, product_id)
            return
        current_raw: Optional[bytes] = self.r.hget(key, product_id)
        if not current_raw:
            return
        try:
            item = json.loads(current_raw)
        except Exception:
            item = {"quantity": quantity}
        item["quantity"] = quantity
        self.r.hset(key, product_id, json.dumps(item))

    def remove_item(self, user_id: str, product_id: str):
        self.r.hdel(self._key(user_id), product_id)

    def clear(self, user_id: str):
        self.r.delete(self._key(user_id))

    def ping(self) -> bool:
        return bool(self.r.ping())

    def close(self) -> None:
        try:
            self.r.close()
        except Exception:
            pass
