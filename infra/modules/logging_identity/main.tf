data "aws_iam_policy_document" "assume_ec2" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "cloudwatch_logs" {
  statement {
    sid       = "WriteOnlyNamedLogStreams"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = [for arn in var.log_group_arns : "${arn}:*"]
  }
}

resource "aws_iam_role" "this" {
  name               = format("%s-%s-%s", var.project_name, var.environment, var.role_suffix)
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "cloudwatch_logs" {
  name   = "write-named-cloudwatch-log-groups"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.cloudwatch_logs.json
}

resource "aws_iam_instance_profile" "this" {
  name = format("%s-%s-%s", var.project_name, var.environment, var.role_suffix)
  role = aws_iam_role.this.name
  tags = var.tags
}
