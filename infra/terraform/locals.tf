locals {
  rabbitmq_internal_host = "rabbitmq.bookstore.svc.cluster.local"
  rabbitmq_url           = format("amqp://%s:%s@%s:5672/", var.rabbitmq_user, var.rabbitmq_password, local.rabbitmq_internal_host)
  redis_host             = aws_elasticache_replication_group.redis.primary_endpoint_address
  cart_redis_url         = format("rediss://%s:6379/0", local.redis_host)
  service_db_schemas = {
    "cart-service"           = "cart"
    "catalog-service"        = "catalog"
    "inventory-service"      = "inventory"
    "order-service"          = "order"
    "payment-service"        = "payment"
    "recommendation-service" = "recommendation"
  }
  service_db_urls = {
    for svc, schema in local.service_db_schemas :
    svc => format(
      "postgres://%s:%s@%s:5432/%s?sslmode=require&options=-c%%20search_path%%3D%s",
      var.db_user,
      var.db_password,
      aws_db_instance.postgres.address,
      var.db_name,
      schema
    )
  }
}
