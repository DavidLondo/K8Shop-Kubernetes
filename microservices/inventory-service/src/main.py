import json
import logging
import os
from collections import defaultdict
from datetime import datetime, timezone
from typing import Dict, List, Optional
from urllib import error as urlerror
from urllib import request as urlrequest

from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel
from dotenv import load_dotenv, find_dotenv

# Load env from .env if present (useful for local development/tests)
load_dotenv(find_dotenv())

try:
    import boto3  # type: ignore
    from botocore.exceptions import BotoCoreError, ClientError  # type: ignore
except Exception:  # pragma: no cover - boto3 always available in cluster image
    boto3 = None
    BotoCoreError = ClientError = Exception

try:
    import pika  # type: ignore
except Exception:  # pragma: no cover - optional dependency
    pika = None


def _setup_logger() -> logging.Logger:
    level_name = os.getenv("LOG_LEVEL", "INFO").upper()
    level = getattr(logging, level_name, logging.INFO)
    logging.basicConfig(level=level, format="[inventory-service] %(levelname)s %(message)s")
    return logging.getLogger("inventory-service")


logger = _setup_logger()

app = FastAPI()

# Environment configuration

def _detect_aws_region() -> Optional[str]:
    # Prefer explicit configuration via env vars
    env_region = os.getenv("AWS_REGION") or os.getenv("AWS_DEFAULT_REGION")
    if env_region:
        return env_region

    # Fall back to boto3 auto-discovery if available
    if boto3 is not None:
        try:
            session = boto3.session.Session()
            if session.region_name:
                return session.region_name
        except Exception:
            pass

    # Attempt to obtain the region from EC2 instance metadata (IMDSv2)
    if os.getenv("AWS_EC2_METADATA_DISABLED", "").lower() in ("1", "true", "yes", "on"):
        return None

    try:
        token_req = urlrequest.Request(
            "http://169.254.169.254/latest/api/token",
            method="PUT",
            headers={"X-aws-ec2-metadata-token-ttl-seconds": "21600"},
        )
        with urlrequest.urlopen(token_req, timeout=1) as resp:
            token = resp.read().decode("utf-8")

        doc_req = urlrequest.Request(
            "http://169.254.169.254/latest/dynamic/instance-identity/document",
            headers={"X-aws-ec2-metadata-token": token},
        )
        with urlrequest.urlopen(doc_req, timeout=1) as resp:
            document = json.loads(resp.read().decode("utf-8"))
            return document.get("region")
    except (urlerror.URLError, TimeoutError, ValueError, json.JSONDecodeError):
        logger.warning("Unable to determine AWS region automatically; set AWS_REGION env var")
    except Exception:
        logger.warning("Unexpected error determining AWS region", exc_info=True)
    return None


AWS_REGION = _detect_aws_region()
DDB_TABLE = os.getenv("DDB_TABLE", "")
DDB_ENDPOINT_URL = os.getenv("DDB_ENDPOINT_URL")
DESCRIBE_WARNING_EMITTED = False

# Optional RabbitMQ integration
PUBLISH_ENABLED = os.getenv("INVENTORY_PUBLISH_ENABLED", "0").lower() in ("1", "true", "yes", "on")
PUBLISH_STRICT = os.getenv("INVENTORY_PUBLISH_STRICT", "0").lower() in ("1", "true", "yes", "on")
RABBIT_URL = os.getenv("INVENTORY_RABBIT_URL", os.getenv("RABBIT_URL", "amqp://guest:guest@localhost:5672/%2f"))


class Item(BaseModel):
    sku: str
    qty: int


class InventoryReq(BaseModel):
    order_id: str
    items: List[Item]


class InventoryResp(BaseModel):
    order_id: str
    status: str


class InventoryStoreError(Exception):
    """Base exception for inventory store failures."""


class OutOfStockError(InventoryStoreError):
    """Raised when requested quantity exceeds available stock."""


class InventoryStore:  # pragma: no cover - interface definition
    backend: str = "unknown"

    def ping(self) -> None:
        raise NotImplementedError

    def apply(self, items: Dict[str, int]) -> Dict[str, object]:
        raise NotImplementedError

    def close(self) -> None:
        return


class InMemoryInventoryStore(InventoryStore):
    backend = "memory"

    def __init__(self):
        self._data: Dict[str, int] = {}

    def ping(self) -> None:
        return

    def apply(self, items: Dict[str, int]) -> Dict[str, object]:
        for sku, qty in items.items():
            available = self._data.get(sku, 0)
            if available < qty:
                raise OutOfStockError(f"insufficient stock for {sku}")
        for sku, qty in items.items():
            self._data[sku] = self._data.get(sku, 0) - qty
        return {"status": "updated", "backend": self.backend}


class DynamoInventoryStore(InventoryStore):
    backend = "dynamodb"

    def __init__(self, table):
        self.table = table
        self.client = table.meta.client

    def ping(self) -> None:
        global DESCRIBE_WARNING_EMITTED
        try:
            self.client.describe_table(TableName=self.table.name)
        except ClientError as exc:  # pragma: no cover - network/aws failure
            error = exc.response.get("Error", {})
            code = error.get("Code")
            message = error.get("Message", "")
            if code == "AccessDeniedException" and "dynamodb:DescribeTable" in message:
                if not DESCRIBE_WARNING_EMITTED:
                    logger.warning("DescribeTable access denied; skipping table health check")
                    DESCRIBE_WARNING_EMITTED = True
                else:
                    logger.debug("DescribeTable access denied; skipping table health check")
                return
            raise InventoryStoreError(f"describe_table failed: {error}") from exc
        except BotoCoreError as exc:  # pragma: no cover - network/aws failure
            raise InventoryStoreError(f"dynamodb ping failed: {exc}") from exc

    def apply(self, items: Dict[str, int]) -> Dict[str, object]:
        if not items:
            return {"status": "noop"}
        if len(items) > 25:
            raise InventoryStoreError("DynamoDB transaction limit exceeded (max 25 unique SKUs per order)")

        now = datetime.now(timezone.utc).isoformat()
        transact_items = []
        for sku, qty in items.items():
            if qty <= 0:
                continue
            transact_items.append({
                "Update": {
                    "TableName": self.table.name,
                    "Key": {"sku": {"S": sku}},
                    "UpdateExpression": "SET #stock = #stock - :qty, updated_at = :ts",
                    "ConditionExpression": "attribute_exists(#stock) AND #stock >= :qty",
                    "ExpressionAttributeNames": {
                        "#stock": "stock",
                    },
                    "ExpressionAttributeValues": {
                        ":qty": {"N": str(qty)},
                        ":ts": {"S": now},
                    },
                }
            })

        if not transact_items:
            return {"status": "noop"}

        try:
            response = self.client.transact_write_items(
                TransactItems=transact_items,
                ReturnConsumedCapacity="TOTAL"
            )
            return {
                "status": "updated",
                "consumed_capacity": response.get("ConsumedCapacity", []),
            }
        except ClientError as exc:
            code = exc.response.get("Error", {}).get("Code")
            if code == "ConditionalCheckFailedException":
                raise OutOfStockError("requested quantity exceeds available stock") from exc
            raise InventoryStoreError(f"dynamodb transaction failed: {code}") from exc
        except BotoCoreError as exc:
            raise InventoryStoreError(f"dynamodb request failed: {exc}") from exc


def aggregate_items(items: List[Item]) -> Dict[str, int]:
    aggregated: Dict[str, int] = defaultdict(int)
    for entry in items:
        if entry.qty <= 0:
            continue
        aggregated[entry.sku] += entry.qty
    return dict(aggregated)


def publish_inventory_updated(event: dict) -> None:
    if not PUBLISH_ENABLED:
        logger.debug("Publish disabled, skipping event for %s", event.get("order_id"))
        return
    if pika is None:
        logger.warning("pika not available; cannot publish inventory.updated event")
        if PUBLISH_STRICT:
            raise RuntimeError("RabbitMQ publishing required but pika not installed")
        return
    try:
        params = pika.URLParameters(RABBIT_URL)
        conn = pika.BlockingConnection(params)
        channel = conn.channel()
        channel.queue_declare(queue="inventory.updated", durable=True)
        channel.basic_publish(
            exchange="",
            routing_key="inventory.updated",
            body=json.dumps(event),
            properties=pika.BasicProperties(content_type="application/json", delivery_mode=2),
        )
        logger.info("Published inventory.updated for %s", event.get("order_id"))
        conn.close()
    except Exception as exc:  # pragma: no cover - network failure
        logger.error("Publish failed for %s: %s", event.get("order_id"), exc)
        if PUBLISH_STRICT:
            raise


def build_store() -> InventoryStore:
    if boto3 is None:
        logger.warning("boto3 not available; falling back to in-memory inventory store")
        return InMemoryInventoryStore()
    if not DDB_TABLE:
        raise RuntimeError("DDB_TABLE environment variable must be set for DynamoDB inventory store")
    if not AWS_REGION:
        raise RuntimeError("AWS region could not be determined; set AWS_REGION or AWS_DEFAULT_REGION")

    session_kwargs = {}
    if AWS_REGION:
        session_kwargs["region_name"] = AWS_REGION
    session = boto3.session.Session(**session_kwargs)
    resource_kwargs = {}
    if DDB_ENDPOINT_URL:
        resource_kwargs["endpoint_url"] = DDB_ENDPOINT_URL
    dynamodb = session.resource("dynamodb", **resource_kwargs)
    store = DynamoInventoryStore(dynamodb.Table(DDB_TABLE))
    store.ping()
    logger.info("Using DynamoDB table %s in region %s", DDB_TABLE, AWS_REGION)
    return store


store = build_store()


@app.get("/healthz")
def healthz():
    try:
        store.ping()
        return {"ok": True, "backend": getattr(store, "backend", "unknown")}
    except InventoryStoreError as exc:
        logger.error("Health check failed: %s", exc)
        return JSONResponse(status_code=503, content={"ok": False, "backend": getattr(store, "backend", "unknown"), "error": "store unavailable"})


@app.post("/inventory/apply", response_model=InventoryResp)
def apply_inventory(req: InventoryReq):
    items = aggregate_items(req.items)
    if not items:
        raise HTTPException(status_code=400, detail="items required")

    event_payload = [item.model_dump() for item in req.items]

    try:
        result = store.apply(items)
        status = "inventory.updated"
        logger.info("Reserved stock for %s (result=%s)", req.order_id, result)
    except OutOfStockError as exc:
        status = "inventory.failed"
        logger.warning("Out of stock processing order %s: %s", req.order_id, exc)
    except InventoryStoreError as exc:
        logger.error("Inventory store failure for order %s: %s", req.order_id, exc, exc_info=True)
        raise HTTPException(status_code=503, detail="inventory store unavailable") from exc

    event = {"order_id": req.order_id, "status": status, "items": event_payload}
    if status == "inventory.failed":
        event["reason"] = "out_of_stock"
    publish_inventory_updated(event)
    return InventoryResp(order_id=req.order_id, status=status)


@app.on_event("shutdown")
def shutdown_event():  # pragma: no cover - side effects only
    try:
        store.close()
    except Exception:
        pass


if __name__ == "__main__":  # pragma: no cover - manual execution
    import uvicorn

    host = os.getenv("HOST", "127.0.0.1")
    port = int(os.getenv("PORT", "8080"))
    uvicorn.run("main:app", host=host, port=port, reload=True)
