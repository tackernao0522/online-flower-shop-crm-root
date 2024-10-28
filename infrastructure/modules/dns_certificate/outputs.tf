output "zone_id" {
  description = "The ID of the hosted zone"
  value       = aws_route53_zone.main.zone_id
}

output "certificate_arn" {
  description = "The ARN of the SSL certificate"
  value       = aws_acm_certificate_validation.cert_validation.certificate_arn
}

output "domain_name" {
  description = "The domain name"
  value       = var.domain_name
}

output "zone_name_servers" {
  description = "The name servers for the hosted zone"
  value       = aws_route53_zone.main.name_servers
}
