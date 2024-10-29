variable "project_name" {
  description = "The name of the project"
  type        = string
}

variable "vpc_cidr" {
  description = "The CIDR block for the VPC"
  type        = string
}

variable "aws_region" {
  description = "The AWS region to deploy to"
  type        = string
}

variable "vpc_endpoints_security_group_id" {
  description = "Security group ID for VPC endpoints"
  type        = string
}
