terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Provider for us-east-1
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = var.common_tags
  }
}

# Provider for us-west-2
provider "aws" {
  alias  = "us_west_2"
  region = "us-west-2"

  default_tags {
    tags = var.common_tags
  }
}

# Get current AWS account ID and caller identity
data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

#######################################
# AWS Config - us-east-1
#######################################

# S3 bucket for AWS Config (us-east-1)
resource "aws_s3_bucket" "config_us_east_1" {
  provider = aws.us_east_1
  bucket   = "${var.config_bucket_prefix}-us-east-1-${data.aws_caller_identity.current.account_id}"

  force_destroy = var.force_destroy_buckets
}

resource "aws_s3_bucket_versioning" "config_us_east_1" {
  provider = aws.us_east_1
  bucket   = aws_s3_bucket.config_us_east_1.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config_us_east_1" {
  provider = aws.us_east_1
  bucket   = aws_s3_bucket.config_us_east_1.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "config_us_east_1" {
  provider = aws.us_east_1
  bucket   = aws_s3_bucket.config_us_east_1.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "config_us_east_1" {
  provider = aws.us_east_1
  bucket   = aws_s3_bucket.config_us_east_1.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSConfigBucketPermissionsCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.config_us_east_1.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AWSConfigBucketExistenceCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.config_us_east_1.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AWSConfigBucketDelivery"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.config_us_east_1.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# IAM role for AWS Config (us-east-1)
resource "aws_iam_role" "config_us_east_1" {
  provider = aws.us_east_1
  name     = "AWSConfigRole-us-east-1"

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
}

resource "aws_iam_role_policy_attachment" "config_us_east_1" {
  provider   = aws.us_east_1
  role       = aws_iam_role.config_us_east_1.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/ConfigRole"
}

resource "aws_iam_role_policy" "config_s3_us_east_1" {
  provider = aws.us_east_1
  name     = "config-s3-policy"
  role     = aws_iam_role.config_us_east_1.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketVersioning",
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = [
          aws_s3_bucket.config_us_east_1.arn,
          "${aws_s3_bucket.config_us_east_1.arn}/*"
        ]
      }
    ]
  })
}

# AWS Config Recorder (us-east-1)
resource "aws_config_configuration_recorder" "us_east_1" {
  provider = aws.us_east_1
  name     = "config-recorder-us-east-1"
  role_arn = aws_iam_role.config_us_east_1.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = var.config_include_global_resources_us_east_1
  }
}

# AWS Config Delivery Channel (us-east-1)
resource "aws_config_delivery_channel" "us_east_1" {
  provider       = aws.us_east_1
  name           = "config-delivery-channel-us-east-1"
  s3_bucket_name = aws_s3_bucket.config_us_east_1.id

  depends_on = [aws_config_configuration_recorder.us_east_1]
}

# Start AWS Config Recorder (us-east-1)
resource "aws_config_configuration_recorder_status" "us_east_1" {
  provider   = aws.us_east_1
  name       = aws_config_configuration_recorder.us_east_1.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.us_east_1]
}

#######################################
# AWS Config - us-west-2
#######################################

# S3 bucket for AWS Config (us-west-2)
resource "aws_s3_bucket" "config_us_west_2" {
  provider = aws.us_west_2
  bucket   = "${var.config_bucket_prefix}-us-west-2-${data.aws_caller_identity.current.account_id}"

  force_destroy = var.force_destroy_buckets
}

resource "aws_s3_bucket_versioning" "config_us_west_2" {
  provider = aws.us_west_2
  bucket   = aws_s3_bucket.config_us_west_2.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config_us_west_2" {
  provider = aws.us_west_2
  bucket   = aws_s3_bucket.config_us_west_2.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "config_us_west_2" {
  provider = aws.us_west_2
  bucket   = aws_s3_bucket.config_us_west_2.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "config_us_west_2" {
  provider = aws.us_west_2
  bucket   = aws_s3_bucket.config_us_west_2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSConfigBucketPermissionsCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.config_us_west_2.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AWSConfigBucketExistenceCheck"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:ListBucket"
        Resource = aws_s3_bucket.config_us_west_2.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "AWSConfigBucketDelivery"
        Effect = "Allow"
        Principal = {
          Service = "config.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.config_us_west_2.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"      = "bucket-owner-full-control"
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

# IAM role for AWS Config (us-west-2)
resource "aws_iam_role" "config_us_west_2" {
  provider = aws.us_west_2
  name     = "AWSConfigRole-us-west-2"

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
}

resource "aws_iam_role_policy_attachment" "config_us_west_2" {
  provider   = aws.us_west_2
  role       = aws_iam_role.config_us_west_2.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/ConfigRole"
}

resource "aws_iam_role_policy" "config_s3_us_west_2" {
  provider = aws.us_west_2
  name     = "config-s3-policy"
  role     = aws_iam_role.config_us_west_2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketVersioning",
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = [
          aws_s3_bucket.config_us_west_2.arn,
          "${aws_s3_bucket.config_us_west_2.arn}/*"
        ]
      }
    ]
  })
}

# AWS Config Recorder (us-west-2)
resource "aws_config_configuration_recorder" "us_west_2" {
  provider = aws.us_west_2
  name     = "config-recorder-us-west-2"
  role_arn = aws_iam_role.config_us_west_2.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = var.config_include_global_resources_us_west_2
  }
}

# AWS Config Delivery Channel (us-west-2)
resource "aws_config_delivery_channel" "us_west_2" {
  provider       = aws.us_west_2
  name           = "config-delivery-channel-us-west-2"
  s3_bucket_name = aws_s3_bucket.config_us_west_2.id

  depends_on = [aws_config_configuration_recorder.us_west_2]
}

# Start AWS Config Recorder (us-west-2)
resource "aws_config_configuration_recorder_status" "us_west_2" {
  provider   = aws.us_west_2
  name       = aws_config_configuration_recorder.us_west_2.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.us_west_2]
}

#######################################
# GuardDuty - us-east-1
#######################################

resource "aws_guardduty_detector" "us_east_1" {
  provider = aws.us_east_1
  enable   = true

  finding_publishing_frequency = var.guardduty_finding_frequency

  datasources {
    s3_logs {
      enable = var.guardduty_enable_s3_logs
    }
    kubernetes {
      audit_logs {
        enable = var.guardduty_enable_kubernetes
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = var.guardduty_enable_malware_protection
        }
      }
    }
  }
}

#######################################
# GuardDuty - us-west-2
#######################################

resource "aws_guardduty_detector" "us_west_2" {
  provider = aws.us_west_2
  enable   = true

  finding_publishing_frequency = var.guardduty_finding_frequency

  datasources {
    s3_logs {
      enable = var.guardduty_enable_s3_logs
    }
    kubernetes {
      audit_logs {
        enable = var.guardduty_enable_kubernetes
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = var.guardduty_enable_malware_protection
        }
      }
    }
  }
}

#######################################
# Security Hub - us-east-1
#######################################

resource "aws_securityhub_account" "us_east_1" {
  provider = aws.us_east_1

  # Security Hub requires Config and GuardDuty to be enabled first
  depends_on = [
    aws_config_configuration_recorder_status.us_east_1,
    aws_guardduty_detector.us_east_1
  ]

  enable_default_standards = false
  control_finding_generator = var.securityhub_control_finding_generator
}

#######################################
# Security Hub - us-west-2
#######################################

resource "aws_securityhub_account" "us_west_2" {
  provider = aws.us_west_2

  # Security Hub requires Config and GuardDuty to be enabled first
  depends_on = [
    aws_config_configuration_recorder_status.us_west_2,
    aws_guardduty_detector.us_west_2
  ]

  enable_default_standards = false
  control_finding_generator = var.securityhub_control_finding_generator
}
