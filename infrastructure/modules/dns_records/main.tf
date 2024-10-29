# Route 53 Record for Backend
resource "aws_route53_record" "backend" {
  zone_id = var.zone_id
  name    = "api.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}

# Route 53 Record for Frontend
resource "aws_route53_record" "frontend" {
  zone_id = var.zone_id
  name    = "front.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}
