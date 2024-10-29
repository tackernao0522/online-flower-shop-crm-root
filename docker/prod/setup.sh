#!/bin/bash

set -e

# カラー出力の設定
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}手動デプロイ環境のセットアップを開始します...${NC}"

# スクリプトのディレクトリパスを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../" && pwd)"

# 必要なコマンドの確認
echo "必要なコマンドの確認中..."
REQUIRED_COMMANDS="docker docker-compose aws jq curl"
for cmd in $REQUIRED_COMMANDS; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}Error: $cmd が見つかりません。インストールしてください。${NC}"
        exit 1
    fi
done

# AWSの認証情報の確認
echo "AWS認証情報の確認中..."
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}Error: AWS認証情報が設定されていないか、無効です。${NC}"
    echo "以下のいずれかの方法で認証情報を設定してください："
    echo "1. AWS CLIの設定: aws configure"
    echo "2. 環境変数の設定: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_DEFAULT_REGION"
    exit 1
fi

# docker-compose.prod.ymlの作成
echo "docker-compose.prod.ymlを作成中..."
cat > "${PROJECT_ROOT}/docker-compose.prod.yml" << 'EOL'
version: '3.8'

services:
  backend:
    build:
      context: ./api
      dockerfile: infra/php/Dockerfile.prod
      args:
        AWS_REGION: ${AWS_REGION}
    image: ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-backend:${IMAGE_TAG}
    environment:
      # アプリケーション設定
      APP_NAME: ${PROJECT_NAME}
      APP_ENV: production
      APP_KEY: ${APP_KEY}
      APP_DEBUG: 'false'
      LOG_CHANNEL: stderr
      APP_URL: https://api.${DOMAIN_NAME}
      LOG_LEVEL: error

      # データベース設定
      DB_CONNECTION: mysql
      DB_HOST: ${DB_HOST}
      DB_PORT: 3306
      DB_DATABASE: ${DB_DATABASE}
      DB_USERNAME: ${DB_USERNAME}
      DB_PASSWORD: ${DB_PASSWORD}
      DB_CONNECTION_RETRIES: 5
      DB_CONNECTION_RETRY_DELAY: 5
      WAIT_HOSTS: ${DB_HOST}:3306
      WAIT_HOSTS_TIMEOUT: 300

      # Broadcast/WebSocket設定
      BROADCAST_DRIVER: pusher
      PUSHER_APP_ID: ${PUSHER_APP_ID}
      PUSHER_APP_KEY: ${PUSHER_APP_KEY}
      PUSHER_APP_SECRET: ${PUSHER_APP_SECRET}
      PUSHER_HOST: api-ap3.pusher.com
      PUSHER_PORT: 443
      PUSHER_SCHEME: https
      PUSHER_APP_CLUSTER: ${PUSHER_APP_CLUSTER}
      PUSHER_DEBUG: 'false'

      # Laravel WebSockets設定
      LARAVEL_WEBSOCKETS_ENABLED: 'true'
      LARAVEL_WEBSOCKETS_HOST: 0.0.0.0
      LARAVEL_WEBSOCKETS_PORT: 6001
      LARAVEL_WEBSOCKETS_SCHEME: http
      LARAVEL_WEBSOCKETS_DEBUG: 'false'

      # JWT設定
      JWT_SECRET: ${JWT_SECRET}
      JWT_ALGO: HS256

      # フロントエンドURL
      FRONTEND_URL: https://front.${DOMAIN_NAME}

      # その他の設定
      RUN_WEBSOCKETS: 'true'
      AWS_USE_FIPS_ENDPOINT: 'true'
      ECS_ENABLE_EXECUTE_COMMAND: 'true'

  frontend:
    build:
      context: ./front
      dockerfile: Dockerfile.prod
      args:
        NODE_ENV: production
    image: ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-frontend:${IMAGE_TAG}
    environment:
      NODE_ENV: production
      NEXT_PUBLIC_APP_ENV: production
      NEXT_PUBLIC_API_URL: https://api.${DOMAIN_NAME}
      NEXT_PUBLIC_PUSHER_APP_KEY: ${PUSHER_APP_KEY}
      NEXT_PUBLIC_PUSHER_HOST: api-ap3.pusher.com
      NEXT_PUBLIC_PUSHER_PORT: 443
      NEXT_PUBLIC_PUSHER_SCHEME: https
      NEXT_PUBLIC_PUSHER_APP_CLUSTER: ${PUSHER_APP_CLUSTER}

networks:
  app-network:
    driver: bridge
EOL

# スクリプトディレクトリの作成
echo "スクリプトディレクトリを作成中..."
mkdir -p "${PROJECT_ROOT}/docker/prod/scripts"

# デプロイスクリプトの作成
echo "デプロイスクリプトを作成中..."
cat > "${PROJECT_ROOT}/docker/prod/scripts/deploy.sh" << 'EOL'
#!/bin/bash
set -e

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# 環境変数ファイルの読み込み
if [ ! -f "${PROJECT_ROOT}/.env.prod" ]; then
    echo "Error: .env.prod file not found in project root!"
    exit 1
fi

source "${PROJECT_ROOT}/.env.prod"

# タイムスタンプベースのイメージタグを生成
export IMAGE_TAG=$(date +%Y%m%d_%H%M%S)

# AWS ECRへのログイン
echo "Logging in to Amazon ECR..."
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# リソースIDの取得
echo "Getting AWS resource IDs..."
PRIVATE_SUBNET_1=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=${PROJECT_NAME}-private-subnet-1" --query 'Subnets[0].SubnetId' --output text)
PRIVATE_SUBNET_2=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=${PROJECT_NAME}-private-subnet-2" --query 'Subnets[0].SubnetId' --output text)
ECS_TASKS_SG=$(aws ec2 describe-security-groups --filters "Name=tag:Name,Values=${PROJECT_NAME}-ecs-tasks-sg" --query 'SecurityGroups[0].GroupId' --output text)

# Dockerイメージのビルドとプッシュ
echo "Building and pushing Docker images..."
docker-compose -f "${PROJECT_ROOT}/docker-compose.prod.yml" build
docker-compose -f "${PROJECT_ROOT}/docker-compose.prod.yml" push

# ECSサービスの更新
echo "Updating ECS services..."
aws ecs update-service \
    --cluster ${PROJECT_NAME}-cluster \
    --service ${PROJECT_NAME}-backend-service \
    --force-new-deployment

aws ecs update-service \
    --cluster ${PROJECT_NAME}-cluster \
    --service ${PROJECT_NAME}-frontend-service \
    --force-new-deployment

echo "Deployment completed!"
EOL

# デプロイスクリプトに実行権限を付与
chmod +x "${PROJECT_ROOT}/docker/prod/scripts/deploy.sh"

# 環境変数テンプレート例の作成（Gitで管理される）
echo "環境変数テンプレート例を作成中..."
cat > "${PROJECT_ROOT}/.env.template.example" << 'EOL'
# AWS Configuration
AWS_REGION=ap-northeast-1
AWS_ACCOUNT_ID=123456789012
AWS_ACCESS_KEY_ID=your_access_key_here
AWS_SECRET_ACCESS_KEY=your_secret_key_here
AWS_DEFAULT_REGION=ap-northeast-1

# Project Configuration
PROJECT_NAME=your_project_name
DOMAIN_NAME=example.com

# Database Configuration
DB_HOST=your_rds_endpoint_here
DB_DATABASE=your_database_name
DB_USERNAME=your_db_username
DB_PASSWORD=your_db_password
DB_CONNECTION_RETRIES=5
DB_CONNECTION_RETRY_DELAY=5
WAIT_HOSTS_TIMEOUT=300

# Application Configuration
APP_NAME=YourAppName
APP_ENV=production
APP_KEY=your_app_key_here
APP_DEBUG=false
LOG_CHANNEL=stderr
LOG_LEVEL=error

# WebSocket Configuration
BROADCAST_DRIVER=pusher
PUSHER_APP_ID=your_pusher_app_id
PUSHER_APP_KEY=your_pusher_app_key
PUSHER_APP_SECRET=your_pusher_secret
PUSHER_HOST=api-ap3.pusher.com
PUSHER_PORT=443
PUSHER_SCHEME=https
PUSHER_APP_CLUSTER=ap3
PUSHER_DEBUG=false

# Laravel WebSockets Configuration
LARAVEL_WEBSOCKETS_ENABLED=true
LARAVEL_WEBSOCKETS_HOST=0.0.0.0
LARAVEL_WEBSOCKETS_PORT=6001
LARAVEL_WEBSOCKETS_SCHEME=http
LARAVEL_WEBSOCKETS_DEBUG=false

# Cache Configuration
CACHE_DRIVER=file
SESSION_DRIVER=file
QUEUE_CONNECTION=sync

# JWT Configuration
JWT_SECRET=your_jwt_secret_here
JWT_ALGO=HS256

# Frontend Configuration
FRONTEND_URL=https://front.example.com
NEXT_PUBLIC_APP_ENV=production
NEXT_PUBLIC_API_URL=https://api.example.com

# ECS Configuration
ECS_ENABLE_EXECUTE_COMMAND=true
AWS_USE_FIPS_ENDPOINT=true

# Image Configuration
IMAGE_TAG=latest
EOL

# 実際のテンプレートファイルの作成
cp "${PROJECT_ROOT}/.env.template.example" "${PROJECT_ROOT}/.env.template"

# .env.prodの作成
cp "${PROJECT_ROOT}/.env.template" "${PROJECT_ROOT}/.env.prod"

# gitignoreの更新
echo "gitignoreを更新中..."
if [ -f "${PROJECT_ROOT}/.gitignore" ]; then
    echo "" >> "${PROJECT_ROOT}/.gitignore"
    echo "# Production deployment files" >> "${PROJECT_ROOT}/.gitignore"
    echo ".env.template" >> "${PROJECT_ROOT}/.gitignore"
    echo ".env.prod" >> "${PROJECT_ROOT}/.gitignore"
    echo "*.pem" >> "${PROJECT_ROOT}/.gitignore"
else
    echo -e "${YELLOW}Warning: .gitignoreファイルが見つかりません。新規作成します。${NC}"
    echo "# Production deployment files" > "${PROJECT_ROOT}/.gitignore"
    echo ".env.template" >> "${PROJECT_ROOT}/.gitignore"
    echo ".env.prod" >> "${PROJECT_ROOT}/.gitignore"
    echo "*.pem" >> "${PROJECT_ROOT}/.gitignore"
fi

echo -e "${GREEN}セットアップが完了しました！${NC}"
echo ""
echo -e "${YELLOW}次のステップ:${NC}"
echo "1. .env.templateを編集して実際のプロジェクト用テンプレートを作成"
echo "2. .env.prodファイルに実際の本番環境の値を設定"
echo "3. デプロイスクリプトを実行: ./docker/prod/scripts/deploy.sh"
echo ""
echo -e "${YELLOW}注意: ${NC}"
echo "- .env.template.exampleはGitで管理され、ダミー値のみを含みます"
echo "- .env.templateと.env.prodは.gitignoreに含まれ、GitHubにプッシュされません"
