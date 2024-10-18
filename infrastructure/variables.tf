variable "aws_region" {
  description = "The AWS region to deploy to"
  type        = string
}

variable "project_name" {
  description = "The name of the project"
  type        = string
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC"
  type        = string
}

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

variable "db_username" {
  description = "Username for the database"
  type        = string
}

variable "db_password" {
  description = "Password for the database"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "The name of the database"
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
