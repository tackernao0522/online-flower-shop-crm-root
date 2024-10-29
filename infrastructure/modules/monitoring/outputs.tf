output "backend_log_group_name" {
  description = "The name of the backend CloudWatch log group"
  value       = aws_cloudwatch_log_group.backend_logs.name
}

output "frontend_log_group_name" {
  description = "The name of the frontend CloudWatch log group"
  value       = aws_cloudwatch_log_group.frontend_logs.name
}

output "backend_health_alarm_arn" {
  description = "The ARN of the backend health alarm"
  value       = aws_cloudwatch_metric_alarm.backend_health.arn
}
