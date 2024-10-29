output "backend_fqdn" {
  description = "The FQDN of the backend endpoint"
  value       = aws_route53_record.backend.fqdn
}

output "frontend_fqdn" {
  description = "The FQDN of the frontend endpoint"
  value       = aws_route53_record.frontend.fqdn
}
