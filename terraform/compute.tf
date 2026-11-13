resource "aws_ecr_repository" "pulsepay" {
  count                = var.use_localstack ? 0 : 1
  name                 = "pulsepay-${var.environment}-api"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

locals {
  ecr_repo_url = var.use_localstack ? "123456789012.dkr.ecr.${var.aws_region}://{var.environment}-api" : one(aws_ecr_repository.pulsepay[*].repository_url)
}

resource "aws_ecs_cluster" "main" {
  name = "pulsepay-${var.environment}-cluster"
}

resource "aws_lb" "main" {
  count              = var.use_localstack ? 0 : 1
  name               = "pulsepay-${var.environment}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
}

resource "aws_lb_target_group" "api" {
  name        = "pulsepay-${var.environment}-tg"
  port        = 8000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 15
  }
}

resource "aws_lb_listener" "http" {
  count             = var.use_localstack ? 0 : 1
  load_balancer_arn = one(aws_lb.main[*].arn)
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

resource "aws_ecs_task_definition" "api" {
  family                   = "pulsepay-${var.environment}-api"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn

  container_definitions = jsonencode([{
    name      = "pulsepay-api"
    image     = "${local.ecr_repo_url}:${var.image_tag}"
    essential = true
    portMappings = [{
      containerPort = 8000
      protocol      = "tcp"
    }]
    secrets = [{
      name      = "DATABASE_URL"
      valueFrom = aws_secretsmanager_secret.db_url.arn
    }]
  }])
}

resource "aws_ecs_service" "api" {
  name            = "pulsepay-${var.environment}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.api.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = false
  }

  dynamic "load_balancer" {
    for_each = var.use_localstack ? [] : ["enabled"]
    content {
      target_group_arn = aws_lb_target_group.api.arn
      container_name   = "pulsepay-api"
      container_port   = 8000
    }
  }
}
