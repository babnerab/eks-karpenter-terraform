# AWS Security Hub
resource "aws_securityhub_account" "main" {
  enable_default_standards = true
}

# AWS GuardDuty
resource "aws_guardduty_detector" "main" {
  enable = true

  tags = local.common_tags
}

# GuardDuty features (replace deprecated datasources)
resource "aws_guardduty_detector_feature" "s3_data_events" {
  detector_id = aws_guardduty_detector.main.id
  name        = "S3_DATA_EVENTS"
  status      = "ENABLED"
}

resource "aws_guardduty_detector_feature" "kubernetes_audit_logs" {
  detector_id = aws_guardduty_detector.main.id
  name        = "KUBERNETES_AUDIT_LOGS"
  status      = "ENABLED"
}

resource "aws_guardduty_detector_feature" "ebs_malware_protection" {
  detector_id = aws_guardduty_detector.main.id
  name        = "EBS_MALWARE_PROTECTION"
  status      = "ENABLED"
}

# CloudTrail for audit logging
resource "aws_cloudtrail" "main" {
  name                          = "${local.cluster_name}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_logging                = true

  event_selector {
    read_write_type                 = "All"
    include_management_events       = true
    data_resource {
      type   = "AWS::S3::Object"
      values = ["${aws_s3_bucket.cloudtrail.arn}/*"]
    }
  }

  tags = local.common_tags
}

# S3 bucket for CloudTrail
resource "aws_s3_bucket" "cloudtrail" {
  bucket        = "${local.cluster_name}-cloudtrail-${random_id.bucket_suffix.hex}"
  force_destroy = true

  tags = local.common_tags
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudWatch Log Groups for security monitoring
resource "aws_cloudwatch_log_group" "security_events" {
  name              = "/aws/security/${local.cluster_name}"
  retention_in_days = 30

  tags = local.common_tags
}

# CloudWatch Alarms for security events
resource "aws_cloudwatch_metric_alarm" "guardduty_findings" {
  alarm_name          = "${local.cluster_name}-guardduty-findings"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "TotalFindings"
  namespace           = "AWS/GuardDuty"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "This metric monitors GuardDuty findings"
  alarm_actions       = [aws_sns_topic.security_alerts.arn]

  tags = local.common_tags
}

# SNS Topic for security alerts
resource "aws_sns_topic" "security_alerts" {
  name = "${local.cluster_name}-security-alerts"

  tags = local.common_tags
}

# SNS Topic Policy
resource "aws_sns_topic_policy" "security_alerts" {
  arn = aws_sns_topic.security_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action = "sns:Publish"
        Resource = aws_sns_topic.security_alerts.arn
      }
    ]
  })
}

# AWS Config for compliance monitoring
resource "aws_config_configuration_recorder" "main" {
  name     = "${local.cluster_name}-config-recorder"
  role_arn = aws_iam_role.config.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }

  depends_on = [aws_config_delivery_channel.main]
}

resource "aws_config_delivery_channel" "main" {
  name           = "${local.cluster_name}-config-delivery"
  s3_bucket_name = aws_s3_bucket.config.id
}

resource "aws_s3_bucket" "config" {
  bucket        = "${local.cluster_name}-config-${random_id.bucket_suffix.hex}"
  force_destroy = true

  tags = local.common_tags
}

resource "aws_s3_bucket_versioning" "config" {
  bucket = aws_s3_bucket.config.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config" {
  bucket = aws_s3_bucket.config.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# IAM Role for AWS Config
resource "aws_iam_role" "config" {
  name = "${local.cluster_name}-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "config" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/ConfigRole"
  role       = aws_iam_role.config.name
}

resource "aws_iam_role_policy" "config_s3" {
  name = "${local.cluster_name}-config-s3-policy"
  role = aws_iam_role.config.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject"
        ]
        Resource = "${aws_s3_bucket.config.arn}/*"
      },
      {
        Effect = "Allow"
        Action = "s3:ListBucket"
        Resource = aws_s3_bucket.config.arn
      }
    ]
  })
}
