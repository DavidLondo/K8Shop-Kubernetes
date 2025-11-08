variable "access_key" {
  description = "AWS access key"
  type        = string
  sensitive   = true
}

variable "secret_key" {
  description = "AWS secret key"
  type        = string
  sensitive   = true
}

variable "session_token" {
  description = "AWS session token"
  type        = string
  sensitive   = true
}

variable "region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region where all resources are provisioned."
}

variable "cluster_name" {
  type        = string
  default     = "bookstore-eks"
  description = "Friendly name for the EKS cluster."
}

variable "admin_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDR blocks allowed to reach the EKS public endpoint."
}

variable "cluster_iam_role_arn" {
  type        = string
  description = "Existing IAM role ARN to associate with the EKS control plane."
}

variable "node_type" {
  type        = string
  default     = "t3.large"
  description = "Instance type used by the EKS managed node group."
}

variable "node_iam_role_arn" {
  type        = string
  description = "Existing IAM role ARN used by the EKS managed node group."
}

variable "desired" {
  type        = number
  default     = 3
  description = "Desired number of worker nodes for the EKS node group."
}

variable "min" {
  type        = number
  default     = 3
  description = "Minimum number of worker nodes for the EKS node group."
}

variable "max" {
  type        = number
  default     = 9
  description = "Maximum number of worker nodes for the EKS node group."
}

variable "db_user" {
  type        = string
  description = "Master username for the PostgreSQL instance."
}

variable "db_password" {
  type        = string
  description = "Master password for the PostgreSQL instance."
  sensitive   = true
}

variable "db_name" {
  type        = string
  default     = "bookstore"
  description = "Logical database name used by the application tier."
}

variable "rabbitmq_user" {
  type        = string
  default     = "user"
  description = "Username used by application services when connecting to RabbitMQ inside the cluster."
}

variable "rabbitmq_password" {
  type        = string
  default     = "password"
  description = "Password used by application services when connecting to RabbitMQ inside the cluster."
  sensitive   = true
}
