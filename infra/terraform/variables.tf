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
  default     = "bookstore-k8s"
  description = "Friendly name used for tagging the vanilla Kubernetes cluster."
}

variable "admin_cidr_blocks" {
  type        = list(string)
  default     = ["0.0.0.0/0"]
  description = "CIDR blocks allowed to reach the Kubernetes API server and SSH."
}

variable "ssh_key_name" {
  type        = string
  description = "Name of an existing EC2 Key Pair to attach to control plane and worker instances."
}

variable "ssh_private_key_path" {
  type        = string
  description = "Path to the private key file that matches ssh_key_name (used for automated kubeconfig retrieval)."
}

variable "local_kubeconfig_path" {
  type        = string
  default     = "~/.kube/bookstore-config"
  description = "Local path where Terraform will store the kubeconfig for the vanilla cluster."
}

variable "control_plane_instance_type" {
  type        = string
  default     = "t3.medium"
  description = "Instance type used for the Kubernetes control plane node."
}

variable "worker_instance_type" {
  type        = string
  default     = "t3.large"
  description = "Instance type used for worker nodes that run the application workloads."
}

variable "control_plane_root_volume_size" {
  type        = number
  default     = 40
  description = "Root EBS volume size (in GiB) for the control plane instance."
}

variable "worker_root_volume_size" {
  type        = number
  default     = 50
  description = "Root EBS volume size (in GiB) for each worker node instance."
}

variable "worker_count" {
  type        = number
  default     = 2
  description = "Number of worker nodes to provision in the EC2-based Kubernetes cluster."
}

variable "pod_network_cidr" {
  type        = string
  default     = "10.244.0.0/16"
  description = "Pod network CIDR used when bootstrapping the cluster with kubeadm."
}

variable "service_cidr" {
  type        = string
  default     = "10.96.0.0/12"
  description = "Service CIDR range passed to kubeadm for the in-cluster virtual IPs."
}
