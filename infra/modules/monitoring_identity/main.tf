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
    sid       = "WriteOnlyNamedMonitoringLogStreams"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = [for arn in var.log_group_arns : "${arn}:*"]
  }

}

resource "aws_iam_role" "this" {
  name               = format("%s-%s-monitoring-host", var.project_name, var.environment)
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "secret_read" {
  name   = "read-named-monitoring-secrets"
  role   = aws_iam_role.this.id
  policy = var.secret_read_policy_json
}

resource "aws_iam_role_policy" "cloudwatch_logs" {
  name   = "write-named-monitoring-log-groups"
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.cloudwatch_logs.json
}

resource "aws_iam_instance_profile" "this" {
  name = format("%s-%s-monitoring-host", var.project_name, var.environment)
  role = aws_iam_role.this.name
  tags = var.tags
}
