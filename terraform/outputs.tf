output "account_id" {
  description = "AWS Account ID where services are enabled"
  value       = data.aws_caller_identity.current.account_id
}

#######################################
# AWS Config Outputs
#######################################

output "config_us_east_1" {
  description = "AWS Config information for us-east-1"
  value = {
    recorder_name  = aws_config_configuration_recorder.us_east_1.name
    recorder_id    = aws_config_configuration_recorder.us_east_1.id
    s3_bucket      = aws_s3_bucket.config_us_east_1.id
    s3_bucket_arn  = aws_s3_bucket.config_us_east_1.arn
    iam_role_arn   = aws_iam_role.config_us_east_1.arn
    iam_role_name  = aws_iam_role.config_us_east_1.name
  }
}

output "config_us_west_2" {
  description = "AWS Config information for us-west-2"
  value = {
    recorder_name  = aws_config_configuration_recorder.us_west_2.name
    recorder_id    = aws_config_configuration_recorder.us_west_2.id
    s3_bucket      = aws_s3_bucket.config_us_west_2.id
    s3_bucket_arn  = aws_s3_bucket.config_us_west_2.arn
    iam_role_arn   = aws_iam_role.config_us_west_2.arn
    iam_role_name  = aws_iam_role.config_us_west_2.name
  }
}

#######################################
# GuardDuty Outputs
#######################################

output "guardduty_us_east_1" {
  description = "GuardDuty detector information for us-east-1"
  value = {
    detector_id = aws_guardduty_detector.us_east_1.id
    status      = aws_guardduty_detector.us_east_1.enable ? "ENABLED" : "DISABLED"
    account_id  = aws_guardduty_detector.us_east_1.account_id
  }
}

output "guardduty_us_west_2" {
  description = "GuardDuty detector information for us-west-2"
  value = {
    detector_id = aws_guardduty_detector.us_west_2.id
    status      = aws_guardduty_detector.us_west_2.enable ? "ENABLED" : "DISABLED"
    account_id  = aws_guardduty_detector.us_west_2.account_id
  }
}

#######################################
# Security Hub Outputs
#######################################

output "securityhub_us_east_1" {
  description = "Security Hub information for us-east-1"
  value = {
    hub_arn              = aws_securityhub_account.us_east_1.arn
    subscribed_at        = aws_securityhub_account.us_east_1.id
    standards_enabled    = []  # No standards enabled as requested
  }
}

output "securityhub_us_west_2" {
  description = "Security Hub information for us-west-2"
  value = {
    hub_arn              = aws_securityhub_account.us_west_2.arn
    subscribed_at        = aws_securityhub_account.us_west_2.id
    standards_enabled    = []  # No standards enabled as requested
  }
}

#######################################
# Summary Output
#######################################

output "deployment_summary" {
  description = "Summary of all deployed security services"
  value = {
    regions = ["us-east-1", "us-west-2"]
    services = {
      aws_config = {
        enabled = true
        regions = ["us-east-1", "us-west-2"]
        s3_buckets = [
          aws_s3_bucket.config_us_east_1.id,
          aws_s3_bucket.config_us_west_2.id
        ]
      }
      guardduty = {
        enabled = true
        regions = ["us-east-1", "us-west-2"]
        detector_ids = [
          aws_guardduty_detector.us_east_1.id,
          aws_guardduty_detector.us_west_2.id
        ]
      }
      security_hub = {
        enabled = true
        regions = ["us-east-1", "us-west-2"]
        standards_enabled = false
      }
    }
  }
}
