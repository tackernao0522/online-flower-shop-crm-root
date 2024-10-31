#!/bin/bash
set -e

# カラー出力の設定
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# スクリプトのディレクトリを取得
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# 必要な環境変数のリスト
REQUIRED_ENV_VARS=(
    "AWS_REGION"
    "AWS_ACCOUNT_ID"
    "PROJECT_NAME"
    "DOMAIN_NAME"
    "DB_HOST"
    "DB_DATABASE"
    "DB_USERNAME"
    "DB_PASSWORD"
    "APP_KEY"
    "JWT_SECRET"
    "PUSHER_APP_ID"
    "PUSHER_APP_KEY"
    "PUSHER_APP_SECRET"
    "PUSHER_APP_CLUSTER"
)

# 環境変数ファイルの読み込みと検証
if [ ! -f "${PROJECT_ROOT}/.env.prod" ]; then
    echo -e "${RED}Error: .env.prod file not found in project root!${NC}"
    echo "Expected location: ${PROJECT_ROOT}/.env.prod"
    exit 1
fi

# 環境変数をエクスポート
set -a
source "${PROJECT_ROOT}/.env.prod"
set +a

# 環境変数の検証
echo "環境変数のチェック中..."
MISSING_VARS=0
for VAR in "${REQUIRED_ENV_VARS[@]}"; do
    if [ -z "${!VAR}" ]; then
        echo -e "${RED}Error: $VAR is not set in .env.prod${NC}"
        MISSING_VARS=1
    fi
done

if [ $MISSING_VARS -eq 1 ]; then
    echo -e "${RED}必要な環境変数が設定されていません。.env.prodを確認してください。${NC}"
    exit 1
fi

# タイムスタンプベースのイメージタグを生成
export IMAGE_TAG=$(date +%Y%m%d_%H%M%S)

echo -e "${GREEN}デプロイを開始します...${NC}"
echo "Project: ${PROJECT_NAME}"
echo "Region: ${AWS_REGION}"
echo "Image Tag: ${IMAGE_TAG}"

# AWS ECRへのログイン
echo "AWS ECRへログイン中..."
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# リソースIDの取得
echo "AWSリソースIDの取得中..."
PRIVATE_SUBNET_1=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=${PROJECT_NAME}-private-subnet-1" --query 'Subnets[0].SubnetId' --output text)
PRIVATE_SUBNET_2=$(aws ec2 describe-subnets --filters "Name=tag:Name,Values=${PROJECT_NAME}-private-subnet-2" --query 'Subnets[0].SubnetId' --output text)
ECS_TASKS_SG=$(aws ec2 describe-security-groups --filters "Name=tag:Name,Values=${PROJECT_NAME}-ecs-tasks-sg" --query 'SecurityGroups[0].GroupId' --output text)

# ALBのDNS名を取得
ALB_DNS_NAME=$(aws elbv2 describe-load-balancers --names "${PROJECT_NAME}-alb" --query 'LoadBalancers[0].DNSName' --output text)

if [ -z "$PRIVATE_SUBNET_1" ] || [ -z "$PRIVATE_SUBNET_2" ] || [ -z "$ECS_TASKS_SG" ] || [ -z "$ALB_DNS_NAME" ]; then
    echo -e "${RED}Error: 必要なAWSリソースIDの取得に失敗しました${NC}"
    echo "PRIVATE_SUBNET_1: ${PRIVATE_SUBNET_1}"
    echo "PRIVATE_SUBNET_2: ${PRIVATE_SUBNET_2}"
    echo "ECS_TASKS_SG: ${ECS_TASKS_SG}"
    echo "ALB_DNS_NAME: ${ALB_DNS_NAME}"
    exit 1
fi

# ECRリポジトリの存在確認
echo "ECRリポジトリの確認中..."
aws ecr describe-repositories --repository-names ${PROJECT_NAME}-backend ${PROJECT_NAME}-frontend > /dev/null 2>&1 || {
    echo -e "${RED}Error: ECRリポジトリが見つかりません${NC}"
    exit 1
}

# Dockerイメージのビルドとプッシュ
echo "Dockerイメージのビルドとプッシュを開始..."
echo "Backend image: ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-backend:${IMAGE_TAG}"
echo "Frontend image: ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-frontend:${IMAGE_TAG}"

docker-compose -f "${PROJECT_ROOT}/docker-compose.prod.yml" build || {
    echo -e "${RED}Error: Dockerイメージのビルドに失敗しました${NC}"
    exit 1
}

docker-compose -f "${PROJECT_ROOT}/docker-compose.prod.yml" push || {
    echo -e "${RED}Error: Dockerイメージのプッシュに失敗しました${NC}"
    exit 1
}

# バックエンドのタスク定義の更新
echo "Updating backend task definition..."

# Secrets ManagerのARNを取得
SECRETS_ARN=$(aws secretsmanager describe-secret --secret-id "${PROJECT_NAME}/production/app-secrets" --query 'ARN' --output text)

BACKEND_TASK_DEFINITION=$(aws ecs describe-task-definition --task-definition ${PROJECT_NAME}-backend --query taskDefinition)
NEW_BACKEND_TASK_DEFINITION=$(echo "$BACKEND_TASK_DEFINITION" | jq --arg secrets_arn "$SECRETS_ARN" '
{
    "family": .family,
    "taskRoleArn": "arn:aws:iam::'${AWS_ACCOUNT_ID}':role/ofcrm-ecs-task-role",
    "executionRoleArn": "arn:aws:iam::'${AWS_ACCOUNT_ID}':role/ofcrm-ecs-execution-role",
    "networkMode": "awsvpc",
    "containerDefinitions": [
      .containerDefinitions[0] |
      .image = "'${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-backend:${IMAGE_TAG}'" |
      .portMappings = [
        {
          "containerPort": 80,
          "hostPort": 80,
          "protocol": "tcp"
        },
        {
          "containerPort": 6001,
          "hostPort": 6001,
          "protocol": "tcp"
        }
      ] |
      .environment = [
        {
          "name": "APP_NAME",
          "value": "'${PROJECT_NAME}'"
        },
        {
          "name": "APP_ENV",
          "value": "production"
        },
        {
          "name": "APP_DEBUG",
          "value": "false"
        },
        {
          "name": "LOG_CHANNEL",
          "value": "stderr"
        },
        {
          "name": "APP_URL",
          "value": "https://api.'${DOMAIN_NAME}'"
        },
        {
          "name": "LOG_LEVEL",
          "value": "error"
        },
        {
          "name": "DB_CONNECTION",
          "value": "mysql"
        },
        {
          "name": "DB_PORT",
          "value": "3306"
        },
        {
          "name": "BROADCAST_DRIVER",
          "value": "pusher"
        },
        {
          "name": "PUSHER_HOST",
          "value": "api-ap3.pusher.com"
        },
        {
          "name": "PUSHER_PORT",
          "value": "443"
        },
        {
          "name": "PUSHER_SCHEME",
          "value": "https"
        },
        {
          "name": "PUSHER_APP_CLUSTER",
          "value": "'${PUSHER_APP_CLUSTER}'"
        },
        {
          "name": "LARAVEL_WEBSOCKETS_ENABLED",
          "value": "true"
        },
        {
          "name": "LARAVEL_WEBSOCKETS_HOST",
          "value": "0.0.0.0"
        },
        {
          "name": "LARAVEL_WEBSOCKETS_PORT",
          "value": "6001"
        },
        {
          "name": "JWT_ALGO",
          "value": "HS256"
        },
        {
          "name": "FRONTEND_URL",
          "value": "https://front.'${DOMAIN_NAME}'"
        },
        {
          "name": "RUN_WEBSOCKETS",
          "value": "true"
        }
      ] |
      .secrets = [
        {
          "name": "APP_KEY",
          "valueFrom": ($secrets_arn + ":APP_KEY::")
        },
        {
          "name": "DB_HOST",
          "valueFrom": ($secrets_arn + ":DB_HOST::")
        },
        {
          "name": "DB_DATABASE",
          "valueFrom": ($secrets_arn + ":DB_DATABASE::")
        },
        {
          "name": "DB_USERNAME",
          "valueFrom": ($secrets_arn + ":DB_USERNAME::")
        },
        {
          "name": "DB_PASSWORD",
          "valueFrom": ($secrets_arn + ":DB_PASSWORD::")
        },
        {
          "name": "JWT_SECRET",
          "valueFrom": ($secrets_arn + ":JWT_SECRET::")
        },
        {
          "name": "PUSHER_APP_ID",
          "valueFrom": ($secrets_arn + ":PUSHER_APP_ID::")
        },
        {
          "name": "PUSHER_APP_KEY",
          "valueFrom": ($secrets_arn + ":PUSHER_APP_KEY::")
        },
        {
          "name": "PUSHER_APP_SECRET",
          "valueFrom": ($secrets_arn + ":PUSHER_APP_SECRET::")
        }
      ] |
      .healthCheck = {
        "command": ["CMD-SHELL", "php artisan health || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      } |
      .logConfiguration = {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/'${PROJECT_NAME}'-backend",
          "awslogs-region": "'${AWS_REGION}'",
          "awslogs-stream-prefix": "ecs",
          "mode": "non-blocking",
          "max-buffer-size": "4m"
        }
      }
    ],
    "requiresCompatibilities": ["FARGATE"],
    "cpu": "256",
    "memory": "512"
}')

echo "$NEW_BACKEND_TASK_DEFINITION" > backend-task-definition.json
BACKEND_TASK_DEF_ARN=$(aws ecs register-task-definition --cli-input-json "$(cat backend-task-definition.json)" --query 'taskDefinition.taskDefinitionArn' --output text)

# フロントエンドのタスク定義の更新
echo "Updating frontend task definition..."
FRONTEND_TASK_DEFINITION=$(aws ecs describe-task-definition --task-definition ${PROJECT_NAME}-frontend --query taskDefinition)
NEW_FRONTEND_TASK_DEFINITION=$(echo $FRONTEND_TASK_DEFINITION | jq '{
    family: .family,
    taskRoleArn: "arn:aws:iam::'"${AWS_ACCOUNT_ID}"':role/ofcrm-ecs-task-role",
    executionRoleArn: "arn:aws:iam::'"${AWS_ACCOUNT_ID}"':role/ofcrm-ecs-execution-role",
    networkMode: "awsvpc",
    containerDefinitions: [
      .containerDefinitions[0] |
      .image = "'${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROJECT_NAME}-frontend:${IMAGE_TAG}'" |
      .portMappings = [
        {
          "containerPort": 3000,
          "hostPort": 3000,
          "protocol": "tcp"
        }
      ] |
      .environment = [
        {
          "name": "NODE_ENV",
          "value": "production"
        },
        {
          "name": "NEXT_PUBLIC_APP_ENV",
          "value": "production"
        },
        {
          "name": "NEXT_PUBLIC_API_URL",
          "value": "https://api.'${DOMAIN_NAME}'"
        },
        {
          "name": "NEXT_PUBLIC_PUSHER_APP_KEY",
          "value": "'${PUSHER_APP_KEY}'"
        },
        {
          "name": "NEXT_PUBLIC_PUSHER_HOST",
          "value": "api-ap3.pusher.com"
        },
        {
          "name": "NEXT_PUBLIC_PUSHER_PORT",
          "value": "443"
        },
        {
          "name": "NEXT_PUBLIC_PUSHER_SCHEME",
          "value": "https"
        },
        {
          "name": "NEXT_PUBLIC_PUSHER_APP_CLUSTER",
          "value": "'${PUSHER_APP_CLUSTER}'"
        }
      ] |
      .logConfiguration = {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/'${PROJECT_NAME}'-frontend",
          "awslogs-region": "'${AWS_REGION}'",
          "awslogs-stream-prefix": "ecs"
        }
      }
    ],
    requiresCompatibilities: ["FARGATE"],
    cpu: "256",
    memory: "512"
}')

echo "$NEW_FRONTEND_TASK_DEFINITION" > frontend-task-definition.json
FRONTEND_TASK_DEF_ARN=$(aws ecs register-task-definition --cli-input-json "$(cat frontend-task-definition.json)" --query 'taskDefinition.taskDefinitionArn' --output text)

# ECSサービスの更新
echo "ECSサービスの更新中..."
echo "Updating backend service..."
aws ecs update-service \
    --cluster ${PROJECT_NAME}-cluster \
    --service ${PROJECT_NAME}-backend-service \
    --task-definition ${BACKEND_TASK_DEF_ARN} \
    --force-new-deployment \
    --platform-version "1.4.0" \
    --deployment-configuration '{
        "deploymentCircuitBreaker": {
            "enable": true,
            "rollback": true
        },
        "maximumPercent": 200,
        "minimumHealthyPercent": 50
    }' \
    --network-configuration '{
        "awsvpcConfiguration": {
            "subnets": ["'$PRIVATE_SUBNET_1'", "'$PRIVATE_SUBNET_2'"],
            "securityGroups": ["'$ECS_TASKS_SG'"],
            "assignPublicIp": "DISABLED"
        }
    }'

echo "Updating frontend service..."
aws ecs update-service \
    --cluster ${PROJECT_NAME}-cluster \
    --service ${PROJECT_NAME}-frontend-service \
    --task-definition ${FRONTEND_TASK_DEF_ARN} \
    --force-new-deployment \
    --platform-version "1.4.0" \
    --deployment-configuration '{
        "deploymentCircuitBreaker": {
            "enable": true,
            "rollback": true
        },
        "maximumPercent": 200,
        "minimumHealthyPercent": 50
    }' \
    --network-configuration '{
        "awsvpcConfiguration": {
            "subnets": ["'$PRIVATE_SUBNET_1'", "'$PRIVATE_SUBNET_2'"],
            "securityGroups": ["'$ECS_TASKS_SG'"],
            "assignPublicIp": "DISABLED"
        }
    }'

# サービスの安定化を待機
echo "サービスの安定化を待機中..."
echo "Waiting additional time for container initialization..."
sleep 120  # コンテナの初期化待機

# バックエンドの健全性チェック
echo "Verifying backend deployment..."
HEALTH_CHECK_URL="https://${ALB_DNS_NAME}/health"
HOST_HEADER="api.${DOMAIN_NAME}"
MAX_RETRIES=15
RETRY_INTERVAL=30

for i in $(seq 1 $MAX_RETRIES); do
    echo "Attempt $i: Checking ALB health check endpoint"
    if curl -s -f -k -H "Host: ${HOST_HEADER}" "${HEALTH_CHECK_URL}" > /dev/null; then
        echo "Backend health check passed!"
        break
    fi
    if [ $i -eq $MAX_RETRIES ]; then
        echo "Backend health check failed after $MAX_RETRIES attempts"
        exit 1
    fi
    echo "Waiting $RETRY_INTERVAL seconds before next attempt..."
    sleep $RETRY_INTERVAL
done

# WebSocket検証
echo "Verifying WebSocket..."
MAX_RETRIES=5
RETRY_INTERVAL=30

echo "Testing service health..."
for i in $(seq 1 $MAX_RETRIES); do
    echo "Attempt $i: Checking service health..."
    if curl -s -f -k -H "Host: ${HOST_HEADER}" "${HEALTH_CHECK_URL}" > /dev/null; then
        echo "Service health check passed!"
        break
    fi
    if [ $i -eq $MAX_RETRIES ]; then
        echo "Service health check failed after $MAX_RETRIES attempts"
        exit 1
    fi
    sleep $RETRY_INTERVAL
done

# フロントエンドの健全性チェック
echo "Verifying frontend deployment..."
FRONTEND_HEALTH_URL="https://${ALB_DNS_NAME}"
FRONTEND_HOST_HEADER="front.${DOMAIN_NAME}"
for i in $(seq 1 $MAX_RETRIES); do
    echo "Attempt $i: Checking frontend..."
    if curl -s -f -k -H "Host: ${FRONTEND_HOST_HEADER}" "${FRONTEND_HEALTH_URL}" > /dev/null; then
        echo "Frontend health check passed!"
        break
    fi
    if [ $i -eq $MAX_RETRIES ]; then
        echo "Frontend health check failed after $MAX_RETRIES attempts"
        exit 1
    fi
    echo "Waiting $RETRY_INTERVAL seconds before next attempt..."
    sleep $RETRY_INTERVAL
done

# ECSサービスの状態確認
for SERVICE in "backend" "frontend"; do
    echo "Checking $SERVICE service status..."
    aws ecs describe-services \
        --cluster ${PROJECT_NAME}-cluster \
        --services ${PROJECT_NAME}-${SERVICE}-service \
        --query 'services[0].{status: status, desiredCount: desiredCount, runningCount: runningCount, pendingCount: pendingCount}'

    # サービスの安定化を待機
    echo "Waiting for $SERVICE service to be stable..."
    aws ecs wait services-stable \
        --cluster ${PROJECT_NAME}-cluster \
        --services ${PROJECT_NAME}-${SERVICE}-service || {
        echo -e "${RED}Error: ${SERVICE}サービスの安定化に失敗しました${NC}"
        exit 1
    }
done

# 最終確認のための待機
echo "Waiting final verification period..."
sleep 60

# 最終ヘルスチェック
echo "Performing final health checks..."

# バックエンドの最終確認
if ! curl -s -f -k -H "Host: ${HOST_HEADER}" "${HEALTH_CHECK_URL}" > /dev/null; then
    echo -e "${RED}Error: Backend final health check failed${NC}"
    exit 1
fi
echo "Backend final health check passed"

# フロントエンドの最終確認
if ! curl -s -f -k -H "Host: ${FRONTEND_HOST_HEADER}" "${FRONTEND_HEALTH_URL}" > /dev/null; then
    echo -e "${RED}Error: Frontend final health check failed${NC}"
    exit 1
fi
echo "Frontend final health check passed"

echo -e "${GREEN}デプロイが完了しました！${NC}"
echo "Backend URL: https://api.${DOMAIN_NAME}"
echo "Frontend URL: https://front.${DOMAIN_NAME}"
echo "WebSocket URL: wss://api.${DOMAIN_NAME}/app/${PUSHER_APP_KEY}"
echo "全てのヘルスチェックが正常に完了しました。"
