# ALB: the only security group that accepts traffic from the open internet.
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "Internet-facing ALB: allow inbound HTTP from anywhere, all egress"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-alb-sg"
  }
}

# Frontend ECS tasks: only reachable from the ALB, never directly from the
# internet, even though the tasks have public IPs (required to pull images
# without a NAT Gateway).
resource "aws_security_group" "frontend" {
  name        = "${local.name_prefix}-frontend-sg"
  description = "Frontend ECS tasks: allow inbound only from the ALB security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "App traffic from ALB"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "All outbound (ECR/CloudWatch/etc.)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-frontend-sg"
  }
}

# Backend ECS tasks: same pattern as frontend.
resource "aws_security_group" "backend" {
  name        = "${local.name_prefix}-backend-sg"
  description = "Backend ECS tasks: allow inbound only from the ALB security group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "App traffic from ALB"
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "All outbound (ECR/CloudWatch/etc.)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-backend-sg"
  }
}

# Jenkins EC2 instance.
resource "aws_security_group" "jenkins" {
  name        = "${local.name_prefix}-jenkins-sg"
  description = "Jenkins EC2: web UI restricted to jenkins_allowed_cidrs, SSH optional and off by default"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Jenkins web UI"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = var.jenkins_allowed_cidrs
  }

  dynamic "ingress" {
    for_each = var.enable_jenkins_ssh ? [1] : []
    content {
      description = "SSH (explicitly enabled via enable_jenkins_ssh)"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [var.jenkins_ssh_allowed_cidr]
    }
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-jenkins-sg"
  }
}
