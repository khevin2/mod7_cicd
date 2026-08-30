data "aws_iam_policy_document" "kms" {
  count = var.enabled ? 1 : 0

  statement {
    sid       = "EnableAccountRootAdministration"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${var.partition}:iam::${var.account_id}:root"]
    }
  }

  statement {
    sid    = "AllowCloudTrailToEncryptThisTrailOnly"
    effect = "Allow"
    actions = [
      "kms:DescribeKey",
      "kms:GenerateDataKey*",
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:${var.partition}:cloudtrail:${var.aws_region}:${var.account_id}:trail/${var.trail_name}"]
    }
  }
}

resource "aws_kms_key" "archive" {
  count = var.enabled ? 1 : 0

  description             = "Encrypts only the ${var.trail_name} CloudTrail archive."
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms[0].json
  tags                    = merge(var.tags, { Role = "cloudtrail-archive" })
}

resource "aws_kms_alias" "archive" {
  count = var.enabled ? 1 : 0

  name          = "alias/${var.project_name}-${var.environment}-cloudtrail-archive"
  target_key_id = aws_kms_key.archive[0].key_id
}

resource "aws_s3_bucket" "archive" {
  count = var.enabled ? 1 : 0

  bucket        = var.bucket_name
  force_destroy = false
  tags          = merge(var.tags, { Role = "cloudtrail-archive" })
}

resource "aws_s3_bucket_ownership_controls" "archive" {
  count = var.enabled ? 1 : 0

  bucket = aws_s3_bucket.archive[0].id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "archive" {
  count = var.enabled ? 1 : 0

  bucket                  = aws_s3_bucket.archive[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "archive" {
  count = var.enabled ? 1 : 0

  bucket = aws_s3_bucket.archive[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "archive" {
  count = var.enabled ? 1 : 0

  bucket = aws_s3_bucket.archive[0].id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.archive[0].arn
      sse_algorithm     = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "archive" {
  count = var.enabled ? 1 : 0

  bucket = aws_s3_bucket.archive[0].id

  rule {
    id     = "cloudtrail-retention"
    status = "Enabled"

    filter {
      prefix = "${var.key_prefix}/"
    }

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_transition {
      noncurrent_days = 90
      storage_class   = "GLACIER"
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "bucket" {
  count = var.enabled ? 1 : 0

  statement {
    sid       = "AllowCloudTrailGetBucketAcl"
    effect    = "Allow"
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.archive[0].arn]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:${var.partition}:cloudtrail:${var.aws_region}:${var.account_id}:trail/${var.trail_name}"]
    }
  }

  statement {
    sid     = "AllowCloudTrailWriteOwnLogsOnly"
    effect  = "Allow"
    actions = ["s3:PutObject"]
    resources = [
      "${aws_s3_bucket.archive[0].arn}/${var.key_prefix}/AWSLogs/${var.account_id}/*",
    ]

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:${var.partition}:cloudtrail:${var.aws_region}:${var.account_id}:trail/${var.trail_name}"]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.archive[0].arn, "${aws_s3_bucket.archive[0].arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "archive" {
  count = var.enabled ? 1 : 0

  bucket = aws_s3_bucket.archive[0].id
  policy = data.aws_iam_policy_document.bucket[0].json

  depends_on = [aws_s3_bucket_public_access_block.archive]
}

resource "aws_cloudtrail" "lab" {
  count = var.enabled ? 1 : 0

  name                          = var.trail_name
  s3_bucket_name                = aws_s3_bucket.archive[0].id
  s3_key_prefix                 = var.key_prefix
  kms_key_id                    = aws_kms_key.archive[0].arn
  enable_logging                = true
  enable_log_file_validation    = true
  include_global_service_events = true
  is_multi_region_trail         = true
  is_organization_trail         = false
  tags                          = merge(var.tags, { Role = "cloudtrail" })

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  depends_on = [
    aws_s3_bucket_policy.archive,
    aws_s3_bucket_versioning.archive,
    aws_s3_bucket_server_side_encryption_configuration.archive,
  ]
}
