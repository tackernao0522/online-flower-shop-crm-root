# AWSプロバイダーの設定
provider "aws" {
  region = var.aws_region
}

provider "aws" {
  alias  = "us-east-1"
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

# ACM 証明書のリクエスト (API)
resource "aws_acm_certificate" "api_cert" {
  domain_name       = "api.${var.domain_name}"
  validation_method = "DNS"

  tags = {
    Name = "${var.project_name}-api-cert"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Route 53でのDNS検証を設定 (API)
resource "aws_route53_record" "api_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.api_cert.domain_validation_options : dvo.domain_name => {
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

# ACM証明書の検証完了待ち (API)
resource "aws_acm_certificate_validation" "api_cert_validation" {
  certificate_arn         = aws_acm_certificate.api_cert.arn
  validation_record_fqdns = [for record in aws_route53_record.api_cert_validation : record.fqdn]
}

# ALB リスナー (HTTPS)
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate_validation.api_cert_validation.certificate_arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "OK"
      status_code  = "200"
    }
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

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
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

# ACM 証明書 for front (us-east-1リージョンに作成)
resource "aws_acm_certificate" "front_cert" {
  provider          = aws.us-east-1
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
  provider                = aws.us-east-1
  certificate_arn         = aws_acm_certificate.front_cert.arn
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

    # ここでTTL値を設定
    min_ttl     = 0
    default_ttl = 0
    max_ttl     = 0

    viewer_protocol_policy = "redirect-to-https"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn = aws_acm_certificate_validation.front_cert_validation.certificate_arn
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
