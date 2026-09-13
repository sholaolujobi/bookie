resource "aws_lb" "main" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  # No sensitive data is served and this is a short-lived demo/challenge
  # environment, so access logging to S3 is intentionally left off to avoid
  # an extra S3 bucket + cost; enable it for a longer-lived deployment.
  enable_deletion_protection = false

  tags = {
    Name = "${local.name_prefix}-alb"
  }
}

resource "aws_lb_target_group" "frontend" {
  name        = "${local.name_prefix}-frontend-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/healthz"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  deregistration_delay = 15

  tags = {
    Name = "${local.name_prefix}-frontend-tg"
  }
}

resource "aws_lb_target_group" "backend" {
  name        = "${local.name_prefix}-backend-tg"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/api/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  deregistration_delay = 15

  tags = {
    Name = "${local.name_prefix}-backend-tg"
  }
}

# Default action serves the frontend (same-origin SPA). A path-based rule
# routes /api/* to the backend so the browser can call the API without CORS
# ever coming into play in production.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }

  tags = {
    Name = "${local.name_prefix}-http-listener"
  }
}

resource "aws_lb_listener_rule" "backend_api" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    path_pattern {
      values = ["/api/*"]
    }
  }
}
