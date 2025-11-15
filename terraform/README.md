# AWS Security Services Terraform Module

This Terraform module enables and configures AWS security services across multiple regions (us-east-1 and us-west-2):

- **AWS Config**: Records and evaluates configurations of AWS resources
- **AWS GuardDuty**: Threat detection service that monitors for malicious activity
- **AWS Security Hub**: Aggregates security findings from multiple AWS services (deployed with no standards enabled)

## Features

- **Multi-region deployment**: Deploys services to both us-east-1 and us-west-2
- **Complete prerequisites**: Creates all required IAM roles, S3 buckets, and policies
- **Security best practices**:
  - S3 buckets with encryption, versioning, and public access blocking
  - Least privilege IAM roles
  - Proper service dependencies
- **Configurable**: Customizable via variables for different environments
- **Production-ready**: Includes proper tagging, monitoring, and compliance features

## Architecture

### AWS Config
- Configuration recorder to track resource changes
- S3 bucket for storing configuration snapshots and history
- IAM role with appropriate permissions
- Delivery channel for configuration data
- Separate recorders for each region (global resources tracked in us-east-1 only)

### GuardDuty
- Threat detection enabled in both regions
- Optional data sources:
  - S3 logs monitoring
  - Kubernetes audit logs
  - Malware protection for EC2 instances
- Configurable finding frequency

### Security Hub
- Centralized security findings dashboard
- No standards enabled (as requested)
- Depends on Config and GuardDuty being enabled
- Deployed in both regions for regional coverage

## Prerequisites

1. **Terraform**: Version 1.0 or higher
2. **AWS CLI**: Configured with appropriate credentials
3. **AWS Permissions**: The executing IAM user/role needs permissions to:
   - Create and manage IAM roles and policies
   - Create and manage S3 buckets
   - Enable AWS Config, GuardDuty, and Security Hub
   - Create tags on resources

### Required IAM Permissions

The following AWS managed policies provide the necessary permissions:
- `AWSConfigRole` (for AWS Config setup)
- `AmazonGuardDutyFullAccess` (for GuardDuty setup)
- `AWSSecurityHubFullAccess` (for Security Hub setup)
- `IAMFullAccess` (for creating service roles)
- `AmazonS3FullAccess` (for creating Config buckets)

Or create a custom policy with these specific permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "config:*",
        "guardduty:*",
        "securityhub:*",
        "iam:CreateRole",
        "iam:PutRolePolicy",
        "iam:AttachRolePolicy",
        "iam:GetRole",
        "iam:PassRole",
        "s3:CreateBucket",
        "s3:PutBucketPolicy",
        "s3:PutEncryptionConfiguration",
        "s3:PutBucketVersioning",
        "s3:PutBucketPublicAccessBlock"
      ],
      "Resource": "*"
    }
  ]
}
```

## Usage

### 1. Clone or Copy Files

Ensure you have all the Terraform files in your working directory:
- `main.tf`
- `variables.tf`
- `outputs.tf`
- `terraform.tfvars` (optional, for customization)

### 2. Configure Variables (Optional)

Create a `terraform.tfvars` file to customize the deployment:

```hcl
# Copy the example file
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
vim terraform.tfvars
```

### 3. Initialize Terraform

```bash
terraform init
```

This downloads the required AWS provider and initializes the backend.

### 4. Review the Plan

```bash
terraform plan
```

Review the resources that will be created. You should see:
- 2 S3 buckets (one per region for Config)
- 2 IAM roles (one per region for Config)
- 2 Config recorders
- 2 Config delivery channels
- 2 GuardDuty detectors
- 2 Security Hub accounts

### 5. Apply the Configuration

```bash
terraform apply
```

Type `yes` when prompted to create the resources.

Deployment typically takes 2-5 minutes.

### 6. Verify Deployment

After successful deployment, verify the services are enabled:

```bash
# Check AWS Config
aws configservice describe-configuration-recorders --region us-east-1
aws configservice describe-configuration-recorders --region us-west-2

# Check GuardDuty
aws guardduty list-detectors --region us-east-1
aws guardduty list-detectors --region us-west-2

# Check Security Hub
aws securityhub describe-hub --region us-east-1
aws securityhub describe-hub --region us-west-2
```

Or view the Terraform outputs:

```bash
terraform output
```

## Configuration Options

### Key Variables

| Variable | Description | Default | Options |
|----------|-------------|---------|---------|
| `config_bucket_prefix` | Prefix for Config S3 buckets | `aws-config` | Any valid S3 prefix |
| `force_destroy_buckets` | Allow bucket deletion with objects | `false` | `true`, `false` |
| `config_include_global_resources_us_east_1` | Track global resources in us-east-1 | `true` | `true`, `false` |
| `config_include_global_resources_us_west_2` | Track global resources in us-west-2 | `false` | `true`, `false` |
| `guardduty_finding_frequency` | Finding update frequency | `FIFTEEN_MINUTES` | `FIFTEEN_MINUTES`, `ONE_HOUR`, `SIX_HOURS` |
| `guardduty_enable_s3_logs` | Enable S3 data event monitoring | `true` | `true`, `false` |
| `guardduty_enable_kubernetes` | Enable K8s audit log monitoring | `true` | `true`, `false` |
| `guardduty_enable_malware_protection` | Enable malware scanning | `true` | `true`, `false` |
| `securityhub_control_finding_generator` | Control finding generator mode | `SECURITY_CONTROL` | `SECURITY_CONTROL`, `STANDARD_CONTROL` |

### Important Notes

- **Global Resources**: Only enable `config_include_global_resources` in ONE region to avoid duplicate recordings of global resources like IAM roles
- **Bucket Names**: S3 bucket names are automatically generated with the format: `{prefix}-{region}-{account_id}`
- **GuardDuty Costs**: Enabling malware protection and S3 logs increases GuardDuty costs

## Outputs

The module provides comprehensive outputs:

```bash
# View all outputs
terraform output

# View specific output
terraform output config_us_east_1
terraform output deployment_summary
```

### Available Outputs

- `account_id`: AWS Account ID
- `config_us_east_1`: Config details for us-east-1
- `config_us_west_2`: Config details for us-west-2
- `guardduty_us_east_1`: GuardDuty details for us-east-1
- `guardduty_us_west_2`: GuardDuty details for us-west-2
- `securityhub_us_east_1`: Security Hub details for us-east-1
- `securityhub_us_west_2`: Security Hub details for us-west-2
- `deployment_summary`: Complete deployment summary

## Cost Considerations

These services have associated costs:

### AWS Config
- **Configuration items**: $0.003 per item recorded
- **Rules evaluations**: $0.001 per evaluation (if you add Config rules later)
- **S3 storage**: Standard S3 pricing applies

### GuardDuty
- **CloudTrail events**: $4.45 per million events (first 400,000 free)
- **VPC Flow Logs**: $1.11 per GB (first 500 GB free)
- **DNS logs**: $0.40 per million events
- **S3 logs**: $0.50 per GB (if enabled)
- **Kubernetes audit logs**: $0.50 per GB (if enabled)
- **Malware protection**: $0.13 per GB scanned (if enabled)

### Security Hub
- **Finding ingestion events**: $0.0010 per 10,000 events (first 10,000 free per region per month)
- **Security checks**: $0.0010 per check per region per month

**Free Tier**:
- GuardDuty offers a 30-day free trial
- Security Hub offers a 30-day free trial
- AWS Config has no free tier

**Estimate**: For a small AWS environment (~500 resources), expect $50-150/month combined.

## Cleanup

To remove all resources created by this module:

```bash
terraform destroy
```

**Warning**: This will:
- Disable AWS Config, GuardDuty, and Security Hub in both regions
- Delete the S3 buckets (if `force_destroy_buckets = true`)
- Remove IAM roles

If `force_destroy_buckets = false` (default), you'll need to manually empty the S3 buckets before destroying.

## Security Considerations

1. **S3 Buckets**: All buckets are created with:
   - Server-side encryption (AES-256)
   - Versioning enabled
   - Public access blocked
   - Bucket policies restricting access to AWS Config service

2. **IAM Roles**: Follow least privilege principle with:
   - Service-specific assume role policies
   - Minimal required permissions
   - AWS managed policies where appropriate

3. **Data Retention**: Config data is retained in S3 indefinitely by default. Consider implementing lifecycle policies for cost optimization.

4. **Regional Isolation**: Each region has independent resources to ensure regional failures don't affect other regions.

## Troubleshooting

### Error: "Bucket already exists"

S3 bucket names must be globally unique. The module uses your account ID in the bucket name, but if you've run this before, modify the `config_bucket_prefix` variable.

### Error: "Access Denied" when enabling services

Ensure your AWS credentials have the necessary permissions listed in the Prerequisites section.

### Security Hub shows "Config not enabled" error

This module has proper dependencies configured. If you see this error, verify that AWS Config is actually recording by checking:

```bash
aws configservice describe-configuration-recorder-status --region us-east-1
```

The status should show `"recording": true`.

### GuardDuty findings not appearing in Security Hub

Allow 5-10 minutes for the services to fully integrate. GuardDuty findings are sent to Security Hub automatically once both are enabled.

## Extending This Module

### Adding Config Rules

To add AWS Config rules for compliance checking:

```hcl
resource "aws_config_config_rule" "s3_bucket_encryption" {
  provider = aws.us_east_1
  name     = "s3-bucket-encryption-enabled"

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED"
  }

  depends_on = [aws_config_configuration_recorder.us_east_1]
}
```

### Enabling Security Hub Standards

To enable specific standards (CIS, PCI-DSS, AWS Foundational Security Best Practices):

```hcl
resource "aws_securityhub_standards_subscription" "cis" {
  provider      = aws.us_east_1
  standards_arn = "arn:aws:securityhub:us-east-1::standards/cis-aws-foundations-benchmark/v/1.4.0"

  depends_on = [aws_securityhub_account.us_east_1]
}
```

### Adding SNS Notifications

To receive notifications for GuardDuty findings:

```hcl
resource "aws_sns_topic" "guardduty_findings" {
  provider = aws.us_east_1
  name     = "guardduty-findings"
}

resource "aws_cloudwatch_event_rule" "guardduty" {
  provider    = aws.us_east_1
  name        = "guardduty-findings"
  description = "GuardDuty findings"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
  })
}

resource "aws_cloudwatch_event_target" "sns" {
  provider  = aws.us_east_1
  rule      = aws_cloudwatch_event_rule.guardduty.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.guardduty_findings.arn
}
```

## Support

For issues or questions:
1. Check AWS service quotas in your account
2. Review CloudTrail logs for API errors
3. Consult AWS documentation:
   - [AWS Config](https://docs.aws.amazon.com/config/)
   - [GuardDuty](https://docs.aws.amazon.com/guardduty/)
   - [Security Hub](https://docs.aws.amazon.com/securityhub/)

## License

This project is provided as-is for AWS security automation purposes.
