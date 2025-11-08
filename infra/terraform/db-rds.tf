# rds.tf
resource "aws_db_subnet_group" "rds" {
  name       = "bookstore-rds-subnets"
  subnet_ids = module.vpc.private_subnets
}

resource "aws_security_group" "rds" {
  name   = "bookstore-rds-sg"
  vpc_id = module.vpc.vpc_id
  # DEMO: permitir desde toda la VPC. En prod, restringe al SG de los nodos EKS.
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [module.vpc.vpc_cidr_block]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "postgres" {
  identifier             = "bookstore-postgres"
  engine                 = "postgres"
  engine_version         = "15"
  instance_class         = "db.t3.micro" # demo
  allocated_storage      = 20
  username               = var.db_user     # define en variables
  password               = var.db_password # define en variables (o Secrets Manager)
  db_name                = var.db_name
  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  multi_az               = false # demo; en prod true (costo ↑)
  publicly_accessible    = false
  skip_final_snapshot    = true
}
