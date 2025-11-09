output "cluster_name" {
  value       = var.cluster_name
  description = "Friendly name assigned to the vanilla Kubernetes cluster."
}

output "vpc_id" {
  value       = module.vpc.vpc_id
  description = "ID of the VPC hosting the Kubernetes nodes."
}

output "public_subnets" {
  value       = module.vpc.public_subnets
  description = "Public subnet IDs (control plane lives here)."
}

output "private_subnets" {
  value       = module.vpc.private_subnets
  description = "Private subnet IDs where worker nodes are scheduled."
}

output "control_plane_public_ip" {
  value       = aws_instance.control_plane.public_ip
  description = "Public IPv4 address for the control plane node (used for SSH and kubectl)."
}

output "control_plane_private_ip" {
  value       = aws_instance.control_plane.private_ip
  description = "Private IPv4 address for the control plane node."
}

output "worker_private_ips" {
  value       = aws_instance.worker[*].private_ip
  description = "Private IPv4 addresses for worker nodes."
}

output "cluster_security_group_id" {
  value       = aws_security_group.k8s_nodes.id
  description = "Security group ID attached to every Kubernetes node."
}

output "kubeadm_token" {
  value       = local.kubeadm_token
  sensitive   = true
  description = "Bootstrap token used by kubeadm to join nodes."
}

output "edge_proxy_node_port" {
  value       = 30080
  description = "NodePort used by the edge proxy service (HTTP)."
}

output "kubeconfig_path" {
  value       = var.local_kubeconfig_path
  description = "Local path where Terraform writes the kubeconfig for this cluster."
}
