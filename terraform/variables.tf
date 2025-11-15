variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    ManagedBy   = "Terraform"
    Environment = "Production"
    Purpose     = "Security-Services"
  }
}

#######################################
# AWS Config Variables
#######################################

variable "config_bucket_prefix" {
  description = "Prefix for AWS Config S3 bucket names"
  type        = string
  default     = "aws-config"
}

variable "force_destroy_buckets" {
  description = "Allow destruction of S3 buckets even if they contain objects (use with caution)"
  type        = bool
  default     = false
}

variable "config_include_global_resources_us_east_1" {
  description = "Include global resources (like IAM) in Config for us-east-1. Should be true for only one region."
  type        = bool
  default     = true
}

variable "config_include_global_resources_us_west_2" {
  description = "Include global resources (like IAM) in Config for us-west-2. Should be false if enabled in us-east-1."
  type        = bool
  default     = false
}

#######################################
# GuardDuty Variables
#######################################

variable "guardduty_finding_frequency" {
  description = "Frequency of notifications about updated findings (FIFTEEN_MINUTES, ONE_HOUR, SIX_HOURS)"
  type        = string
  default     = "FIFTEEN_MINUTES"

  validation {
    condition     = contains(["FIFTEEN_MINUTES", "ONE_HOUR", "SIX_HOURS"], var.guardduty_finding_frequency)
    error_message = "Finding frequency must be FIFTEEN_MINUTES, ONE_HOUR, or SIX_HOURS."
  }
}

variable "guardduty_enable_s3_logs" {
  description = "Enable S3 data event logs monitoring in GuardDuty"
  type        = bool
  default     = true
}

variable "guardduty_enable_kubernetes" {
  description = "Enable Kubernetes audit logs monitoring in GuardDuty"
  type        = bool
  default     = true
}

variable "guardduty_enable_malware_protection" {
  description = "Enable malware protection for EC2 instances in GuardDuty"
  type        = bool
  default     = true
}

#######################################
# Security Hub Variables
#######################################

variable "securityhub_control_finding_generator" {
  description = "Control finding generator setting (SECURITY_CONTROL or STANDARD_CONTROL)"
  type        = string
  default     = "SECURITY_CONTROL"

  validation {
    condition     = contains(["SECURITY_CONTROL", "STANDARD_CONTROL"], var.securityhub_control_finding_generator)
    error_message = "Control finding generator must be SECURITY_CONTROL or STANDARD_CONTROL."
  }
}
