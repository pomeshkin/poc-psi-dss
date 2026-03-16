# External Load Balancer

resource "aws_security_group" "alb_ext" {
  count = local.create.sg ? 1 : 0

  name        = "${local.name_prefix}-alb-ext"
  description = "ALB external"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description      = "Managed by Terraform: HTTP from internet"
    from_port        = 80 // HTTP will be redirected to 443 by ALB listener
    to_port          = 80
    protocol         = "tcp"
    cidr_blocks      = var.network_allowed_cidrs_ingress
    ipv6_cidr_blocks = []
  }

  ingress {
    description      = "Managed by Terraform: HTTPs from internet"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = var.network_allowed_cidrs_ingress
    ipv6_cidr_blocks = []
  }

  egress {
    description      = "Managed by Terraform: HTTPs to EC2 app instances"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = var.network_vpc_private_subnets
    ipv6_cidr_blocks = []
  }

  tags = { "Name" : "${local.name_prefix}-alb-ext" }
}

# EC2 app

resource "aws_security_group" "ec2_app" {
  count = local.create.sg ? 1 : 0

  name        = "${local.name_prefix}-ec2-app"
  description = "Security group for EC2 instances hosting application"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Managed by Terraform: from ALB"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = aws_security_group.alb_ext.*.id
  }

  egress {
    description = "Managed by Terraform: HTTPs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    // cidr_blocks = var.network_vpc_private_subnets
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Managed by Terraform: To MySQL"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = var.network_vpc_database_subnets
  }

  tags = {
    Name = "${local.name_prefix}-ec2-app"
  }
}

# EC2 MySQL

resource "aws_security_group" "ec2_mysql" {
  count = local.create.sg ? 1 : 0

  name        = "${local.name_prefix}-ec2-mysql"
  description = "Security group for EC2 instances hosting MySQL database"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Managed by Terraform: MySQL from Application"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = aws_security_group.ec2_app.*.id
  }

  egress {
    description = "Managed by Terraform: To VPC endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.network_vpc_private_subnets
  }

  tags = { "Name" : "${local.name_prefix}-ec2-mysql" }
}

# VPC endpoints

resource "aws_security_group" "vpc_endpoints" {
  count = local.create.sg ? 1 : 0

  name        = "${local.name_prefix}-vpc-endpoints"
  description = "Security group for VPC endpoints"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Managed by Terraform: from EC2 app and MySQL"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.network_vpc_cidr]
    //security_groups = concat(aws_security_group.ec2_app.*.id, aws_security_group.ec2_mysql.*.id)
  }

  egress {
    description = "Managed by Terraform: HTTPs to AWS services via VPC endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { "Name" : "${local.name_prefix}-vpc-endpoints" }
}

# Packer

resource "aws_security_group" "packer" {
  count = local.create.sg ? 1 : 0

  name        = "${local.name_prefix}-packer"
  description = "Security group for Packer"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Managed by Terraform: allow all"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Managed by Terraform: allow all"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { "Name" : "${local.name_prefix}-packer" }
}

