# VPC Flow Logs Enablement Scripts

Scripts to automatically enable VPC Flow Logs on all VPCs across all AWS regions, with CloudWatch Logs as the destination.

**Available Versions:**
- `enable-vpc-flowlogs.sh` - Bash script for Linux/macOS
- `enable-vpc-flowlogs.ps1` - PowerShell script for Windows

Both scripts provide identical functionality and enable VPC Flow Logs with the same configuration.

## Overview

These scripts automate the process of enabling VPC Flow Logs on all VPCs in your AWS account across all regions. They handle:

- Automatic region discovery
- VPC enumeration in each region
- CloudWatch Log Group creation
- Flow logs enablement with proper IAM role
- Skipping VPCs that already have flow logs enabled
- Detailed reporting with CSV and summary outputs

### What Gets Enabled

For each VPC that doesn't have flow logs:

1. **CloudWatch Log Group**: Created in each region (if it doesn't exist)
2. **VPC Flow Logs**: Enabled with configurable traffic type
3. **Delivery to CloudWatch**: Uses IAM role for log delivery

### Why This Is Needed

VPC Flow Logs provide visibility into network traffic for:
- **Security monitoring**: Detect unusual traffic patterns
- **Troubleshooting**: Diagnose connectivity issues
- **Compliance**: Meet audit and regulatory requirements
- **Cost optimization**: Identify traffic patterns and optimize routes

## Prerequisites

### Bash Script (Linux/macOS)

- AWS CLI installed and configured
- Bash 4.0 or higher
- `jq` command-line JSON processor
- AWS credentials with required permissions (see below)

### PowerShell Script (Windows)

- PowerShell 5.0 or later
- AWS CLI installed and configured
- AWS credentials with required permissions (see below)

### IAM Role for VPC Flow Logs

**REQUIRED**: You must have an IAM role for VPC Flow Logs before running these scripts.

Create the role using one of these methods:

**Option 1: Use the provided scripts**
```bash
# Bash
./create-vpc-flowlogs-role.sh

# PowerShell
.\create-vpc-flowlogs-role.ps1
```

**Option 2: Manual creation**
See [VPC-FLOWLOGS-ROLE.md](VPC-FLOWLOGS-ROLE.md) for detailed instructions.

The role ARN will be auto-detected if named `VPCFlowLogsRole`, or you can specify a custom role ARN.

### Required AWS Permissions

The user/role running these scripts needs the following IAM permissions:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeRegions",
        "ec2:DescribeVpcs",
        "ec2:DescribeFlowLogs",
        "ec2:CreateFlowLogs",
        "ec2:CreateTags",
        "logs:CreateLogGroup",
        "logs:DescribeLogGroups",
        "logs:PutRetentionPolicy",
        "iam:GetRole",
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
```

## Usage

### Basic Usage

**Bash (Linux/macOS):**
```bash
./enable-vpc-flowlogs.sh
```

**PowerShell (Windows):**
```powershell
.\enable-vpc-flowlogs.ps1
```

This will:
- Use the default IAM role: `VPCFlowLogsRole`
- Create log groups with prefix: `/aws/vpc/flowlogs`
- Log all traffic (ACCEPT + REJECT)
- Enable flow logs on all VPCs across all regions

### Dry Run Mode

Preview what would be enabled without making changes:

**Bash:**
```bash
DRY_RUN=true ./enable-vpc-flowlogs.sh
```

**PowerShell:**
```powershell
.\enable-vpc-flowlogs.ps1 -DryRun
```

### Custom IAM Role

**Bash:**
```bash
export ROLE_ARN="arn:aws:iam::123456789012:role/MyFlowLogsRole"
./enable-vpc-flowlogs.sh
```

**PowerShell:**
```powershell
.\enable-vpc-flowlogs.ps1 -RoleArn "arn:aws:iam::123456789012:role/MyFlowLogsRole"
```

### Custom Log Group

**Bash:**
```bash
export LOG_GROUP_PREFIX="/aws/vpc/production-flowlogs"
./enable-vpc-flowlogs.sh
```

**PowerShell:**
```powershell
.\enable-vpc-flowlogs.ps1 -LogGroupPrefix "/aws/vpc/production-flowlogs"
```

### Log Only Rejected Traffic

For security monitoring, you might want to log only rejected traffic:

**Bash:**
```bash
export TRAFFIC_TYPE=REJECT
./enable-vpc-flowlogs.sh
```

**PowerShell:**
```powershell
.\enable-vpc-flowlogs.ps1 -TrafficType REJECT
```

**Traffic type options:**
- `ALL` - Log both accepted and rejected traffic (default)
- `ACCEPT` - Log only accepted traffic
- `REJECT` - Log only rejected traffic

### Combined Configuration

**Bash:**
```bash
export ROLE_ARN="arn:aws:iam::123456789012:role/MyFlowLogsRole"
export LOG_GROUP_PREFIX="/aws/vpc/security-flowlogs"
export TRAFFIC_TYPE=REJECT
DRY_RUN=true ./enable-vpc-flowlogs.sh
```

**PowerShell:**
```powershell
.\enable-vpc-flowlogs.ps1 `
  -RoleArn "arn:aws:iam::123456789012:role/MyFlowLogsRole" `
  -LogGroupPrefix "/aws/vpc/security-flowlogs" `
  -TrafficType REJECT `
  -DryRun
```

## Configuration Options

### Bash Script

Configure via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `ROLE_ARN` | Auto-detected | IAM role ARN for VPC Flow Logs |
| `LOG_GROUP_PREFIX` | `/aws/vpc/flowlogs` | CloudWatch Logs log group name |
| `TRAFFIC_TYPE` | `ALL` | Traffic to log: `ALL`, `ACCEPT`, or `REJECT` |
| `DRY_RUN` | `false` | Preview mode without making changes |

### PowerShell Script

Configure via parameters:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-RoleArn` | Auto-detected | IAM role ARN for VPC Flow Logs |
| `-LogGroupPrefix` | `/aws/vpc/flowlogs` | CloudWatch Logs log group name |
| `-TrafficType` | `ALL` | Traffic to log: `ALL`, `ACCEPT`, or `REJECT` |
| `-DryRun` | Off | Switch to enable preview mode |

## Output

### Console Output

```
==========================================
VPC Flow Logs Enablement
==========================================

AWS Account ID: 123456789012
Using role: arn:aws:iam::123456789012:role/VPCFlowLogsRole
Log Group Prefix: /aws/vpc/flowlogs
Traffic Type: ALL

Fetching AWS regions...
Found 16 regions to check

Checking region: us-east-1
  Found 3 VPC(s)
  VPC: vpc-abc123 (Production) - Already enabled
    Existing flow log(s): fl-0a1b2c3d4e5f6g7h8
  VPC: vpc-def456 (Development)
  Creating/verifying log group... ✓
  Enabling flow logs... ✓ Success
  VPC: vpc-ghi789 (Testing)
  Creating/verifying log group... ✓
  Enabling flow logs... ✓ Success

Checking region: us-west-2
  Found 2 VPC(s)
  VPC: vpc-jkl012 (Staging)
  Creating/verifying log group... ✓
  Enabling flow logs... ✓ Success
  VPC: vpc-mno345 (DR)
  Creating/verifying log group... ✓
  Enabling flow logs... ✓ Success

==========================================
SUMMARY
==========================================
Total regions checked: 16
Total VPCs found: 5

VPCs with flow logs enabled: 4
VPCs already had flow logs: 1

Output files:
  Summary: vpc-flowlogs-enablement-summary.txt
  CSV:     vpc-flowlogs-enablement.csv

✓ VPC Flow Logs enablement complete!
==========================================
```

### CSV Output

File: `vpc-flowlogs-enablement.csv`

```csv
Region,VPC ID,VPC Name,Status,Flow Log ID,Message
us-east-1,vpc-abc123,Production,Already Enabled,fl-0a1b2c3d4e5f6g7h8,Flow logs already active
us-east-1,vpc-def456,Development,Enabled,fl-1a2b3c4d5e6f7g8h9,Successfully enabled
us-east-1,vpc-ghi789,Testing,Enabled,fl-2a3b4c5d6e7f8g9h0,Successfully enabled
us-west-2,vpc-jkl012,Staging,Enabled,fl-3a4b5c6d7e8f9g0h1,Successfully enabled
us-west-2,vpc-mno345,DR,Enabled,fl-4a5b6c7d8e9f0g1h2,Successfully enabled
```

### Summary File

File: `vpc-flowlogs-enablement-summary.txt`

```
VPC Flow Logs Enablement Summary
Generated: 2024-01-15 14:30:00
Account: 123456789012
IAM Role: arn:aws:iam::123456789012:role/VPCFlowLogsRole
Traffic Type: ALL
Dry Run: False
========================================

  [SKIP] us-east-1 - vpc-abc123 (Production) - Already enabled: fl-0a1b2c3d4e5f6g7h8
  [ENABLED] us-east-1 - vpc-def456 (Development) - fl-1a2b3c4d5e6f7g8h9
  [ENABLED] us-east-1 - vpc-ghi789 (Testing) - fl-2a3b4c5d6e7f8g9h0
  [ENABLED] us-west-2 - vpc-jkl012 (Staging) - fl-3a4b5c6d7e8f9g0h1
  [ENABLED] us-west-2 - vpc-mno345 (DR) - fl-4a5b6c7d8e9f0g1h2

SUMMARY
========================================
Total regions checked: 16
Total VPCs found: 5
VPCs with flow logs enabled: 4
VPCs already had flow logs: 1
VPCs failed: 0
```

## Use Cases

### Enable Flow Logs on All VPCs (Basic)

For comprehensive network monitoring across your entire AWS infrastructure:

```bash
# Bash
./enable-vpc-flowlogs.sh

# PowerShell
.\enable-vpc-flowlogs.ps1
```

### Security Monitoring - Rejected Traffic Only

To monitor security events and potential attacks:

```bash
# Bash
export TRAFFIC_TYPE=REJECT
./enable-vpc-flowlogs.sh

# PowerShell
.\enable-vpc-flowlogs.ps1 -TrafficType REJECT
```

This is cost-effective for security monitoring as it only logs blocked traffic.

### Compliance Audit Preparation

Preview what would be enabled before making changes:

```bash
# Bash
DRY_RUN=true ./enable-vpc-flowlogs.sh

# PowerShell
.\enable-vpc-flowlogs.ps1 -DryRun
```

Review the output and CSV file, then run without dry run mode to enable.

### Multi-Account Setup

Use AWS Organizations and run the script in each account:

```bash
#!/bin/bash
# enable-flowlogs-all-accounts.sh

ACCOUNTS=("123456789012" "234567890123" "345678901234")
ROLE_NAME="OrganizationAccountAccessRole"

for account in "${ACCOUNTS[@]}"; do
    echo "Processing account: $account"

    # Assume role in target account
    CREDENTIALS=$(aws sts assume-role \
        --role-arn "arn:aws:iam::$account:role/$ROLE_NAME" \
        --role-session-name "EnableFlowLogs" \
        --query 'Credentials' --output json)

    export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r '.AccessKeyId')
    export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r '.SecretAccessKey')
    export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r '.SessionToken')

    # Run the enablement script
    ./enable-vpc-flowlogs.sh

    # Rename output files to include account ID
    mv vpc-flowlogs-enablement.csv "vpc-flowlogs-enablement-${account}.csv"
    mv vpc-flowlogs-enablement-summary.txt "vpc-flowlogs-enablement-summary-${account}.txt"

    unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
done
```

### Region-Specific Deployment

If you only want to enable flow logs in specific regions, modify the script or filter by region manually:

```bash
# Enable only in US regions
aws ec2 describe-regions --query 'Regions[?RegionName==`us-east-1` || RegionName==`us-west-2`].RegionName' --output text | \
while read region; do
    echo "Processing region: $region"
    # Enable flow logs for VPCs in this region
    for vpc_id in $(aws ec2 describe-vpcs --region $region --query 'Vpcs[].VpcId' --output text); do
        aws ec2 create-flow-logs \
            --region $region \
            --resource-type VPC \
            --resource-ids $vpc_id \
            --traffic-type ALL \
            --log-destination-type cloud-watch-logs \
            --log-group-name /aws/vpc/flowlogs \
            --deliver-logs-permission-arn arn:aws:iam::123456789012:role/VPCFlowLogsRole
    done
done
```

## Cost Considerations

### CloudWatch Logs Costs

VPC Flow Logs incur costs for data ingestion and storage:

1. **Data Ingestion**: ~$0.50 per GB ingested to CloudWatch Logs
2. **Data Storage**: ~$0.03 per GB-month stored

**Example monthly cost** for a moderately busy environment:
- 10 VPCs with moderate traffic (50 GB flow logs/month): ~$25 ingestion + ~$1.50 storage = **~$26.50/month**
- 50 VPCs with heavy traffic (500 GB flow logs/month): ~$250 ingestion + ~$15 storage = **~$265/month**

### Cost Optimization Strategies

#### 1. Log Only Rejected Traffic

Reduces data volume by 80-95% in typical environments:

```bash
# Bash
export TRAFFIC_TYPE=REJECT
./enable-vpc-flowlogs.sh

# PowerShell
.\enable-vpc-flowlogs.ps1 -TrafficType REJECT
```

**Savings**: If your normal traffic is 95% accepted, you reduce costs by ~95%.

#### 2. Set Retention Policies

Don't keep logs longer than needed:

```bash
# Set 7-day retention on all flow log groups
for region in $(aws ec2 describe-regions --query 'Regions[].RegionName' --output text); do
    aws logs put-retention-policy \
        --region $region \
        --log-group-name /aws/vpc/flowlogs \
        --retention-in-days 7
done
```

**Common retention periods**: 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365 days

#### 3. Use S3 Instead of CloudWatch

For long-term storage, S3 is cheaper:

```bash
# Modify the script to use S3 destination
aws ec2 create-flow-logs \
    --resource-type VPC \
    --resource-ids vpc-xxxxxxxx \
    --traffic-type ALL \
    --log-destination-type s3 \
    --log-destination arn:aws:s3:::my-flow-logs-bucket
```

**S3 costs**: ~$0.023 per GB-month (vs $0.03 for CloudWatch)

#### 4. Custom Log Format

Log only the fields you need to reduce data volume:

```bash
aws ec2 create-flow-logs \
    --resource-type VPC \
    --resource-ids vpc-xxxxxxxx \
    --traffic-type ALL \
    --log-destination-type cloud-watch-logs \
    --log-group-name /aws/vpc/flowlogs \
    --deliver-logs-permission-arn arn:aws:iam::123456789012:role/VPCFlowLogsRole \
    --log-format '${srcaddr} ${dstaddr} ${srcport} ${dstport} ${protocol} ${action}'
```

**Default format** includes 14+ fields; custom format can reduce to 6-8 essential fields.

#### 5. Selective VPC Coverage

Enable flow logs only on critical VPCs:

```bash
# Enable only on production VPCs
aws ec2 describe-vpcs --filters "Name=tag:Environment,Values=production" \
    --query 'Vpcs[].VpcId' --output text | \
    xargs -I {} aws ec2 create-flow-logs \
        --resource-type VPC \
        --resource-ids {} \
        --traffic-type ALL \
        --log-destination-type cloud-watch-logs \
        --log-group-name /aws/vpc/flowlogs \
        --deliver-logs-permission-arn arn:aws:iam::123456789012:role/VPCFlowLogsRole
```

### Cost Estimation

Before enabling, estimate costs:

```bash
# Check number of VPCs
vpc_count=$(aws ec2 describe-vpcs --all-regions --query 'Vpcs[].VpcId' | jq '. | length')
echo "Total VPCs: $vpc_count"

# Estimate: Assume average 10 GB flow logs per VPC per month
estimated_gb=$((vpc_count * 10))
estimated_cost=$(echo "$estimated_gb * 0.50 + $estimated_gb * 0.03" | bc)
echo "Estimated monthly cost: \$${estimated_cost}"
```

## Verification

After enabling flow logs, verify they're working:

### Check Flow Log Status

```bash
# List all flow logs
aws ec2 describe-flow-logs \
    --query 'FlowLogs[].{ID:FlowLogId,Status:FlowLogStatus,VPC:ResourceId,DeliverStatus:DeliverLogsStatus}' \
    --output table

# Check specific VPC
aws ec2 describe-flow-logs \
    --filter "Name=resource-id,Values=vpc-xxxxxxxx" \
    --query 'FlowLogs[].{ID:FlowLogId,Status:FlowLogStatus,DeliverStatus:DeliverLogsStatus}' \
    --output table
```

Look for:
- `FlowLogStatus: ACTIVE`
- `DeliverLogsStatus: SUCCESS`

### Check CloudWatch Logs

```bash
# List log streams (wait 10-15 minutes after enabling)
aws logs describe-log-streams \
    --log-group-name /aws/vpc/flowlogs \
    --max-items 10 \
    --query 'logStreams[].{Name:logStreamName,LastEvent:lastEventTime}' \
    --output table

# View recent logs
aws logs tail /aws/vpc/flowlogs --follow
```

### Query Flow Logs

Use CloudWatch Logs Insights:

```bash
# Top 10 source IPs by bytes transferred
aws logs start-query \
    --log-group-name /aws/vpc/flowlogs \
    --start-time $(date -u -d '1 hour ago' +%s) \
    --end-time $(date -u +%s) \
    --query-string 'fields @timestamp, srcaddr, dstaddr, bytes | stats sum(bytes) as total_bytes by srcaddr | sort total_bytes desc | limit 10'
```

## Troubleshooting

### Flow Logs Not Appearing

**Issue**: Flow logs created but no data in CloudWatch Logs

**Possible causes**:
1. **Wait time**: Flow logs can take 10-15 minutes to start appearing
2. **No traffic**: Verify there's actual network traffic on the VPC
3. **IAM role issues**: Check role permissions and trust policy
4. **Log group doesn't exist**: Ensure log group was created

**Verification steps**:
```bash
# Check flow log configuration
aws ec2 describe-flow-logs --flow-log-ids fl-xxxxxxxx

# Verify IAM role
aws iam get-role --role-name VPCFlowLogsRole
aws iam get-role-policy --role-name VPCFlowLogsRole --policy-name VPCFlowLogsPolicy

# Check log group exists
aws logs describe-log-groups --log-group-name-prefix /aws/vpc/flowlogs

# Generate some traffic
ping -c 10 <some-instance-ip>
```

### Permission Errors

**Error**: `User is not authorized to perform: ec2:CreateFlowLogs`

**Solution**: Add the required IAM permissions (see Prerequisites section).

**Error**: `LogDestinationPermissionIssue`

**Solution**:
1. Verify the IAM role ARN is correct
2. Wait 60 seconds for IAM role to propagate
3. Check the role's trust policy allows `vpc-flow-logs.amazonaws.com`

### Script Failures

**Error**: `Role ARN not found`

**Solution**:
```bash
# Create the role first
./create-vpc-flowlogs-role.sh

# Or specify custom role ARN
export ROLE_ARN="arn:aws:iam::123456789012:role/MyFlowLogsRole"
./enable-vpc-flowlogs.sh
```

**Error**: `Failed to create log group`

**Solution**: Check CloudWatch Logs permissions:
```bash
aws iam get-role-policy \
    --role-name VPCFlowLogsRole \
    --policy-name VPCFlowLogsPolicy \
    --query 'PolicyDocument.Statement[].Action'
```

Should include `logs:CreateLogGroup`.

### Delivery Errors

**Issue**: `DeliverLogsStatus: FAILED`

**Check the error**:
```bash
aws ec2 describe-flow-logs \
    --flow-log-ids fl-xxxxxxxx \
    --query 'FlowLogs[].DeliverLogsErrorMessage' \
    --output text
```

**Common errors**:
- `Access Denied`: IAM role lacks permissions
- `Rate exceeded`: Too many log writes (throttling)
- `Log group not found`: Log group was deleted

### Already Enabled VPCs

**Behavior**: Script skips VPCs with existing flow logs

**To re-enable**:
```bash
# Delete existing flow logs
aws ec2 delete-flow-logs --flow-log-ids fl-xxxxxxxx

# Run script again
./enable-vpc-flowlogs.sh
```

## Security Best Practices

1. **Least Privilege IAM**: Use the minimum required permissions
2. **Encrypt Logs**: Enable CloudWatch Logs encryption with KMS
   ```bash
   aws logs associate-kms-key \
       --log-group-name /aws/vpc/flowlogs \
       --kms-key-id arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012
   ```
3. **Secure Role**: Ensure only VPC Flow Logs service can assume the role
4. **Monitor Access**: Enable CloudTrail logging for flow log API calls
5. **Retention Policy**: Set appropriate retention to limit data exposure
6. **Access Control**: Restrict who can read flow logs using IAM policies

## Compliance Use Cases

VPC Flow Logs help meet various compliance requirements:

### PCI-DSS

**Requirement 10**: Track and monitor all access to network resources

```bash
# Enable flow logs on all VPCs containing cardholder data
export TRAFFIC_TYPE=ALL
./enable-vpc-flowlogs.sh

# Set 1-year retention for audit trail
aws logs put-retention-policy \
    --log-group-name /aws/vpc/flowlogs \
    --retention-in-days 365
```

### HIPAA

**Technical Safeguards**: Audit controls for network traffic

```bash
# Enable comprehensive logging
export TRAFFIC_TYPE=ALL
./enable-vpc-flowlogs.sh

# Encrypt logs
aws logs associate-kms-key \
    --log-group-name /aws/vpc/flowlogs \
    --kms-key-id <kms-key-arn>
```

### SOC 2

**Monitoring Controls**: Network traffic logging and analysis

```bash
# Enable flow logs with alerting
export TRAFFIC_TYPE=ALL
./enable-vpc-flowlogs.sh

# Create metric filters and alarms
aws logs put-metric-filter \
    --log-group-name /aws/vpc/flowlogs \
    --filter-name RejectCount \
    --filter-pattern '[version, account, eni, source, destination, srcport, destport, protocol, packets, bytes, windowstart, windowend, action=REJECT, flowlogstatus]' \
    --metric-transformations \
        metricName=FlowLogsRejectCount,metricNamespace=VPC,metricValue=1
```

### NIST Cybersecurity Framework

**Detect (DE)**: Continuous monitoring

```bash
# Enable comprehensive flow logging
export TRAFFIC_TYPE=ALL
./enable-vpc-flowlogs.sh

# Integrate with SIEM for analysis
# Export to S3 for long-term analysis
```

## Integration Examples

### Export to S3 for Analysis

Configure flow logs to also send to S3:

```bash
# Create S3 bucket with proper policy
aws s3api create-bucket \
    --bucket my-vpc-flowlogs-archive \
    --region us-east-1

# Bucket policy for VPC Flow Logs
cat > bucket-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AWSLogDeliveryWrite",
      "Effect": "Allow",
      "Principal": {
        "Service": "delivery.logs.amazonaws.com"
      },
      "Action": "s3:PutObject",
      "Resource": "arn:aws:s3:::my-vpc-flowlogs-archive/*"
    }
  ]
}
EOF

aws s3api put-bucket-policy \
    --bucket my-vpc-flowlogs-archive \
    --policy file://bucket-policy.json

# Subscribe CloudWatch Logs to S3
# (requires additional Kinesis Firehose setup)
```

### Athena Queries

Query flow logs with Athena for analysis:

```sql
-- Create table for VPC Flow Logs
CREATE EXTERNAL TABLE vpc_flow_logs (
  version int,
  account string,
  interfaceid string,
  sourceaddress string,
  destinationaddress string,
  sourceport int,
  destinationport int,
  protocol int,
  numpackets int,
  numbytes bigint,
  starttime int,
  endtime int,
  action string,
  logstatus string
)
PARTITIONED BY (dt string)
ROW FORMAT DELIMITED
FIELDS TERMINATED BY ' '
LOCATION 's3://my-vpc-flowlogs-archive/'
TBLPROPERTIES ("skip.header.line.count"="1");

-- Top talkers by bytes
SELECT sourceaddress, SUM(numbytes) as total_bytes
FROM vpc_flow_logs
WHERE dt = '2024-01-15'
GROUP BY sourceaddress
ORDER BY total_bytes DESC
LIMIT 10;

-- Rejected connections
SELECT sourceaddress, destinationaddress, destinationport, COUNT(*) as count
FROM vpc_flow_logs
WHERE action = 'REJECT' AND dt = '2024-01-15'
GROUP BY sourceaddress, destinationaddress, destinationport
ORDER BY count DESC;
```

### CloudWatch Alarms

Create alarms for security monitoring:

```bash
# Alarm for high reject count
aws cloudwatch put-metric-alarm \
    --alarm-name HighRejectCount \
    --alarm-description "Alert on high number of rejected connections" \
    --metric-name FlowLogsRejectCount \
    --namespace VPC \
    --statistic Sum \
    --period 300 \
    --evaluation-periods 1 \
    --threshold 1000 \
    --comparison-operator GreaterThanThreshold \
    --alarm-actions arn:aws:sns:us-east-1:123456789012:SecurityAlerts
```

## References

- [AWS VPC Flow Logs Documentation](https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs.html)
- [Publishing Flow Logs to CloudWatch Logs](https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs-cwl.html)
- [CloudWatch Logs Pricing](https://aws.amazon.com/cloudwatch/pricing/)
- [Flow Logs Record Examples](https://docs.aws.amazon.com/vpc/latest/userguide/flow-logs-records-examples.html)
- [VPC Flow Logs IAM Role Setup](VPC-FLOWLOGS-ROLE.md)

## License

This project is provided as-is for AWS automation purposes.
