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

# Elastic IP (NAT Gatewayに割り当てるIPアドレス)
resource "aws_eip" "nat" {
  domain = "vpc"
  tags = {
    Name = "${var.project_name}-nat-eip"
  }
}

# NAT Gateway
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${var.project_name}-nat-gateway"
  }

  depends_on = [aws_internet_gateway.main]
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

# プライベートルートテーブルにNAT Gateway経由のデフォルトルートを追加
resource "aws_route" "private_nat" {
  count                  = 2
  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}

# プライベートサブネットとルートテーブルの関連付け
resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# VPCエンドポイント (SSM, SSMMessages, EC2Messages)
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [var.vpc_endpoints_security_group_id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-ssm-endpoint"
  }
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [var.vpc_endpoints_security_group_id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-ssmmessages-endpoint"
  }
}

resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [var.vpc_endpoints_security_group_id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-ec2messages-endpoint"
  }
}

# VPCエンドポイント (ECR Docker, ECR API, CloudWatch Logs)
resource "aws_vpc_endpoint" "ecr_docker" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [var.vpc_endpoints_security_group_id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-ecr-docker-endpoint"
  }
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [var.vpc_endpoints_security_group_id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-ecr-api-endpoint"
  }
}

resource "aws_vpc_endpoint" "cloudwatch_logs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [var.vpc_endpoints_security_group_id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-cloudwatch-logs-endpoint"
  }
}

# S3 VPCエンドポイント
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id

  tags = {
    Name = "${var.project_name}-s3-endpoint"
  }
}

resource "aws_vpc_endpoint" "execute_api" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.execute-api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [var.vpc_endpoints_security_group_id]
  private_dns_enabled = true

  tags = {
    Name = "${var.project_name}-execute-api-endpoint"
  }
}

# 利用可能なAZのデータソース
data "aws_availability_zones" "available" {
  state = "available"
}
