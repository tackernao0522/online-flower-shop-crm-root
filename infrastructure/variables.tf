# 基本設定
variable "aws_region" {
  description = "The AWS region to deploy to"
  type        = string
}

# AWS認証情報
variable "aws_access_key_id" {
  description = "AWS access key ID for Secrets Manager"
  type        = string
  sensitive   = true
}

variable "aws_secret_access_key" {
  description = "AWS secret access key for Secrets Manager"
  type        = string
  sensitive   = true
}

variable "project_name" {
  description = "The name of the project"
  type        = string
}

# ネットワーク設定
variable "vpc_cidr" {
  description = "The CIDR block for the VPC"
  type        = string
}

# ドメイン設定
variable "domain_name" {
  description = "The main domain name for the application"
  type        = string
}

variable "frontend_subdomain" {
  description = "The subdomain for the frontend application"
  type        = string
  default     = "front"
}

variable "backend_subdomain" {
  description = "The subdomain for the backend API"
  type        = string
  default     = "api"
}

# データベース情報
variable "db_host" {
  description = "Database host"
  type        = string
  sensitive   = true
}

# データベース設定
variable "db_name" {
  description = "The name of the database"
  type        = string
}

variable "db_username" {
  description = "Username for the database"
  type        = string
}

variable "db_password" {
  description = "Password for the database"
  type        = string
  sensitive   = true
}

# Laravel アプリケーション設定
variable "app_key" {
  description = "Laravel application key"
  type        = string
  sensitive   = true
}

variable "jwt_secret" {
  description = "JWT secret for authentication"
  type        = string
  sensitive   = true
}

variable "jwt_algo" {
  description = "JWT algorithm to be used for authentication"
  type        = string
}

# Pusher設定
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

# Basic認証設定
variable "basic_auth_user" {
  description = "Basic authentication username for frontend"
  type        = string
}

variable "basic_auth_pass" {
  description = "Basic authentication password for frontend"
  type        = string
}
