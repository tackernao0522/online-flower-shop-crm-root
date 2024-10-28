# Load Balancer関連の出力
output "alb_dns_name" {
  description = "The DNS name of the load balancer"
  value       = module.load_balancer.alb_dns_name
}

# アプリケーションURL
output "api_url" {
  description = "The URL of the API"
  value       = "https://api.${var.domain_name}"
}

output "frontend_url" {
  description = "The URL of the frontend"
  value       = "https://front.${var.domain_name}"
}

# ECRリポジトリURL
output "backend_ecr_repository_url" {
  description = "The URL of the backend ECR repository"
  value       = module.container.backend_ecr_repository_url
}

output "frontend_ecr_repository_url" {
  description = "The URL of the frontend ECR repository"
  value       = module.container.frontend_ecr_repository_url
}

# データベース関連
output "rds_endpoint" {
  description = "The endpoint of the RDS instance"
  value       = module.database.db_endpoint
}

# ネットワーク関連
output "private_subnet_1_id" {
  description = "The ID of the first private subnet"
  value       = module.networking.private_subnet_ids[0]
}

output "private_subnet_2_id" {
  description = "The ID of the second private subnet"
  value       = module.networking.private_subnet_ids[1]
}

output "ecs_tasks_security_group_id" {
  description = "The ID of the ECS tasks security group"
  value       = module.security.ecs_tasks_security_group_id
}

# DNS関連
output "nameservers" {
  description = "The nameservers for the Route 53 zone"
  value       = module.dns_certificate.zone_name_servers
}

output "certificate_arn" {
  description = "The ARN of the SSL certificate"
  value       = module.dns_certificate.certificate_arn
}

output "domain_name" {
  description = "The domain name"
  value       = var.domain_name
}

# FQDNs
output "backend_fqdn" {
  description = "The FQDN of the backend endpoint"
  value       = module.dns_records.backend_fqdn
}

output "frontend_fqdn" {
  description = "The FQDN of the frontend endpoint"
  value       = module.dns_records.frontend_fqdn
}
