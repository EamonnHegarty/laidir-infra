output "alarm_name" {
  description = "Name of the request-flood alarm that trips the breaker."
  value       = aws_cloudwatch_metric_alarm.request_flood.alarm_name
}

output "function_name" {
  description = "Name of the breaker Lambda."
  value       = aws_lambda_function.breaker.function_name
}
