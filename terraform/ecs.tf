resource "aws_ecs_cluster" "main" {
  name = "${local.name_prefix}-cluster"

  tags = {
    Name = "${local.name_prefix}-cluster"
  }
}

# ---------------------------------------------------------------------------
# Frontend task definition
# ---------------------------------------------------------------------------

locals {
  frontend_container_def = [{
    name      = "frontend"
    image     = "${aws_ecr_repository.frontend.repository_url}:${var.frontend_image_tag}"
    essential = true

    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]

    readonlyRootFilesystem = true
    linuxParameters = {
      capabilities = { drop = ["ALL"] }
      tmpfs = [
        { containerPath = "/tmp", size = 64 },
        { containerPath = "/var/cache/nginx", size = 64 },
        { containerPath = "/var/run", size = 16 },
      ]
    }

    healthCheck = {
      command     = ["CMD-SHELL", "wget -q -O- http://127.0.0.1:${var.container_port}/healthz || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 10
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.frontend.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }]

  backend_container_def = [{
    name      = "backend"
    image     = "${aws_ecr_repository.backend.repository_url}:${var.backend_image_tag}"
    essential = true

    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]

    environment = [
      { name = "PORT", value = tostring(var.container_port) },
      { name = "NODE_ENV", value = "production" },
      { name = "CORS_ORIGIN", value = "http://${aws_lb.main.dns_name}" },
    ]

    readonlyRootFilesystem = true
    linuxParameters = {
      capabilities = { drop = ["ALL"] }
      tmpfs = [
        { containerPath = "/tmp", size = 64 },
      ]
    }

    healthCheck = {
      command     = ["CMD-SHELL", "wget -q -O- http://127.0.0.1:${var.container_port}/api/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 10
    }

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.backend.name
        "awslogs-region"        = var.aws_region
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }]
}

resource "aws_ecs_task_definition" "frontend" {
  family                   = "${local.name_prefix}-frontend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.frontend_cpu
  memory                   = var.frontend_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.frontend_task.arn
  container_definitions    = jsonencode(local.frontend_container_def)

  tags = {
    Name = "${local.name_prefix}-frontend-task"
  }
}

resource "aws_ecs_task_definition" "backend" {
  family                   = "${local.name_prefix}-backend"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.backend_cpu
  memory                   = var.backend_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.backend_task.arn
  container_definitions    = jsonencode(local.backend_container_def)

  tags = {
    Name = "${local.name_prefix}-backend-task"
  }
}

# ---------------------------------------------------------------------------
# Services
# ---------------------------------------------------------------------------

resource "aws_ecs_service" "frontend" {
  name            = "${local.name_prefix}-frontend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = var.frontend_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.frontend.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name   = "frontend"
    container_port   = var.container_port
  }

  health_check_grace_period_seconds = 60

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  # Jenkins registers new task definition revisions and calls UpdateService
  # directly outside of Terraform; ignore drift on task_definition so a
  # future `terraform apply` doesn't revert Jenkins-managed deployments.
  lifecycle {
    ignore_changes = [task_definition]
  }

  depends_on = [aws_lb_listener.http]

  tags = {
    Name = "${local.name_prefix}-frontend-service"
  }
}

resource "aws_ecs_service" "backend" {
  name            = "${local.name_prefix}-backend"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = var.backend_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.backend.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend.arn
    container_name   = "backend"
    container_port   = var.container_port
  }

  health_check_grace_period_seconds = 60

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  lifecycle {
    ignore_changes = [task_definition]
  }

  depends_on = [aws_lb_listener.http]

  tags = {
    Name = "${local.name_prefix}-backend-service"
  }
}
