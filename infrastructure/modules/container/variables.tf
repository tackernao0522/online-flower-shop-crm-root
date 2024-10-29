variable "project_name" {
  description = "The name of the project"
  type        = string
}

variable "aws_region" {
  description = "The AWS region to deploy to"
  type        = string
}

variable "domain_name" {
  description = "The domain name for the application"
  type        = string
}

variable "private_subnet_ids" {
  description = "The IDs of the private subnets"
  type        = list(string)
}

variable "ecs_security_group_id" {
  description = "The ID of the ECS security group"
  type        = string
}

variable "ecs_execution_role_arn" {
  description = "The ARN of the ECS execution role"
  type        = string
}

variable "ecs_task_role_arn" {
  description = "The ARN of the ECS task role"
  type        = string
}

variable "app_key" {
  description = "Laravel application key"
  type        = string
  sensitive   = true
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
  sensitive   = true
}

variable "pusher_app_cluster" {
  description = "Pusher App Cluster"
  type        = string
}

variable "jwt_secret" {
  description = "JWT secret for authentication"
  type        = string
  sensitive   = true
}

variable "jwt_algo" {
  description = "JWT algorithm"
  type        = string
}

variable "db_host" {
  description = "Database host"
  type        = string
}

variable "db_name" {
  description = "Database name"
  type        = string
}

variable "db_username" {
  description = "Database username"
  type        = string
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "backend_target_group_arn" {
  description = "The ARN of the backend target group"
  type        = string
}

variable "frontend_target_group_arn" {
  description = "The ARN of the frontend target group"
  type        = string
}

variable "websocket_target_group_arn" {
  description = "The ARN of the WebSocket target group"
  type        = string
}
