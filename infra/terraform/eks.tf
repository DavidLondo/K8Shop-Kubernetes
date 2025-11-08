resource "aws_eks_cluster" "this" {
	name     = var.cluster_name
	version  = "1.29"
	role_arn = var.cluster_iam_role_arn

	vpc_config {
		subnet_ids              = module.vpc.private_subnets
		endpoint_public_access  = true
			endpoint_private_access = true
			public_access_cidrs     = var.admin_cidr_blocks
	}

	depends_on = [module.vpc]
}

resource "aws_eks_node_group" "general" {
	cluster_name    = aws_eks_cluster.this.name
	node_group_name = "general"
	node_role_arn   = var.node_iam_role_arn

	subnet_ids = module.vpc.private_subnets

	scaling_config {
		desired_size = var.desired
		min_size     = var.min
		max_size     = var.max
	}

	instance_types = [var.node_type]

	depends_on = [aws_eks_cluster.this]
}
