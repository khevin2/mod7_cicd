resource "aws_ecr_repository" "app" {
  name                 = var.project_name
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  encryption_configuration {
    encryption_type = "AES256"
  }
  force_delete = false
}

# Only explicitly retired demo images qualify automatically. Active, rollback
# and bootstrap images keep their immutable release tags and are never marked.
resource "aws_ecr_lifecycle_policy" "app" {
  count      = 1
  repository = aws_ecr_repository.app.name
  policy = jsonencode({
    rules = concat([{
      rulePriority = 1
      description  = "Expire explicitly retired demo images after one day"
      selection = {
        tagStatus     = "tagged"
        tagPrefixList = ["retired-demo-"]
        countType     = "sinceImagePushed"
        countUnit     = "days"
        countNumber   = 1
      }
      action = { type = "expire" }
      }], var.enable_untagged_image_expiry ? [{
      rulePriority = 2
      description  = "Expire untagged images after 30 days"
      selection = {
        tagStatus   = "untagged"
        countType   = "sinceImagePushed"
        countUnit   = "days"
        countNumber = 30
      }
      action = { type = "expire" }
    }] : [])
  })
}

resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = var.log_retention_days
}
