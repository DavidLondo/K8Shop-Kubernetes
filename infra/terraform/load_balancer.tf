locals {
  edge_proxy_lb_name = substr("${var.cluster_name}-edge", 0, 32)
}

resource "aws_lb" "edge_proxy" {
  name               = local.edge_proxy_lb_name
  load_balancer_type = "network"
  internal           = false
  subnets            = module.vpc.public_subnets

  enable_deletion_protection = false

  tags = {
    Name      = local.edge_proxy_lb_name
    Role      = "edge-proxy"
    Cluster   = var.cluster_name
    ManagedBy = "terraform"
  }
}

resource "aws_lb_target_group" "edge_proxy" {
  name        = substr("${var.cluster_name}-edge-tg", 0, 32)
  port        = var.edge_proxy_node_port
  protocol    = "TCP"
  target_type = "instance"
  vpc_id      = module.vpc.vpc_id

  health_check {
    port     = "traffic-port"
    protocol = "TCP"
  }

  tags = {
    Name      = substr("${var.cluster_name}-edge-tg", 0, 32)
    Role      = "edge-proxy"
    Cluster   = var.cluster_name
    ManagedBy = "terraform"
  }
}

resource "aws_lb_listener" "edge_proxy_http" {
  load_balancer_arn = aws_lb.edge_proxy.arn
  port              = 80
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.edge_proxy.arn
  }
}

resource "aws_lb_target_group_attachment" "edge_proxy_workers" {
  count            = var.worker_count
  target_group_arn = aws_lb_target_group.edge_proxy.arn
  target_id        = aws_instance.worker[count.index].id
  port             = var.edge_proxy_node_port
}
