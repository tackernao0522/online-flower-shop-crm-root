provider "aws" {
  region     = "ap-northeast-1"
  access_key = var.aws_access_key_id == "" ? null : var.aws_access_key_id
  secret_key = var.aws_secret_access_key == "" ? null : var.aws_secret_access_key
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
  backend "s3" {
    bucket = "online-flower-crm-bucket"
    key    = "terraform/state"
    region = "ap-northeast-1"
  }
}

# VPCの作成
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "main-vpc"
  }
}

# インターネットゲートウェイの作成
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "main-igw"
  }
}

# ルートテーブルの作成
resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "main-route-table"
  }
}

# サブネットの作成（2つのAZに分散）
resource "aws_subnet" "subnet_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "ap-northeast-1a"
  tags = {
    Name = "main-subnet-a"
  }
}

resource "aws_subnet" "subnet_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-northeast-1c"
  tags = {
    Name = "main-subnet-b"
  }
}

# サブネットにルートテーブルを関連付ける
resource "aws_route_table_association" "subnet_a_association" {
  subnet_id      = aws_subnet.subnet_a.id
  route_table_id = aws_route_table.main.id
}

resource "aws_route_table_association" "subnet_b_association" {
  subnet_id      = aws_subnet.subnet_b.id
  route_table_id = aws_route_table.main.id
}

# ECSタスク用のセキュリティグループ
resource "aws_security_group" "ecs_sg" {
  name        = "ecs-sg"
  description = "Security group for ECS tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ecs-sg"
  }
}

# ECSクラスタの作成
resource "aws_ecs_cluster" "main" {
  name = "ecs-cluster"
}

# ECRリポジトリの作成
resource "aws_ecr_repository" "laravel" {
  name = "laravel-app"
}

resource "aws_ecr_repository" "nextjs" {
  name = "nextjs-app"
}

resource "aws_ecr_repository" "nginx" {
  name = "nginx"
}

# ECSタスク定義の作成
resource "aws_ecs_task_definition" "app" {
  family                   = "app-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "laravel-app"
      image     = "${aws_ecr_repository.laravel.repository_url}:latest"
      cpu       = 256
      memory    = 512
      essential = true
      portMappings = [{
        containerPort = 9000
        hostPort      = 9000
      }]
      environment = [
        { name = "APP_ENV", value = "production" },
        { name = "APP_DEBUG", value = "false" },
        { name = "APP_URL", value = "https://www.tkb-tech.com" },
        { name = "DB_CONNECTION", value = "mysql" },
        { name = "DB_HOST", value = aws_db_instance.default.address },
        { name = "DB_PORT", value = "3306" },
        { name = "DB_DATABASE", value = var.db_name },
        { name = "DB_USERNAME", value = var.db_username },
        { name = "BROADCAST_DRIVER", value = "pusher" },
        { name = "CACHE_DRIVER", value = "redis" },
        { name = "FILESYSTEM_DISK", value = "s3" },
        { name = "QUEUE_CONNECTION", value = "redis" },
        { name = "SESSION_DRIVER", value = "redis" },
        { name = "AWS_DEFAULT_REGION", value = "ap-northeast-1" },
        { name = "AWS_BUCKET", value = var.s3_bucket_name },
        { name = "PUSHER_APP_CLUSTER", value = "ap3" }
      ]
      secrets = [
        { name = "APP_KEY", valueFrom = aws_secretsmanager_secret.app_key.arn },
        { name = "DB_PASSWORD", valueFrom = aws_secretsmanager_secret.db_password.arn },
        { name = "REDIS_PASSWORD", valueFrom = aws_secretsmanager_secret.redis_password.arn },
        { name = "AWS_ACCESS_KEY_ID", valueFrom = aws_secretsmanager_secret.aws_access_key_id.arn },
        { name = "AWS_SECRET_ACCESS_KEY", valueFrom = aws_secretsmanager_secret.aws_secret_access_key.arn },
        { name = "PUSHER_APP_ID", valueFrom = aws_secretsmanager_secret.pusher_app_id.arn },
        { name = "PUSHER_APP_KEY", valueFrom = aws_secretsmanager_secret.pusher_app_key.arn },
        { name = "PUSHER_APP_SECRET", valueFrom = aws_secretsmanager_secret.pusher_app_secret.arn }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/app-task"
          awslogs-region        = "ap-northeast-1"
          awslogs-stream-prefix = "laravel"
        }
      }
    },
    {
      name      = "nextjs-app"
      image     = "${aws_ecr_repository.nextjs.repository_url}:latest"
      cpu       = 128
      memory    = 256
      essential = true
      portMappings = [{
        containerPort = 3000
        hostPort      = 3000
      }]
      environment = [
        { name = "NEXT_PUBLIC_API_URL", value = "https://tkb-tech.com" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/app-task"
          awslogs-region        = "ap-northeast-1"
          awslogs-stream-prefix = "nextjs"
        }
      }
    },
    {
      name      = "nginx"
      image     = "${aws_ecr_repository.nginx.repository_url}:latest"
      cpu       = 128
      memory    = 256
      essential = true
      portMappings = [{
        containerPort = 80
        hostPort      = 80
      }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/app-task"
          awslogs-region        = "ap-northeast-1"
          awslogs-stream-prefix = "nginx"
        }
      }
      healthCheck = {
        command     = ["CMD-SHELL", "curl -f http://localhost/ || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
    }
  ])
}

# ECSサービスの作成
resource "aws_ecs_service" "app_service" {
  name            = "app-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = [aws_subnet.subnet_a.id, aws_subnet.subnet_b.id]
    security_groups = [aws_security_group.ecs_sg.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.main.arn
    container_name   = "nginx"
    container_port   = 80
  }

  depends_on = [aws_lb_listener.http, aws_lb_listener.https]
}

# ALBの作成
resource "aws_lb" "main" {
  name               = "main-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ecs_sg.id]
  subnets            = [aws_subnet.subnet_a.id, aws_subnet.subnet_b.id]

  enable_deletion_protection = false

  tags = {
    Name = "main-lb"
  }
}

# ALBリスナー（HTTP）
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# ALBリスナー（HTTPS）
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = "arn:aws:acm:ap-northeast-1:699475951464:certificate/8ce690d8-3909-405c-aa46-f64ba354cc2e"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }

  lifecycle {
    ignore_changes = [default_action]
  }
}

# 既存のリスナーをインポート
import {
  to = aws_lb_listener.https
  id = "arn:aws:elasticloadbalancing:ap-northeast-1:699475951464:listener/app/main-lb/e18d972aa80c53a1/444c9212f1acc5f6"
}

# ALBターゲットグループ
resource "aws_lb_target_group" "main" {
  name        = "main-targets"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    healthy_threshold   = "3"
    interval            = "30"
    protocol            = "HTTP"
    matcher             = "200"
    timeout             = "5"
    path                = "/"
    unhealthy_threshold = "2"
  }
}

# IAMロールの作成
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# IAMロールポリシーのアタッチ
resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ECSタスクロールの作成
resource "aws_iam_role" "ecs_task_role" {
  name = "ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

# ECSタスクロールにポリシーをアタッチ
resource "aws_iam_role_policy_attachment" "ecs_task_role_policy" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"  # S3へのフルアクセスを許可
}

# RDSインスタンスの作成
resource "aws_db_instance" "default" {
  identifier           = "main-rds"
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "mysql"
  engine_version       = "8.0"
  instance_class       = "db.t3.micro"
  db_name              = var.db_name
  username             = var.db_username
  password             = var.db_password
  parameter_group_name = "default.mysql8.0"
  skip_final_snapshot  = true

  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  db_subnet_group_name   = aws_db_subnet_group.main.name

  tags = {
    Name = "main-rds"
  }
}

# RDS用のセキュリティグループ
resource "aws_security_group" "rds_sg" {
  name        = "rds-sg"
  description = "Security group for RDS"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "rds-sg"
  }
}

# RDS用のサブネットグループ
resource "aws_db_subnet_group" "main" {
  name       = "main-db-subnet-group"
  subnet_ids = [aws_subnet.subnet_a.id, aws_subnet.subnet_b.id]

  tags = {
    Name = "main-db-subnet-group"
  }
}

# Route 53レコード
resource "aws_route53_record" "www" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "www.tkb-tech.com"
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

# 既存のRoute 53ゾーンを参照
data "aws_route53_zone" "main" {
  name = "tkb-tech.com"
}

# Secrets Manager シークレット
resource "aws_secretsmanager_secret" "db_password" {
  name = "db-password"
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = var.db_password
}

resource "aws_secretsmanager_secret" "app_key" {
  name = "app-key"
}

resource "aws_secretsmanager_secret_version" "app_key" {
  secret_id     = aws_secretsmanager_secret.app_key.id
  secret_string = var.app_key
}

resource "aws_secretsmanager_secret" "redis_password" {
  name = "redis-password"
}

resource "aws_secretsmanager_secret_version" "redis_password" {
  secret_id     = aws_secretsmanager_secret.redis_password.id
  secret_string = var.redis_password
}

resource "aws_secretsmanager_secret" "aws_access_key_id" {
  name = "aws-access-key-id"
}

resource "aws_secretsmanager_secret_version" "aws_access_key_id" {
  secret_id     = aws_secretsmanager_secret.aws_access_key_id.id
  secret_string = var.aws_access_key_id != "" ? var.aws_access_key_id : "dummy_value"
}

resource "aws_secretsmanager_secret" "aws_secret_access_key" {
  name = "aws-secret-access-key"
}

resource "aws_secretsmanager_secret_version" "aws_secret_access_key" {
  secret_id     = aws_secretsmanager_secret.aws_secret_access_key.id
  secret_string = var.aws_secret_access_key != "" ? var.aws_secret_access_key : "dummy_value"
}

resource "aws_secretsmanager_secret" "pusher_app_id" {
  name = "pusher-app-id"
}

resource "aws_secretsmanager_secret_version" "pusher_app_id" {
  secret_id     = aws_secretsmanager_secret.pusher_app_id.id
  secret_string = var.pusher_app_id
}

resource "aws_secretsmanager_secret" "pusher_app_key" {
  name = "pusher-app-key"
}

resource "aws_secretsmanager_secret_version" "pusher_app_key" {
  secret_id     = aws_secretsmanager_secret.pusher_app_key.id
  secret_string = var.pusher_app_key
}

resource "aws_secretsmanager_secret" "pusher_app_secret" {
  name = "pusher-app-secret"
}

resource "aws_secretsmanager_secret_version" "pusher_app_secret" {
  secret_id     = aws_secretsmanager_secret.pusher_app_secret.id
  secret_string = var.pusher_app_secret
}

# CloudWatch Logs Group
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/app-task"
  retention_in_days = 30
}

# 変数の定義
variable "db_name" {
  description = "Name of the database"
  type        = string
}

variable "db_username" {
  description = "Username for the database"
  type        = string
}

variable "db_password" {
  description = "Password for the database"
  type        = string
}

variable "app_key" {
  description = "Laravel APP_KEY"
  type        = string
}

variable "redis_password" {
  description = "Redis password"
  type        = string
}

variable "aws_access_key_id" {
  description = "AWS Access Key ID"
  type        = string
  default     = ""
}

variable "aws_secret_access_key" {
  description = "AWS Secret Access Key"
  type        = string
  default     = ""
}

variable "s3_bucket_name" {
  description = "S3 bucket name for file storage"
  type        = string
}

variable "pusher_app_id" {
  description = "Pusher App ID"
  type        = string
}

variable "pusher_app_key" {
  description = "Pusher App Key"
  type        = string
}

variable "pusher_app_secret" {
  description = "Pusher App Secret"
  type        = string
}
