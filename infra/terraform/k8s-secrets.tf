resource "null_resource" "k8s_bootstrap" {
  depends_on = [
    aws_eks_node_group.general,
    aws_db_instance.postgres,
    aws_elasticache_replication_group.redis,
    aws_dynamodb_table.inventory,
  ]

  triggers = {
    redis_host      = local.redis_host
    rabbitmq_url    = local.rabbitmq_url
    cart_redis_url  = local.cart_redis_url
    rds_endpoint    = aws_db_instance.postgres.address
    db_user         = var.db_user
    db_name         = var.db_name
    db_password_sum = sha256(nonsensitive(var.db_password))
    ddb_table       = aws_dynamodb_table.inventory.name
    db_urls_hash    = sha256(jsonencode(local.service_db_urls))
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      kubectl get ns bookstore >/dev/null 2>&1 || kubectl create ns bookstore

      kubectl apply -f - <<'EOF'
      apiVersion: v1
      kind: Secret
      metadata:
        name: datastore-secrets
        namespace: bookstore
      type: Opaque
      stringData:
        DB_HOST: "${aws_db_instance.postgres.address}"
        DB_USER: "${var.db_user}"
        DB_PASSWORD: "${var.db_password}"
      EOF

      kubectl apply -f - <<'EOF'
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: runtime-config
        namespace: bookstore
      data:
        DB_NAME: "${var.db_name}"
        RABBIT_URL: "${local.rabbitmq_url}"
        NOTIF_RABBIT_URL: "${local.rabbitmq_url}"
        PAYMENT_RABBIT_URL: "${local.rabbitmq_url}"
        CART_REDIS_URL: "${local.cart_redis_url}"
        REDIS_HOST: "${local.redis_host}"
        DDB_TABLE: "${aws_dynamodb_table.inventory.name}"
      EOF

      kubectl apply -f - <<'EOF'
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: catalog-service-config
        namespace: bookstore
      data:
        HOST: "0.0.0.0"
        PORT: "8080"
        CATALOG_GRPC_HOST: "0.0.0.0"
        CATALOG_GRPC_PORT: "50051"
      EOF

      kubectl apply -f - <<'EOF'
      apiVersion: v1
      kind: Secret
      metadata:
        name: catalog-service-db
        namespace: bookstore
      type: Opaque
      stringData:
        DATABASE_URL: "${local.service_db_urls["catalog-service"]}"
        DB_SCHEMA: "${local.service_db_schemas["catalog-service"]}"
      EOF

      kubectl apply -f - <<'EOF'
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: cart-service-config
        namespace: bookstore
      data:
        HOST: "0.0.0.0"
        PORT: "8080"
        CART_USE_REDIS: "1"
      EOF

      kubectl apply -f - <<'EOF'
      apiVersion: v1
      kind: Secret
      metadata:
        name: cart-service-db
        namespace: bookstore
      type: Opaque
      stringData:
        DATABASE_URL: "${local.service_db_urls["cart-service"]}"
        DB_SCHEMA: "${local.service_db_schemas["cart-service"]}"
      EOF

      kubectl apply -f - <<'EOF'
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: inventory-service-config
        namespace: bookstore
      data:
        HOST: "0.0.0.0"
        PORT: "8080"
        INVENTORY_PUBLISH_ENABLED: "1"
        INVENTORY_PUBLISH_STRICT: "0"
      EOF

      kubectl apply -f - <<'EOF'
      apiVersion: v1
      kind: Secret
      metadata:
        name: inventory-service-db
        namespace: bookstore
      type: Opaque
      stringData:
        DATABASE_URL: "${local.service_db_urls["inventory-service"]}"
        DB_SCHEMA: "${local.service_db_schemas["inventory-service"]}"
      EOF

      kubectl apply -f - <<'EOF'
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: notification-service-config
        namespace: bookstore
      data:
        HOST: "0.0.0.0"
        PORT: "8080"
        NOTIF_CONSUME_ENABLED: "1"
        NOTIF_EXCHANGE: "orders"
        NOTIF_QUEUE_NAME: "notification-service"
      EOF

      kubectl apply -f - <<'EOF'
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: order-service-config
        namespace: bookstore
      data:
        HOST: "0.0.0.0"
        PORT: "8000"
        ORDER_PUBLISH_ENABLED: "1"
        ORDER_PUBLISH_STRICT: "0"
        ORDERS_EXCHANGE: "orders"
      EOF

      kubectl apply -f - <<'EOF'
      apiVersion: v1
      kind: Secret
      metadata:
        name: order-service-db
        namespace: bookstore
      type: Opaque
      stringData:
        DATABASE_URL: "${local.service_db_urls["order-service"]}"
        DB_SCHEMA: "${local.service_db_schemas["order-service"]}"
      EOF

      kubectl apply -f - <<'EOF'
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: payment-service-config
        namespace: bookstore
      data:
        HOST: "0.0.0.0"
        PORT: "8080"
        PAYMENT_PUBLISH_ENABLED: "1"
        PAYMENT_PUBLISH_STRICT: "0"
        PAYMENT_FAIL_PROB: "20"
      EOF

      kubectl apply -f - <<'EOF'
      apiVersion: v1
      kind: Secret
      metadata:
        name: payment-service-db
        namespace: bookstore
      type: Opaque
      stringData:
        DATABASE_URL: "${local.service_db_urls["payment-service"]}"
        DB_SCHEMA: "${local.service_db_schemas["payment-service"]}"
      EOF

      kubectl apply -f - <<'EOF'
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: recommendation-service-config
        namespace: bookstore
      data:
        HOST: "0.0.0.0"
        PORT: "8080"
        REC_STRATEGY: "popular"
        REC_LIMIT: "5"
        CATALOG_GRPC_ADDR: "catalog-service.bookstore.svc.cluster.local:50051"
      EOF

      kubectl apply -f - <<'EOF'
      apiVersion: v1
      kind: Secret
      metadata:
        name: recommendation-service-db
        namespace: bookstore
      type: Opaque
      stringData:
        DATABASE_URL: "${local.service_db_urls["recommendation-service"]}"
        DB_SCHEMA: "${local.service_db_schemas["recommendation-service"]}"
      EOF
    EOT
  }
}
