import os, json, time

# Publishing controls (enable/disable and strict failure behavior)
ORDER_PUBLISH_ENABLED = os.getenv("ORDER_PUBLISH_ENABLED", "1").lower() in ("1", "true", "yes", "on")
ORDER_PUBLISH_STRICT = os.getenv("ORDER_PUBLISH_STRICT", "0").lower() in ("1", "true", "yes", "on")

RABBIT_URL = os.getenv("RABBIT_URL", "amqp://user:pass@rabbitmq:5672/%2f")
EXCHANGE = os.getenv("ORDERS_EXCHANGE", "orders")

def _connect():
    # Import pika lazily so local runs without broker can still start the app
    import pika
    params = pika.URLParameters(RABBIT_URL)
    for _ in range(5):
        try:
            return pika.BlockingConnection(params)
        except Exception as e:
            print("[order-service] RabbitMQ connection failed, retrying...", e)
            time.sleep(2)
    raise RuntimeError("Could not connect to RabbitMQ")

def publish_order_created(event: dict):
    """Publish order.created event.

    Behavior:
    - If ORDER_PUBLISH_ENABLED is false, this becomes a no-op.
    - If enabled but broker is unreachable:
      - When ORDER_PUBLISH_STRICT is true -> raises.
      - Otherwise -> logs a warning and returns.
    """
    if not ORDER_PUBLISH_ENABLED:
        print("[order-service] publish disabled (ORDER_PUBLISH_ENABLED=0); skipping publish for", event.get("orderId"))
        return

    try:
        # Import pika here as well (mirrors lazy import in _connect)
        import pika
        conn = _connect()
        ch = conn.channel()
        ch.exchange_declare(exchange=EXCHANGE, exchange_type='topic', durable=True)
        body = json.dumps(event)
        ch.basic_publish(
            exchange=EXCHANGE,
            routing_key="orders.order_created",
            body=body,
            properties=pika.BasicProperties(
                content_type='application/json',
                delivery_mode=2,
                message_id=event["messageId"],
                correlation_id=event["correlationId"],
            ),
        )
        print("[order-service] published order.created", event["orderId"])
        conn.close()
    except Exception as e:
        msg = f"[order-service] publish failed: {e}"
        if ORDER_PUBLISH_STRICT:
            raise RuntimeError(msg)
        print(msg)
