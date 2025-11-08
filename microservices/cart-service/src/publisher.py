import os, json, time

# Optional publishing controls
CART_PUBLISH_ENABLED = os.getenv("CART_PUBLISH_ENABLED", "0").lower() in ("1", "true", "yes", "on")
CART_PUBLISH_STRICT = os.getenv("CART_PUBLISH_STRICT", "0").lower() in ("1", "true", "yes", "on")

RABBIT_URL = os.getenv("RABBIT_URL", "amqp://guest:guest@localhost:5672/")
EXCHANGE = os.getenv("ORDERS_EXCHANGE", "orders")


def _connect():
    # Import pika lazily so local runs without broker can still start the app
    import pika
    params = pika.URLParameters(RABBIT_URL)
    for _ in range(5):
        try:
            return pika.BlockingConnection(params)
        except Exception as e:
            print("[cart-service] RabbitMQ connection failed, retrying...", e)
            time.sleep(2)
    raise RuntimeError("Could not connect to RabbitMQ")


def publish_cart_checked_out(event: dict):
    """Publish cart.checked_out event.

    Behavior:
    - If CART_PUBLISH_ENABLED is false, this becomes a no-op.
    - If enabled but broker is unreachable:
      - When CART_PUBLISH_STRICT is true -> raises.
      - Otherwise -> logs a warning and returns.
    """
    if not CART_PUBLISH_ENABLED:
        print("[cart-service] publish disabled (CART_PUBLISH_ENABLED=0); skipping publish for", event.get("userId"))
        return

    try:
        import pika
        conn = _connect()
        ch = conn.channel()
        ch.exchange_declare(exchange=EXCHANGE, exchange_type='topic', durable=True)
        body = json.dumps(event)
        ch.basic_publish(
            exchange=EXCHANGE,
            routing_key="orders.cart_checked_out",
            body=body,
            properties=pika.BasicProperties(
                content_type='application/json',
                delivery_mode=2,
                message_id=event.get("messageId"),
                correlation_id=event.get("correlationId"),
            ),
        )
        print("[cart-service] published cart.checked_out for user", event.get("userId"))
        conn.close()
    except Exception as e:
        msg = f"[cart-service] publish failed: {e}"
        if CART_PUBLISH_STRICT:
            raise RuntimeError(msg)
        print(msg)
