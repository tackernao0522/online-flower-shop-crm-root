output "secrets_arn" {
  description = "The ARN of the Secrets Manager secret"
  value       = aws_secretsmanager_secret.app_secrets.arn
}

output "secrets_manager_endpoint_id" {
  description = "The ID of the Secrets Manager VPC endpoint"
  value       = aws_vpc_endpoint.secretsmanager.id
}

output "secrets_security_group_id" {
  description = "The ID of the security group for Secrets Manager VPC endpoint"
  value       = aws_security_group.secrets_endpoint.id
}
