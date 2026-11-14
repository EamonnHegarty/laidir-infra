output "alerts_topic_arn" {
  description = "SNS topic that alarms publish to."
  value       = aws_sns_topic.alerts.arn
}

output "alarm_names" {
  description = "Names of the alarms created."
  value = [
    aws_cloudwatch_metric_alarm.lambda_errors.alarm_name,
    aws_cloudwatch_metric_alarm.lambda_throttles.alarm_name,
    aws_cloudwatch_metric_alarm.api_5xx.alarm_name,
    aws_cloudwatch_metric_alarm.dynamodb_throttles.alarm_name,
  ]
}
