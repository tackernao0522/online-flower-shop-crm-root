variable "project_name" {
  description = "The name of the project"
  type        = string
}

variable "domain_name" {
  description = "The domain name for the application"
  type        = string
}

variable "zone_id" {
  description = "The ID of the Route53 hosted zone"
  type        = string
}

variable "alb_dns_name" {
  description = "The DNS name of the ALB"
  type        = string
}

variable "alb_zone_id" {
  description = "The hosted zone ID of the ALB"
  type        = string
}
