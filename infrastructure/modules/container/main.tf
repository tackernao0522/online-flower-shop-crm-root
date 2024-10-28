# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  tags = {
    Name = "${var.project_name}-cluster"
  }
}

# Backend ECR Repository
resource "aws_ecr_repository" "backend" {
  name         = "${var.project_name}-backend"
  force_delete = true

  tags = {
    Name = "${var.project_name}-backend-ecr"
  }
}

# Frontend ECR Repository
resource "aws_ecr_repository" "frontend" {
  name         = "${var.project_name}-frontend"
  force_delete = true

  tags = {
    Name = "${var.project_name}-frontend-ecr"
  }
}

# Backend ECS Task Definition
resource "aws_ecs_task_definition" "backend" {
  family                   = "${var.project_name}-backend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = var.ecs_execution_role_arn
  task_role_arn           = var.ecs_task_role_arn

  container_definitions = jsonencode([{
    name  = "${var.project_name}-backend"
    image = "${aws_ecr_repository.backend.repository_url}:latest"
    portMappings = [
      {
        containerPort = 80
        hostPort      = 80
      },
      {
        containerPort = 6001
        hostPort      = 6001
        protocol      = "tcp"
      }
    ]
    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost/health | grep -q '\"status\":\"ok\"' || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 60
    }
    environment = [
      { name = "APP_ENV", value = "production" },
      { name = "APP_DEBUG", value = "false" },
      { name = "APP_KEY", value = var.app_key },
      { name = "APP_URL", value = "https://api.${var.domain_name}" },
      { name = "LOG_CHANNEL", value = "stderr" },
      { name = "LOG_LEVEL", value = "error" },
      { name = "PUSHER_DEBUG", value = "false" },
      { name = "LARAVEL_WEBSOCKETS_DEBUG", value = "false" },
      { name = "DB_HOST", value = var.db_host },
      { name = "DB_DATABASE", value = var.db_name },
      { name = "DB_USERNAME", value = var.db_username },
      { name = "DB_PASSWORD", value = var.db_password },
      { name = "DB_CONNECTION_RETRIES", value = "5" },
      { name = "DB_CONNECTION_RETRY_DELAY", value = "5" },
      { name = "WAIT_HOSTS", value = "${var.db_host}:3306" },
      { name = "WAIT_HOSTS_TIMEOUT", value = "300" },
      { name = "FRONTEND_URL", value = "https://front.${var.domain_name}" },
      { name = "BROADCAST_DRIVER", value = "pusher" },
      { name = "PUSHER_APP_ID", value = var.pusher_app_id },
      { name = "PUSHER_APP_KEY", value = var.pusher_app_key },
      { name = "PUSHER_APP_SECRET", value = var.pusher_app_secret },
      { name = "PUSHER_HOST", value = "api-ap3.pusher.com" },
      { name = "PUSHER_PORT", value = "443" },
      { name = "PUSHER_SCHEME", value = "https" },
      { name = "PUSHER_APP_CLUSTER", value = var.pusher_app_cluster },
      { name = "LARAVEL_WEBSOCKETS_ENABLED", value = "true" },
      { name = "LARAVEL_WEBSOCKETS_PORT", value = "6001" },
      { name = "LARAVEL_WEBSOCKETS_HOST", value = "0.0.0.0" },
      { name = "LARAVEL_WEBSOCKETS_SCHEME", value = "https" },
      { name = "RUN_WEBSOCKETS", value = "true" },
      { name = "CACHE_DRIVER", value = "file" },
      { name = "SESSION_DRIVER", value = "file" },
      { name = "QUEUE_CONNECTION", value = "sync" },
      { name = "PHP_FPM_PM", value = "dynamic" },
      { name = "PHP_FPM_PM_MAX_CHILDREN", value = "5" },
      { name = "PHP_FPM_PM_START_SERVERS", value = "2" },
      { name = "PHP_FPM_PM_MIN_SPARE_SERVERS", value = "1" },
      { name = "PHP_FPM_PM_MAX_SPARE_SERVERS", value = "3" },
      { name = "AWS_USE_FIPS_ENDPOINT", value = "true" },
      { name = "ECS_ENABLE_EXECUTE_COMMAND", value = "true" },
      { name = "JWT_SECRET", value = var.jwt_secret },
      { name = "JWT_ALGO", value = var.jwt_algo },
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = "/ecs/${var.project_name}-backend"
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "ecs"
        "mode"                = "non-blocking"
        "max-buffer-size"     = "4m"
      }
    }
  }])

  tags = {
    Name = "${var.project_name}-backend-task"
  }
}

# Backend ECS Service
resource "aws_ecs_service" "backend" {
  name            = "${var.project_name}-backend-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend.arn
  desired_count   = 1
  platform_version = "1.4.0"
  launch_type     = "FARGATE"

  enable_execute_command = true

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 50

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.backend_target_group_arn
    container_name   = "${var.project_name}-backend"
    container_port   = 80
  }

  load_balancer {
    target_group_arn = var.websocket_target_group_arn
    container_name   = "${var.project_name}-backend"
    container_port   = 6001
  }

  tags = {
    Name = "${var.project_name}-backend-service"
  }
}

# Frontend ECS Task Definition
resource "aws_ecs_task_definition" "frontend" {
  family                   = "${var.project_name}-frontend"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = var.ecs_execution_role_arn
  task_role_arn           = var.ecs_task_role_arn

  container_definitions = jsonencode([{
    name  = "${var.project_name}-frontend"
    image = "${aws_ecr_repository.frontend.repository_url}:latest"
    portMappings = [{
      containerPort = 3000
      hostPort      = 3000
    }]
    environment = [
      { name = "NEXT_PUBLIC_API_URL", value = "https://api.${var.domain_name}" },
      { name = "NEXT_PUBLIC_PUSHER_APP_KEY", value = var.pusher_app_key },
      { name = "NEXT_PUBLIC_PUSHER_HOST", value = "api-ap3.pusher.com" },
      { name = "NEXT_PUBLIC_PUSHER_PORT", value = "443" },
      { name = "NEXT_PUBLIC_PUSHER_SCHEME", value = "https" },
      { name = "NEXT_PUBLIC_PUSHER_APP_CLUSTER", value = var.pusher_app_cluster }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = "/ecs/${var.project_name}-frontend"
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "ecs"
      }
    }
  }])

  tags = {
    Name = "${var.project_name}-frontend-task"
  }
}

# Frontend ECS Service
resource "aws_ecs_service" "frontend" {
  name            = "${var.project_name}-frontend-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.frontend.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  enable_execute_command = true

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.frontend_target_group_arn
    container_name   = "${var.project_name}-frontend"
    container_port   = 3000
  }

  tags = {
    Name = "${var.project_name}-frontend-service"
  }
}
