resource "aws_secretsmanager_secret" "app_secrets" {
  name        = "${var.project_name}/production/app-secrets"
  description = "Application secrets for ${var.project_name} production environment"

  tags = {
    Environment = "production"
    Project     = var.project_name
  }
}

resource "aws_secretsmanager_secret_version" "app_secrets" {
  secret_id = aws_secretsmanager_secret.app_secrets.id
  secret_string = jsonencode({
    DB_HOST        = var.db_host
    DB_DATABASE    = var.db_database
    DB_USERNAME    = var.db_username
    DB_PASSWORD    = var.db_password
    APP_KEY        = var.app_key
    JWT_SECRET     = var.jwt_secret
    PUSHER_APP_ID      = var.pusher_app_id
    PUSHER_APP_KEY     = var.pusher_app_key
    PUSHER_APP_SECRET  = var.pusher_app_secret
    AWS_ACCESS_KEY_ID     = var.aws_access_key_id
    AWS_SECRET_ACCESS_KEY = var.aws_secret_access_key
  })
}

# VPCエンドポイントを作成してプライベートサブネットからのアクセスを可能にする
resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.secretsmanager"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.secrets_endpoint.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-secretsmanager-endpoint"
  }
}

# Secrets Manager用のセキュリティグループ
resource "aws_security_group" "secrets_endpoint" {
  name        = "${var.project_name}-secrets-endpoint-sg"
  description = "Security group for Secrets Manager VPC endpoint"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [var.ecs_tasks_security_group_id]
  }

  tags = {
    Name = "${var.project_name}-secrets-endpoint-sg"
  }
}

# ECS Task Roleに権限を追加
resource "aws_iam_role_policy" "ecs_task_secrets_policy" {
  name = "${var.project_name}-ecs-secrets-policy"
  role = var.ecs_task_role_id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [aws_secretsmanager_secret.app_secrets.arn]
      }
    ]
  })
}
