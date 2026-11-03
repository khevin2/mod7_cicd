output "ecr_repository_url" {
  value = aws_ecr_repository.app.repository_url
}
output "ecs_cluster_name" {
  value = aws_ecs_cluster.app.name
}
output "ecs_service_name" {
  value = try(aws_ecs_service.app[0].name, null)
}
output "bootstrap_task_definition_arn" {
  value = try(aws_ecs_task_definition.bootstrap[0].arn, null)
}
output "task_execution_role_arn" {
  value = aws_iam_role.execution.arn
}
output "log_group_name" {
  value = aws_cloudwatch_log_group.app.name
}
output "load_balancer_dns_name" {
  value = aws_lb.app.dns_name
}
output "ecs_host_asg_name" {
  value = aws_autoscaling_group.ecs.name
}
output "vpc_id" {
  value = aws_vpc.app.id
}
output "monitoring_alarm_names" {
  value = [aws_cloudwatch_metric_alarm.high_error_rate.alarm_name, aws_cloudwatch_metric_alarm.high_latency.alarm_name, aws_cloudwatch_metric_alarm.unhealthy_targets.alarm_name, aws_cloudwatch_metric_alarm.no_healthy_targets.alarm_name]
}
output "monitoring_dashboard_name" {
  value = aws_cloudwatch_dashboard.app.dashboard_name
}
