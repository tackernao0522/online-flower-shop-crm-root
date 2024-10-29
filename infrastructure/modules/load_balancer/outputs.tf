output "alb_dns_name" {
  description = "The DNS name of the load balancer"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "The hosted zone ID of the load balancer"
  value       = aws_lb.main.zone_id
}

output "alb_arn" {
  description = "The ARN of the load balancer"
  value       = aws_lb.main.arn
}

output "alb_arn_suffix" {
  description = "The ARN suffix of the load balancer"
  value       = aws_lb.main.arn_suffix
}

output "https_listener_arn" {
  description = "The ARN of the HTTPS listener"
  value       = aws_lb_listener.https.arn
}

output "backend_target_group_arn" {
  description = "The ARN of the backend target group"
  value       = aws_lb_target_group.backend.arn
}

output "frontend_target_group_arn" {
  description = "The ARN of the frontend target group"
  value       = aws_lb_target_group.frontend.arn
}

output "websocket_target_group_arn" {
  description = "The ARN of the WebSocket target group"
  value       = aws_lb_target_group.websocket.arn
}

output "backend_target_group_arn_suffix" {
  description = "The ARN suffix of the backend target group"
  value       = aws_lb_target_group.backend.arn_suffix
}
