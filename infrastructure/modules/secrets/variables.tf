variable "project_name" {
  description = "The name of the project"
  type        = string
}

variable "aws_region" {
  description = "The AWS region to deploy to"
  type        = string
}

variable "vpc_id" {
  description = "The ID of the VPC"
  type        = string
}

variable "private_subnet_ids" {
  description = "The IDs of the private subnets"
  type        = list(string)
}

variable "ecs_tasks_security_group_id" {
  description = "The ID of the ECS tasks security group"
  type        = string
}

variable "ecs_task_role_id" {
  description = "The ID of the ECS task role"
  type        = string
}

# シークレット値の変数
variable "db_host" {
  description = "Database host"
  type        = string
  sensitive   = true
}

variable "db_database" {
  description = "Database name"
  type        = string
  sensitive   = true
}

variable "db_username" {
  description = "Database username"
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "app_key" {
  description = "Laravel application key"
  type        = string
  sensitive   = true
}

variable "jwt_secret" {
  description = "JWT secret key"
  type        = string
  sensitive   = true
}

variable "pusher_app_id" {
  description = "Pusher app ID"
  type        = string
  sensitive   = true
}

variable "pusher_app_key" {
  description = "Pusher app key"
  type        = string
  sensitive   = true
}

variable "pusher_app_secret" {
  description = "Pusher app secret"
  type        = string
  sensitive   = true
}

variable "aws_access_key_id" {
  description = "AWS access key ID"
  type        = string
  sensitive   = true
}

variable "aws_secret_access_key" {
  description = "AWS secret access key"
  type        = string
  sensitive   = true
}
