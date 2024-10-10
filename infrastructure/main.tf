# AWSプロバイダーの設定
provider "aws" {
  region = var.aws_region  # ap-northeast-1
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# VPC設定
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

# パブリックサブネット
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet-${count.index + 1}"
  }
}

# プライベートサブネット
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.project_name}-private-subnet-${count.index + 1}"
  }
}

# インターネットゲートウェイ
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

# パブリックルートテーブル
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# パブリックサブネットとルートテーブルの関連付け
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# プライベートルートテーブル
resource "aws_route_table" "private" {
  count  = 2
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-private-rt-${count.index + 1}"
  }
}

# プライベートサブネットとルートテーブルの関連付け
resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# 利用可能なAZのデータソース
data "aws_availability_zones" "available" {
  state = "available"
}

# ALB Security Group
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-alb-sg"
  description = "Security group for ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS from anywhere"
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
    Name = "${var.project_name}-alb-sg"
  }
}

# MySQL RDS インスタンス
resource "aws_db_instance" "mysql" {
  identifier        = "${var.project_name}-mysql"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp2"

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  vpc_security_group_ids = [aws_security_group.db.id]
  db_subnet_group_name   = aws_db_subnet_group.mysql.name

  backup_retention_period = 7
  skip_final_snapshot     = true
  multi_az                = false

  tags = {
    Name = "${var.project_name}-mysql"
  }
}

# データベース用サブネットグループ
resource "aws_db_subnet_group" "mysql" {
  name       = "${var.project_name}-mysql-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = {
    Name = "${var.project_name}-mysql-subnet-group"
  }
}

# データベース用セキュリティグループ
resource "aws_security_group" "db" {
  name        = "${var.project_name}-db-sg"
  description = "Security group for MySQL RDS"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow MySQL traffic from ALB"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-db-sg"
  }
}

# ALB リソース
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  enable_deletion_protection = false

  tags = {
    Name = "${var.project_name}-alb"
  }
}

# ALB リスナー (HTTP)
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

# Route 53 Hosted Zone
resource "aws_route53_zone" "main" {
  name = var.domain_name

  tags = {
    Name = "${var.project_name}-zone"
  }
}

# ALBに向けたAレコード (API)
resource "aws_route53_record" "api" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "api.${var.domain_name}"
  type    = "A"
  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = false
  }
}

# ACM 証明書のリクエスト (API, 東京リージョン)
resource "aws_acm_certificate" "api_cert_tokyo" {
  domain_name       = "api.${var.domain_name}"
  validation_method = "DNS"

  tags = {
    Name = "${var.project_name}-api-cert"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Route 53でのDNS検証を設定 (API, 東京リージョン)
resource "aws_route53_record" "api_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.api_cert_tokyo.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = aws_route53_zone.main.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

# ACM証明書の検証完了待ち (API, 東京リージョン)
resource "aws_acm_certificate_validation" "api_cert_validation_tokyo" {
  certificate_arn         = aws_acm_certificate.api_cert_tokyo.arn
  validation_record_fqdns = [for record in aws_route53_record.api_cert_validation : record.fqdn]
}

# ALB リスナー (HTTPS)
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
    certificate_arn   = aws_acm_certificate_validation.api_cert_validation_tokyo.certificate_arn  # 東京リージョンの証明書

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# フロントエンド用S3バケット
resource "aws_s3_bucket" "front" {
  bucket = "${var.project_name}-front"

  tags = {
    Name = "${var.project_name}-front-bucket"
  }
}

# S3バケットのパブリックアクセスブロック
resource "aws_s3_bucket_public_access_block" "front" {
  bucket = aws_s3_bucket.front.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# CloudFront OAI
resource "aws_cloudfront_origin_access_identity" "front" {
  comment = "OAI for ${var.project_name} frontend"
}

# S3バケットポリシー
resource "aws_s3_bucket_policy" "front" {
  bucket = aws_s3_bucket.front.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = { AWS = aws_cloudfront_origin_access_identity.front.iam_arn },
        Action    = "s3:GetObject",
        Resource  = "${aws_s3_bucket.front.arn}/*"
      }
    ]
  })
}

# ACM 証明書 for front
resource "aws_acm_certificate" "front_cert" {
  provider          = aws.us_east_1  # us-east-1で証明書発行（CloudFrontの要件により）
  domain_name       = "front.${var.domain_name}"
  validation_method = "DNS"

  tags = {
    Name = "${var.project_name}-front-cert"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# DNS検証 for front
resource "aws_route53_record" "front_cert_validation" {
  provider = aws.us_east_1  # us-east-1プロバイダーでDNS検証

  for_each = {
    for dvo in aws_acm_certificate.front_cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = aws_route53_zone.main.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

# ACM証明書の検証完了待ち (Front)
resource "aws_acm_certificate_validation" "front_cert_validation" {
  provider              = aws.us_east_1
  certificate_arn       = aws_acm_certificate.front_cert.arn
  validation_record_fqdns = [for record in aws_route53_record.front_cert_validation : record.fqdn]
}

# CloudFront distribution for front
resource "aws_cloudfront_distribution" "front" {
  enabled             = true
  default_root_object = "index.html"

  origin {
    domain_name = aws_s3_bucket.front.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.front.id}"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.front.cloudfront_access_identity_path
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.front.id}"

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate_validation.front_cert_validation.certificate_arn  # us-east-1証明書
    ssl_support_method  = "sni-only"
  }

  aliases = ["front.${var.domain_name}"]
}

# Route 53 Aレコード for front
resource "aws_route53_record" "front" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "front.${var.domain_name}"
  type    = "A"
  alias {
    name                   = aws_cloudfront_distribution.front.domain_name
    zone_id                = aws_cloudfront_distribution.front.hosted_zone_id
    evaluate_target_health = false
  }
}

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"
}

# ECS Task Definition
resource "aws_ecs_task_definition" "app" {
  family                   = "${var.project_name}-app"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([{
    name  = "${var.project_name}-app"
    image = "${aws_ecr_repository.app.repository_url}:latest"
    portMappings = [{
      containerPort = 80
      hostPort      = 80
    }]
    environment = [
      { name = "APP_ENV", value = "production" },
      { name = "APP_KEY", value = var.app_key },
      { name = "APP_URL", value = "https://api.${var.domain_name}" },
      { name = "DB_HOST", value = aws_db_instance.mysql.address },
      { name = "DB_DATABASE", value = var.db_name },
      { name = "DB_USERNAME", value = var.db_username },
      { name = "DB_PASSWORD", value = var.db_password },
      { name = "FRONTEND_URL", value = "https://front.${var.domain_name}" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = "/ecs/${var.project_name}"
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "ecs"
      }
    }
  }])
}

# CloudWatch Logs group for ECS
resource "aws_cloudwatch_log_group" "ecs_logs" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 30
}

# ECS Task Role
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.project_name}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_role_policy" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# S3へのアクセスを許可するポリシー
resource "aws_iam_role_policy_attachment" "ecs_task_s3_read_policy" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

# ECS Service
resource "aws_ecs_service" "app" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets         = aws_subnet.private[*].id
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app.arn
    container_name   = "${var.project_name}-app"
    container_port   = 80
  }

  depends_on = [aws_lb_listener.https]
}

# ECR Repository
resource "aws_ecr_repository" "app" {
  name         = "${var.project_name}-app"
  force_delete = true
}

# ECS Task Execution Role
resource "aws_iam_role" "ecs_execution_role" {
  name = "${var.project_name}-ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Security Group for ECS Tasks
resource "aws_security_group" "ecs_tasks" {
  name        = "${var.project_name}-ecs-tasks-sg"
    description = "Allow inbound access from the ALB only"
  vpc_id      = aws_vpc.main.id

  ingress {
    protocol        = "tcp"
    from_port       = 80
    to_port         = 80
    security_groups = [aws_security_group.alb.id]
  }

  # HTTPSトラフィックを許可するルール
  ingress {
    protocol        = "tcp"
    from_port       = 443
    to_port         = 443
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ALB Target Group
resource "aws_lb_target_group" "app" {
  name        = "${var.project_name}-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"

  health_check {
    healthy_threshold   = "3"
    interval            = "30"
    protocol            = "HTTP"
    matcher             = "200"
    timeout             = "3"
    path                = "/health"
    unhealthy_threshold = "2"
  }
}

# VPCエンドポイント（NAT Gatewayを使用しない場合）
resource "aws_vpc_endpoint" "ecr_docker" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type = "Interface"
  subnet_ids        = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.ecs_tasks.id]

  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-ecr-docker-endpoint"
  }
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type = "Interface"
  subnet_ids        = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.ecs_tasks.id]

  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-ecr-api-endpoint"
  }
}

resource "aws_vpc_endpoint" "cloudwatch_logs" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type = "Interface"
  subnet_ids        = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.ecs_tasks.id]

  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-cloudwatch-logs-endpoint"
  }
}

# ECS Agent 用 VPCエンドポイント
resource "aws_vpc_endpoint" "ecs_agent" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.ecs-agent"
  vpc_endpoint_type = "Interface"
  subnet_ids        = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.ecs_tasks.id]

  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-ecs-agent-endpoint"
  }
}

# SSM 用 VPCエンドポイント
resource "aws_vpc_endpoint" "ssm" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type = "Interface"
  subnet_ids        = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.ecs_tasks.id]

  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-ssm-endpoint"
  }
}

# Outputs
output "alb_dns_name" {
  description = "The DNS name of the load balancer"
  value       = aws_lb.main.dns_name
}

output "api_url" {
  description = "The URL of the API"
  value       = "https://api.${var.domain_name}"
}

output "frontend_url" {
  description = "The URL of the frontend"
  value       = "https://front.${var.domain_name}"
}

output "ecr_repository_url" {
  description = "The URL of the ECR repository"
  value       = aws_ecr_repository.app.repository_url
}

output "rds_endpoint" {
  description = "The endpoint of the RDS instance"
  value       = aws_db_instance.mysql.endpoint
}
