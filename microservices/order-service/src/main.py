from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from publisher import publish_order_created
from dotenv import load_dotenv, find_dotenv
import uuid, os, datetime, json, urllib.request, urllib.error

# Load environment variables from a .env file if present (search up the tree)
load_dotenv(find_dotenv())

app = FastAPI()
DATABASE_URL = os.getenv("DATABASE_URL", "")
PAYMENT_DEFAULT_URL = "http://payment-service.bookstore.svc.cluster.local:8080/payments"


def _truthy(value: str | None, default: bool = False) -> bool:
    if value is None:
        return default
    return value.strip().lower() in ("1", "true", "yes", "on")


def _payment_url() -> str:
    configured = (os.getenv("PAYMENT_URL") or PAYMENT_DEFAULT_URL).strip()
    if not configured:
        return PAYMENT_DEFAULT_URL
    return configured


def trigger_payment(order_id: str, user_id: str, total: float) -> dict | None:
    if total <= 0:
        return {"order_id": order_id, "status": "payment.skipped"}
    if not _truthy(os.getenv("PAYMENT_ENABLED"), True):
        return {"order_id": order_id, "status": "payment.disabled"}

    payload = json.dumps({
        "order_id": order_id,
        "user_id": user_id,
        "total_amount": total,
    }).encode("utf-8")

    req = urllib.request.Request(
        _payment_url(),
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    timeout = float(os.getenv("PAYMENT_TIMEOUT", "5"))

    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:  # nosec B310
            body = response.read().decode("utf-8") or "{}"
            result = json.loads(body)
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8") or exc.reason or str(exc.code)
        message = f"payment HTTP error: {detail}"
        print(f"[order-service] {message}")
        if _truthy(os.getenv("PAYMENT_STRICT")):
            raise HTTPException(status_code=502, detail=message) from exc
        return {"order_id": order_id, "status": "payment.error", "error": detail}
    except Exception as exc:
        message = f"payment request failed: {exc}"
        print(f"[order-service] {message}")
        if _truthy(os.getenv("PAYMENT_STRICT")):
            raise HTTPException(status_code=502, detail=message) from exc
        return {"order_id": order_id, "status": "payment.error", "error": str(exc)}

    if not isinstance(result, dict):
        result = {"order_id": order_id, "status": "payment.unknown"}

    result.setdefault("order_id", order_id)
    result.setdefault("status", "payment.unknown")
    return result

class Item(BaseModel):
    sku: str
    qty: int
    price: float


class OrderReq(BaseModel):
    userId: str
    items: list[Item]

@app.get("/healthz")
def healthz(): return {"ok": True, "db": bool(DATABASE_URL)}

@app.post("/orders")
def create_order(req: OrderReq):
    # minimal validation
    if not req.items:
        raise HTTPException(status_code=400, detail="items required")

    order_id = str(uuid.uuid4())
    created_at = datetime.datetime.utcnow().isoformat()
    raw_items = []
    order_items = []
    item_count = 0

    for item in req.items:
        raw = item.model_dump() if hasattr(item, "model_dump") else item.dict()
        qty = int(raw.get("qty", raw.get("quantity", 0)))
        price = round(float(raw.get("price", 0.0)), 2)
        line_total = round(qty * price, 2)
        item_count += qty
        order_items.append({
            "sku": raw.get("sku"),
            "quantity": qty,
            "price": price,
            "total": line_total,
        })
        raw["total"] = line_total
        raw["quantity"] = qty
        raw_items.append(raw)

    total = round(sum(line["total"] for line in order_items), 2)

    payment_result = trigger_payment(order_id, req.userId, total)

    event = {
        "event": "order.created",
        "version": 1,
        "orderId": order_id,
        "userId": req.userId,
        "items": raw_items,
        "total": total,
        "itemCount": item_count,
        "createdAt": created_at,
        "messageId": str(uuid.uuid4()),
        "correlationId": order_id,
    }
    # persist: in a real app you would save to DB (omitted here)
    publish_order_created(event)
    response = {
        "orderId": order_id,
        "status": "created",
        "total": total,
        "itemCount": item_count,
        "items": order_items,
        "createdAt": created_at,
    }
    if payment_result:
        response["payment"] = payment_result
        if isinstance(payment_result, dict):
            response["paymentStatus"] = payment_result.get("status")
    return response

# Allow running the service directly: `python main.py`
if __name__ == "__main__":
    import uvicorn
    host = os.getenv("HOST", "127.0.0.1")
    port = int(os.getenv("PORT", "8000"))
    log_level = os.getenv("LOG_LEVEL", "info")
    uvicorn.run("main:app", host=host, port=port, log_level=log_level, reload=True)
