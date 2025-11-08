output "cluster_name" {
  value       = aws_eks_cluster.this.name
  description = "EKS cluster name."
}

output "cluster_endpoint" {
  value       = aws_eks_cluster.this.endpoint
  description = "Public API endpoint for the EKS cluster."
}

output "private_subnets" {
  value       = module.vpc.private_subnets
  description = "Private subnet IDs used by EKS worker nodes."
}

output "vpc_id" {
  value       = module.vpc.vpc_id
  description = "ID of the VPC hosting the workload."
}

output "public_subnets" {
  value       = module.vpc.public_subnets
  description = "Public subnet IDs reachable from the internet (ELB/NLB)."
}

output "rds_endpoint" {
  value       = aws_db_instance.postgres.address
  description = "Hostname for the PostgreSQL RDS instance."
}

output "redis_primary_endpoint" {
  value       = local.redis_host
  description = "Primary endpoint for the ElastiCache Redis replication group."
}

output "dynamodb_table" {
  value       = aws_dynamodb_table.inventory.name
  description = "Name of the DynamoDB table backing inventory state."
}

output "rabbitmq_url" {
  value       = local.rabbitmq_url
  sensitive   = true
  description = "Internal RabbitMQ URL injected into microservices via ConfigMaps."
}

output "cart_redis_url" {
  value       = local.cart_redis_url
  description = "Redis URL used by the cart-service."
}
