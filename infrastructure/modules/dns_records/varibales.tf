variable "zone_id" {
  description = "The ID of the Route53 hosted zone"
  type        = string
}

variable "domain_name" {
  description = "The domain name"
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
