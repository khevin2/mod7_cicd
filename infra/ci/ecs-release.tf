variable "ecs_release" {
  description = "Optional scoped release targets generated from the deployed ECS stack. Null grants no ECS deployment access."
  type = object({
    cluster_arn                 = string
    service_arn                 = string
    task_definition_arn_pattern = string
    execution_role_arn          = string
  })
  default = null
  validation {
    condition = var.ecs_release == null ? true : alltrue([
      can(regex("^arn:aws:ecs:eu-north-1:447558491229:cluster/[A-Za-z0-9_-]+$", var.ecs_release.cluster_arn)),
      can(regex("^arn:aws:ecs:eu-north-1:447558491229:service/[A-Za-z0-9_-]+/[A-Za-z0-9_-]+$", var.ecs_release.service_arn)),
      can(regex("^arn:aws:ecs:eu-north-1:447558491229:task-definition/[A-Za-z0-9_-]+:\\*$", var.ecs_release.task_definition_arn_pattern)),
      can(regex("^arn:aws:iam::447558491229:role/[A-Za-z0-9+=,.@_/-]+$", var.ecs_release.execution_role_arn)),
    ])
    error_message = "Release targets must use explicit resource names in account 447558491229 and eu-north-1; only the task revision may use a wildcard."
  }
}

resource "aws_iam_role_policy" "ecs_release" {
  count = var.ecs_release == null ? 0 : 1
  name  = "release-mod9-ecs-only"
  role  = aws_iam_role.publisher.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "InspectExistingService"
        Effect   = "Allow"
        Action   = ["ecs:DescribeServices"]
        Resource = var.ecs_release.service_arn
      },
      {
        Sid      = "DeployOnlyTheApprovedTaskFamily"
        Effect   = "Allow"
        Action   = ["ecs:UpdateService"]
        Resource = var.ecs_release.service_arn
        Condition = {
          ArnEquals = { "ecs:cluster" = var.ecs_release.cluster_arn }
          ArnLike   = { "ecs:task-definition" = var.ecs_release.task_definition_arn_pattern }
        }
      },
      {
        Sid      = "RegisterOnlyTheApplicationFamily"
        Effect   = "Allow"
        Action   = ["ecs:RegisterTaskDefinition"]
        Resource = var.ecs_release.task_definition_arn_pattern
      },
      {
        Sid       = "PassOnlyTheExecutionRole"
        Effect    = "Allow"
        Action    = ["iam:PassRole"]
        Resource  = var.ecs_release.execution_role_arn
        Condition = { StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" } }
      },
      {
        Sid       = "ListTasksInTheOneCluster"
        Effect    = "Allow"
        Action    = ["ecs:ListTasks"]
        Resource  = "*"
        Condition = { ArnEquals = { "ecs:cluster" = var.ecs_release.cluster_arn } }
      },
      {
        Sid      = "InspectTasksInTheOneCluster"
        Effect   = "Allow"
        Action   = ["ecs:DescribeTasks"]
        Resource = "${replace(var.ecs_release.cluster_arn, ":cluster/", ":task/")}/*"
      },
      {
        Sid       = "VerifyTargetHealth"
        Effect    = "Allow"
        Action    = ["elasticloadbalancing:DescribeTargetHealth"]
        Resource  = "*" # This read action does not support resource-level permissions.
        Condition = { StringEquals = { "aws:RequestedRegion" = "eu-north-1" } }
      },
    ]
  })
}
