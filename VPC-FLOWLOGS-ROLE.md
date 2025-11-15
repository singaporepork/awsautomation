# VPC Flow Logs IAM Role Setup Scripts

Scripts to create an IAM role for VPC Flow Logs to publish flow log data to CloudWatch Logs, following AWS best practices and official documentation.

**Available Versions:**
- `create-vpc-flowlogs-role.sh` - Bash script for Linux/macOS
- `create-vpc-flowlogs-role.ps1` - PowerShell script for Windows

Both scripts provide identical functionality and create the same IAM resources.

## Overview

These scripts automate the creation of an IAM role with the proper trust policy and permissions required for VPC Flow Logs to publish data to CloudWatch Logs. This is a prerequisite for enabling VPC Flow Logs with CloudWatch as the destination.

### What Gets Created

1. **IAM Role**: Named `VPCFlowLogsRole` (customizable)
   - Trust policy allowing `vpc-flow-logs.amazonaws.com` to assume the role
   - Tags for identification and management

2. **Inline IAM Policy**: Named `VPCFlowLogsPolicy` (customizable)
   - Permissions to create log groups and streams
   - Permissions to put log events
   - Permissions to describe log groups and streams

### Why This Is Needed

VPC Flow Logs needs an IAM role to:
- Create CloudWatch Log Groups (if they don't exist)
- Create CloudWatch Log Streams for each network interface
- Write flow log records to CloudWatch Logs

Without this role, you cannot enable VPC Flow Logs with CloudWatch Logs as the destination.

## Prerequisites

### Bash Script (Linux/macOS)

- AWS CLI installed and configured
- Bash 4.0 or higher
- AWS credentials with IAM permissions (see below)

### PowerShell Script (Windows)

- PowerShell 5.0 or later
- AWS CLI installed and configured
- AWS credentials with IAM permissions (see below)

### Required AWS Permissions

The user/role running this script needs the following IAM permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "iam:CreateRole",
        "iam:GetRole",
        "iam:UpdateAssumeRolePolicy",
        "iam:PutRolePolicy",
        "iam:GetRolePolicy",
        "iam:TagRole"
      ],
      "Resource": "arn:aws:iam::*:role/VPCFlowLogsRole"
    },
    {
      "Effect": "Allow",
      "Action": "sts:GetCallerIdentity",
      "Resource": "*"
    }
  ]
}
```

## Usage

### Basic Usage

**Bash (Linux/macOS):**
```bash
./create-vpc-flowlogs-role.sh
```

**PowerShell (Windows):**
```powershell
.\create-vpc-flowlogs-role.ps1
```

### Custom Role Name

**Bash:**
```bash
export ROLE_NAME="MyCustomVPCFlowLogsRole"
export POLICY_NAME="MyCustomVPCFlowLogsPolicy"
./create-vpc-flowlogs-role.sh
```

**PowerShell:**
```powershell
.\create-vpc-flowlogs-role.ps1 -RoleName "MyCustomVPCFlowLogsRole" -PolicyName "MyCustomVPCFlowLogsPolicy"
```

### Update Existing Role

If the role already exists, the script will prompt for confirmation before updating.

**Skip confirmation (PowerShell only):**
```powershell
.\create-vpc-flowlogs-role.ps1 -Force
```

**Bash** (answer 'y' when prompted):
```bash
./create-vpc-flowlogs-role.sh
# When prompted: Do you want to update the existing role? (y/n): y
```

## Output

### Console Output

```
==========================================
VPC Flow Logs IAM Role Setup
==========================================

AWS Account ID: 123456789012
IAM Role Name: VPCFlowLogsRole

Creating trust policy document...
Creating permissions policy document...
Checking if IAM role already exists...
Creating IAM role: VPCFlowLogsRole...
  ✓ IAM role created
Checking for existing inline policy...
Creating inline policy...
  ✓ Permissions policy attached

==========================================
Setup Complete!
==========================================

Role Details:
  Role Name: VPCFlowLogsRole
  Role ARN:  arn:aws:iam::123456789012:role/VPCFlowLogsRole

Next Steps:
1. Create a CloudWatch Logs log group (if not already created):
   aws logs create-log-group --log-group-name /aws/vpc/flowlogs

2. Enable VPC Flow Logs using this role:
   aws ec2 create-flow-logs \
     --resource-type VPC \
     --resource-ids vpc-xxxxxxxx \
     --traffic-type ALL \
     --log-destination-type cloud-watch-logs \
     --log-group-name /aws/vpc/flowlogs \
     --deliver-logs-permission-arn arn:aws:iam::123456789012:role/VPCFlowLogsRole

==========================================

IAM role for VPC Flow Logs is ready to use!
```

## IAM Role Details

### Trust Policy

The role is created with the following trust policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "vpc-flow-logs.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

This allows the VPC Flow Logs service to assume the role.

### Permissions Policy

The role has the following inline policy attached:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ],
      "Resource": "*"
    }
  ]
}
```

This grants the minimum permissions needed for VPC Flow Logs to function.

### Resource Tagging

The role is automatically tagged with:
- `Purpose: VPCFlowLogs`
- `ManagedBy: Script`

These tags help identify the role's purpose and how it was created.

## Next Steps After Running the Script

### 1. Create CloudWatch Log Group

Before enabling VPC Flow Logs, create a CloudWatch Logs log group:

```bash
aws logs create-log-group --log-group-name /aws/vpc/flowlogs
```

**Optional:** Set retention policy to reduce costs:

```bash
# Set retention to 7 days
aws logs put-retention-policy \
  --log-group-name /aws/vpc/flowlogs \
  --retention-in-days 7

# Common retention periods: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653
```

### 2. Enable VPC Flow Logs

Use the role ARN output by the script to enable VPC Flow Logs.

#### For an Entire VPC

```bash
aws ec2 create-flow-logs \
  --resource-type VPC \
  --resource-ids vpc-xxxxxxxx \
  --traffic-type ALL \
  --log-destination-type cloud-watch-logs \
  --log-group-name /aws/vpc/flowlogs \
  --deliver-logs-permission-arn arn:aws:iam::123456789012:role/VPCFlowLogsRole
```

**Traffic type options:**
- `ALL` - Log both accepted and rejected traffic
- `ACCEPT` - Log only accepted traffic
- `REJECT` - Log only rejected traffic

#### For a Subnet

```bash
aws ec2 create-flow-logs \
  --resource-type Subnet \
  --resource-ids subnet-xxxxxxxx \
  --traffic-type ALL \
  --log-destination-type cloud-watch-logs \
  --log-group-name /aws/vpc/flowlogs \
  --deliver-logs-permission-arn arn:aws:iam::123456789012:role/VPCFlowLogsRole
```

#### For a Network Interface

```bash
aws ec2 create-flow-logs \
  --resource-type NetworkInterface \
  --resource-ids eni-xxxxxxxx \
  --traffic-type ALL \
  --log-destination-type cloud-watch-logs \
  --log-group-name /aws/vpc/flowlogs \
  --deliver-logs-permission-arn arn:aws:iam::123456789012:role/VPCFlowLogsRole
```

#### For Multiple Resources

```bash
# Multiple VPCs
aws ec2 create-flow-logs \
  --resource-type VPC \
  --resource-ids vpc-aaaaaaa vpc-bbbbbbb vpc-ccccccc \
  --traffic-type ALL \
  --log-destination-type cloud-watch-logs \
  --log-group-name /aws/vpc/flowlogs \
  --deliver-logs-permission-arn arn:aws:iam::123456789012:role/VPCFlowLogsRole
```

### 3. Verify Flow Logs Are Working

Wait a few minutes, then check if logs are appearing:

```bash
# List log streams
aws logs describe-log-streams \
  --log-group-name /aws/vpc/flowlogs \
  --max-items 5

# View recent logs
aws logs tail /aws/vpc/flowlogs --follow
```

### 4. Query Flow Logs (Optional)

Use CloudWatch Logs Insights to analyze flow logs:

```bash
# Example query: Top talkers by bytes
aws logs start-query \
  --log-group-name /aws/vpc/flowlogs \
  --start-time $(date -u -d '1 hour ago' +%s) \
  --end-time $(date -u +%s) \
  --query-string 'fields srcaddr, sum(bytes) as total_bytes | stats sum(total_bytes) by srcaddr | sort total_bytes desc | limit 10'
```

## Use Cases

### Security Monitoring

Enable flow logs on all VPCs to monitor network traffic patterns:

```bash
#!/bin/bash
# Enable flow logs on all VPCs

ROLE_ARN="arn:aws:iam::123456789012:role/VPCFlowLogsRole"
LOG_GROUP="/aws/vpc/flowlogs"

# Create log group if it doesn't exist
aws logs create-log-group --log-group-name $LOG_GROUP 2>/dev/null || true

# Get all VPC IDs
VPC_IDS=$(aws ec2 describe-vpcs --query 'Vpcs[*].VpcId' --output text)

# Enable flow logs for each VPC
for vpc_id in $VPC_IDS; do
  echo "Enabling flow logs for $vpc_id"
  aws ec2 create-flow-logs \
    --resource-type VPC \
    --resource-ids $vpc_id \
    --traffic-type ALL \
    --log-destination-type cloud-watch-logs \
    --log-group-name $LOG_GROUP \
    --deliver-logs-permission-arn $ROLE_ARN
done
```

### Troubleshooting Network Issues

Enable flow logs on specific resources during troubleshooting:

```bash
# Enable flow logs on a problematic instance's ENI
aws ec2 describe-instances \
  --instance-ids i-xxxxxxxx \
  --query 'Reservations[0].Instances[0].NetworkInterfaces[0].NetworkInterfaceId' \
  --output text | \
  xargs -I {} aws ec2 create-flow-logs \
    --resource-type NetworkInterface \
    --resource-ids {} \
    --traffic-type ALL \
    --log-destination-type cloud-watch-logs \
    --log-group-name /aws/vpc/flowlogs/troubleshooting \
    --deliver-logs-permission-arn arn:aws:iam::123456789012:role/VPCFlowLogsRole
```

### Compliance Requirements

Many compliance frameworks require network traffic logging. VPC Flow Logs help meet these requirements:

- **PCI-DSS**: Requirement 10 (Track and monitor all access to network resources)
- **HIPAA**: Technical safeguards for audit controls
- **SOC 2**: Monitoring and logging controls
- **NIST**: Network traffic logging and monitoring

## Cost Considerations

### CloudWatch Logs Costs

VPC Flow Logs to CloudWatch incur two types of costs:

1. **Data Ingestion**: ~$0.50 per GB ingested
2. **Data Storage**: ~$0.03 per GB-month

**Example monthly cost** for a busy VPC:
- 100 GB flow logs/month: ~$50 ingestion + ~$3 storage = **~$53/month**

### Cost Optimization Tips

1. **Filter traffic**: Log only rejected traffic for security monitoring
   ```bash
   --traffic-type REJECT
   ```

2. **Set retention policies**: Don't keep logs longer than needed
   ```bash
   aws logs put-retention-policy \
     --log-group-name /aws/vpc/flowlogs \
     --retention-in-days 7
   ```

3. **Use custom format**: Log only fields you need (reduces data volume)
   ```bash
   --log-format '${srcaddr} ${dstaddr} ${action}'
   ```

4. **Use S3 instead of CloudWatch**: S3 is cheaper for long-term storage
   ```bash
   --log-destination-type s3 \
   --log-destination arn:aws:s3:::my-flow-logs-bucket
   ```

## Troubleshooting

### Role Creation Fails

**Error**: `User is not authorized to perform: iam:CreateRole`

**Solution**: Ensure your AWS credentials have the required IAM permissions listed in Prerequisites.

### Flow Logs Not Appearing

**Issue**: Flow logs created but no data appearing in CloudWatch

**Possible causes**:
1. **Wait time**: Flow logs can take 10-15 minutes to start appearing
2. **No traffic**: Verify there's actual network traffic on the resource
3. **Role permissions**: Verify the role has correct permissions
4. **Log group doesn't exist**: Create the log group first

**Verification steps**:
```bash
# Check flow log status
aws ec2 describe-flow-logs --flow-log-ids fl-xxxxxxxx

# Look for DeliverLogsStatus: SUCCESS

# Check CloudWatch Logs
aws logs describe-log-streams --log-group-name /aws/vpc/flowlogs
```

### Permission Errors

**Error**: `LogDestinationPermissionIssue`

**Solution**: The role needs time to propagate. Wait 60 seconds and try again, or verify the role ARN is correct.

### Updating Existing Role

If you need to modify the existing role:

1. Run the script again - it will detect and offer to update
2. Or manually update via AWS CLI:
   ```bash
   # Update trust policy
   aws iam update-assume-role-policy \
     --role-name VPCFlowLogsRole \
     --policy-document file://trust-policy.json

   # Update permissions
   aws iam put-role-policy \
     --role-name VPCFlowLogsRole \
     --policy-name VPCFlowLogsPolicy \
     --policy-document file://permissions-policy.json
   ```

## Security Best Practices

1. **Least Privilege**: The created role has minimal permissions required for VPC Flow Logs
2. **Service-Specific**: Trust policy allows only the VPC Flow Logs service to assume the role
3. **Tagged Resources**: Role is tagged for easy identification and governance
4. **Audit Trail**: All API calls are logged in CloudTrail

## Alternative: S3 Destination

If you prefer to send flow logs to S3 instead of CloudWatch Logs:

1. Create an S3 bucket with appropriate bucket policy
2. Enable flow logs with S3 destination:
   ```bash
   aws ec2 create-flow-logs \
     --resource-type VPC \
     --resource-ids vpc-xxxxxxxx \
     --traffic-type ALL \
     --log-destination-type s3 \
     --log-destination arn:aws:s3:::my-flow-logs-bucket \
     --log-format '${srcaddr} ${dstaddr} ${srcport} ${dstport} ${protocol} ${bytes} ${action}'
   ```

**Note**: S3 destination doesn't require an IAM role, but you need to configure the bucket policy.

## References

- [AWS VPC Flow Logs Documentation](https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs.html)
- [VPC Flow Logs to CloudWatch](https://docs.aws.amazon.com/vpc/latest/tgw/flow-logs-cwl.html)
- [CloudWatch Logs Pricing](https://aws.amazon.com/cloudwatch/pricing/)
- [Flow Logs Record Examples](https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs-records-examples.html)

## License

This project is provided as-is for AWS automation purposes.
