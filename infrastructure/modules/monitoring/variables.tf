variable "project_name" {
  description = "The name of the project"
  type        = string
}

variable "backend_target_group_arn_suffix" {
  description = "The ARN suffix of the backend target group"
  type        = string
}

variable "alb_arn_suffix" {
  description = "The ARN suffix of the ALB"
  type        = string
}
