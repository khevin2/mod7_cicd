# The CI host can publish to the one application repository. ECS deployment
# permissions will be added separately when the baseline service exists.
resource "aws_iam_role" "publisher" {
  name_prefix = "mod9-ci-publisher-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "publisher" {
  name = "publish-mod9-ecs-only"
  role = aws_iam_role.publisher.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "RegistryAuthentication"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*" # This ECR action does not support repository-level resources.
      },
      {
        Sid    = "PublishAndVerifyApplicationImage"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability", "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart", "ecr:CompleteLayerUpload", "ecr:PutImage",
          "ecr:DescribeImages", "ecr:BatchGetImage", "ecr:GetDownloadUrlForLayer",
        ]
        Resource = "arn:aws:ecr:eu-north-1:447558491229:repository/mod9-ecs"
      },
    ]
  })
}

resource "aws_iam_instance_profile" "publisher" {
  name_prefix = "mod9-ci-publisher-"
  role        = aws_iam_role.publisher.name
}

output "publisher_role_arn" {
  value = aws_iam_role.publisher.arn
}
