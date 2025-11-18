data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "random_password" "kubeadm_token_id" {
  length  = 6
  special = false
  upper   = false
}

resource "random_password" "kubeadm_token_secret" {
  length  = 16
  special = false
  upper   = false
}

locals {
  kubeadm_token = format("%s.%s", random_password.kubeadm_token_id.result, random_password.kubeadm_token_secret.result)
}

resource "aws_security_group" "k8s_nodes" {
  name        = "${var.cluster_name}-nodes"
  description = "Security group for vanilla Kubernetes cluster nodes"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.admin_cidr_blocks
  }

  ingress {
    description = "Kubernetes API"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = var.admin_cidr_blocks
  }

  ingress {
    description = "NodePort range"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = var.admin_cidr_blocks
  }

  ingress {
    description = "Public HTTP edge proxy"
    from_port   = var.edge_proxy_node_port
    to_port     = var.edge_proxy_node_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Intra-cluster traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name      = "${var.cluster_name}-nodes"
    Cluster   = var.cluster_name
    ManagedBy = "terraform"
  }
}

resource "aws_security_group_rule" "k8s_nodes_internal" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 0
  protocol                 = "-1"
  security_group_id        = aws_security_group.k8s_nodes.id
  source_security_group_id = aws_security_group.k8s_nodes.id
  description              = "Allow all intra-cluster traffic"
}

resource "aws_instance" "control_plane" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.control_plane_instance_type
  subnet_id                   = module.vpc.public_subnets[0]
  associate_public_ip_address = true
  key_name                    = var.ssh_key_name
  vpc_security_group_ids      = [aws_security_group.k8s_nodes.id]

  user_data = templatefile("${path.module}/templates/control-plane.sh.tpl", {
    cluster_name     = var.cluster_name
    kubeadm_token    = local.kubeadm_token
    pod_network_cidr = var.pod_network_cidr
    service_cidr     = var.service_cidr
    api_lb_dns       = aws_lb.api.dns_name
  })
  user_data_replace_on_change = true

  root_block_device {
    volume_size           = var.control_plane_root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  tags = {
    Name      = "${var.cluster_name}-control-plane"
    Role      = "control-plane"
    Cluster   = var.cluster_name
    ManagedBy = "terraform"
  }
}

resource "aws_instance" "worker" {
  count                       = var.worker_count
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.worker_instance_type
  subnet_id                   = element(module.vpc.private_subnets, count.index % length(module.vpc.private_subnets))
  associate_public_ip_address = false
  key_name                    = var.ssh_key_name
  vpc_security_group_ids      = [aws_security_group.k8s_nodes.id]

  user_data = templatefile("${path.module}/templates/worker.sh.tpl", {
    cluster_name             = var.cluster_name
    kubeadm_token            = local.kubeadm_token
    control_plane_private_ip = aws_instance.control_plane.private_ip
    node_index               = format("%02d", count.index + 1)
  })
  user_data_replace_on_change = true

  root_block_device {
    volume_size           = var.worker_root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  tags = {
    Name      = "${var.cluster_name}-worker-${count.index + 1}"
    Role      = "worker"
    Cluster   = var.cluster_name
    ManagedBy = "terraform"
  }

  depends_on = [aws_instance.control_plane]
}

resource "null_resource" "fetch_kubeconfig" {
  depends_on = [
    aws_instance.control_plane,
    aws_lb_listener.api,
    aws_lb_target_group_attachment.api_control_plane
  ]

  triggers = {
    control_plane_id = aws_instance.control_plane.id
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      KUBECONFIG_PATH=$(eval echo "${var.local_kubeconfig_path}")
      KUBECONFIG_DIR=$(dirname "$KUBECONFIG_PATH")
      mkdir -p "$KUBECONFIG_DIR"
      if command -v realpath >/dev/null 2>&1; then
        KEY_PATH=$(realpath "${var.ssh_private_key_path}")
      else
        KEY_PATH=$(readlink -f "${var.ssh_private_key_path}")
      fi
      chmod 600 "$KEY_PATH"
      until ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=10 -i "$KEY_PATH" ubuntu@${aws_instance.control_plane.public_ip} 'sudo test -s /etc/kubernetes/admin.conf'; do
        sleep 10
      done
  ssh -o StrictHostKeyChecking=no -i "$KEY_PATH" ubuntu@${aws_instance.control_plane.public_ip} 'sudo cat /etc/kubernetes/admin.conf' > "$KUBECONFIG_PATH"
  sed -i 's#server: https://.*:6443#server: https://${aws_lb.api.dns_name}:6443#' "$KUBECONFIG_PATH"
      chmod 600 "$KUBECONFIG_PATH"
    EOT
  }
}