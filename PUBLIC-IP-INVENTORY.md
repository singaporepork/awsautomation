# Public IP Resources Inventory Script

Shell script to identify all AWS resources with public IP addresses across all VPCs in all regions. This helps identify potential security exposure points in your AWS infrastructure.

## Overview

This script scans your entire AWS account across all regions to find resources that have public IP addresses or are publicly accessible. It's essential for:

- **Security audits**: Identify all publicly exposed resources
- **Compliance**: Ensure only authorized resources are publicly accessible
- **Cost optimization**: Find unused Elastic IPs
- **Network architecture review**: Understand your public-facing infrastructure
- **Incident response**: Quickly inventory all public entry points

## Resource Types Detected

The script identifies the following resource types with public IPs:

### 1. EC2 Instances
- Instances with public IP addresses
- Shows instance type, state, and private IP
- Identifies VPC and instance name

### 2. NAT Gateways
- All active NAT Gateways (which have public IPs)
- Shows associated subnet
- Identifies VPC

### 3. Elastic IPs (EIPs)
- All allocated Elastic IPs
- Shows association status (associated or unassociated)
- Identifies attached instance or network interface
- **Cost savings opportunity**: Unassociated EIPs incur charges

### 4. Load Balancers
- Classic Load Balancers (internet-facing)
- Application Load Balancers (internet-facing)
- Network Load Balancers (internet-facing)
- Shows DNS name and attached instances/targets

### 5. RDS Instances
- RDS instances with `PubliclyAccessible` flag enabled
- Shows engine type, instance class, and endpoint
- Identifies VPC

### 6. Network Interfaces (ENIs)
- Network interfaces with associated public IPs
- Excludes those already counted under EC2 or NAT Gateway
- Shows attachment status and description

## Prerequisites

### Required Tools

1. **AWS CLI**: Must be installed and configured
   ```bash
   aws --version
   ```

2. **jq**: JSON processor (highly recommended)
   ```bash
   # Ubuntu/Debian
   sudo apt-get install jq

   # macOS
   brew install jq

   # Amazon Linux/RHEL/CentOS
   sudo yum install jq
   ```

   **Note**: The script will work without jq but with limited functionality

### AWS Requirements

1. **AWS credentials** configured via:
   - AWS CLI: `aws configure`
   - Environment variables
   - IAM role (if running on EC2)

2. **Required IAM permissions**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeRegions",
        "ec2:DescribeInstances",
        "ec2:DescribeNatGateways",
        "ec2:DescribeAddresses",
        "ec2:DescribeNetworkInterfaces",
        "ec2:DescribeVpcs",
        "elb:DescribeLoadBalancers",
        "elbv2:DescribeLoadBalancers",
        "rds:DescribeDBInstances"
      ],
      "Resource": "*"
    }
  ]
}
```

## Usage

### Basic Usage

Run the script to scan all regions:

```bash
./find-public-ip-resources.sh
```

### Expected Runtime

- **Small accounts** (1-2 regions active): 1-2 minutes
- **Medium accounts** (5-10 regions): 3-5 minutes
- **Large accounts** (all regions, many resources): 5-10 minutes

The script provides progress updates as it checks each region.

## Output Files

The script generates three output files:

### 1. CSV File: `public-ip-resources.csv`

Comma-separated values file for easy import into spreadsheets or databases.

**Columns**:
- Region
- VPC ID
- VPC Name
- Resource Type
- Resource ID
- Resource Name
- Public IP
- Public DNS
- State
- Additional Info

**Example**:
```csv
Region,VPC ID,VPC Name,Resource Type,Resource ID,Resource Name,Public IP,Public DNS,State,Additional Info
us-east-1,vpc-12345,Production,EC2 Instance,i-abcdef123,web-server-01,54.123.45.67,ec2-54-123-45-67.compute-1.amazonaws.com,running,Type: t3.medium, Private IP: 10.0.1.50
us-east-1,vpc-12345,Production,NAT Gateway,nat-0123456789,prod-nat-gw,18.234.56.78,N/A,available,Subnet: subnet-abc123
us-west-2,vpc-67890,Development,Elastic IP,eipalloc-xyz789,Unnamed,52.45.67.89,N/A,Associated,Instance: i-xyz789, ENI: eni-123456, Private IP: 10.1.2.30
```

### 2. JSON File: `public-ip-resources.json`

Machine-readable JSON format with metadata.

**Structure**:
```json
{
  "resources": [
    {
      "region": "us-east-1",
      "vpc_id": "vpc-12345",
      "vpc_name": "Production",
      "resource_type": "EC2 Instance",
      "resource_id": "i-abcdef123",
      "resource_name": "web-server-01",
      "public_ip": "54.123.45.67",
      "public_dns": "ec2-54-123-45-67.compute-1.amazonaws.com",
      "state": "running",
      "additional_info": "Type: t3.medium, Private IP: 10.0.1.50"
    }
  ],
  "metadata": {
    "generated_at": "2024-01-15T10:30:45Z",
    "account_id": "123456789012",
    "total_resources": 156,
    "regions_checked": 17
  }
}
```

### 3. Report File: `public-ip-resources-report.txt`

Human-readable summary report.

**Contents**:
- Generation timestamp
- AWS account ID
- Summary statistics
- Resources grouped by type
- Resources grouped by region
- Resources grouped by VPC

**Example**:
```
Public IP Resources Inventory Report
Generated: Mon Jan 15 10:30:45 UTC 2024
AWS Account: 123456789012
========================================

SUMMARY
========================================
Total regions checked: 17
Total resources with public IPs: 42

Resources by type:
  15 - EC2 Instance
  8 - NAT Gateway
  6 - Elastic IP
  5 - Application Load Balancer
  4 - RDS Instance
  3 - Network Interface
  1 - Network Load Balancer

Resources by region:
  18 - us-east-1
  12 - us-west-2
  7 - eu-west-1
  5 - ap-southeast-1

Resources by VPC:
  20 - vpc-12345,Production
  15 - vpc-67890,Development
  7 - vpc-abcde,Staging
```

## Console Output

The script provides real-time progress updates:

```
===========================================
Public IP Resources Inventory
===========================================

AWS Account: 123456789012

Fetching AWS regions...
Found 17 regions to check

Checking region: us-east-1
  Checking EC2 instances... 5 found
  Checking NAT Gateways... 2 found
  Checking Elastic IPs... 3 found
  Checking Classic Load Balancers... 0 found
  Checking ALB/NLB Load Balancers... 2 found
  Checking RDS instances... 1 found
  Checking Network Interfaces... 1 found

Checking region: us-west-2
  Checking EC2 instances... 3 found
  ...

===========================================
SUMMARY
===========================================
Total regions checked: 17
Total resources with public IPs: 42

Output files generated:
  ✓ CSV:    public-ip-resources.csv
  ✓ JSON:   public-ip-resources.json
  ✓ Report: public-ip-resources-report.txt

⚠ Warning: Found resources with public IP addresses
Review the output files to assess security exposure

Top resource types found:
     15 EC2 Instance
      8 NAT Gateway
      6 Elastic IP
      5 Application Load Balancer
      4 RDS Instance
```

## Use Cases

### 1. Security Audit

Identify all publicly accessible resources for security review:

```bash
./find-public-ip-resources.sh

# Review resources
cat public-ip-resources.csv | grep -E "EC2 Instance|RDS Instance"

# Find resources in production VPCs
grep "Production" public-ip-resources.csv
```

### 2. Cost Optimization

Find unassociated Elastic IPs (which incur charges):

```bash
./find-public-ip-resources.sh

# Extract unassociated EIPs
grep "Elastic IP" public-ip-resources.csv | grep "Unassociated"
```

Each unassociated EIP costs ~$0.005/hour (~$3.60/month).

### 3. Compliance Reporting

Generate compliance reports showing all public endpoints:

```bash
./find-public-ip-resources.sh

# Generate dated report
cp public-ip-resources-report.txt "compliance-report-$(date +%Y-%m-%d).txt"

# Email to security team
mail -s "Public IP Inventory Report" security@company.com < public-ip-resources-report.txt
```

### 4. Incident Response

Quickly inventory all public entry points during security incidents:

```bash
# Run inventory
./find-public-ip-resources.sh

# Check for specific suspicious IPs
grep "54.123.45.67" public-ip-resources.csv

# List all EC2 instances by region
jq -r '.resources[] | select(.resource_type == "EC2 Instance") | "\(.region): \(.resource_id) - \(.public_ip)"' public-ip-resources.json
```

### 5. Network Architecture Review

Understand your public-facing infrastructure:

```bash
./find-public-ip-resources.sh

# Count by VPC
tail -n +2 public-ip-resources.csv | cut -d',' -f2,3 | sort | uniq -c

# Resources by type and region
jq -r '.resources | group_by(.region) | .[] | "\(.[0].region): \(. | group_by(.resource_type) | map("\(length) \(.[0].resource_type)") | join(", "))"' public-ip-resources.json
```

### 6. Scheduled Audits

Run periodic inventories via cron:

```bash
# Add to crontab
crontab -e

# Weekly inventory every Monday at 2 AM
0 2 * * 1 cd /path/to/scripts && ./find-public-ip-resources.sh && \
  mv public-ip-resources.csv "archive/public-ips-$(date +\%Y\%m\%d).csv"
```

## Analysis Examples

### Using CSV with Standard Tools

```bash
# Count resources by type
tail -n +2 public-ip-resources.csv | cut -d',' -f4 | sort | uniq -c

# Find all resources in a specific VPC
grep "vpc-12345" public-ip-resources.csv

# Extract only running EC2 instances
grep "EC2 Instance" public-ip-resources.csv | grep "running"

# Sort by region
tail -n +2 public-ip-resources.csv | sort -t',' -k1
```

### Using JSON with jq

```bash
# Extract all public IPs
jq -r '.resources[].public_ip' public-ip-resources.json | grep -v "N/A"

# Find resources in specific region
jq '.resources[] | select(.region == "us-east-1")' public-ip-resources.json

# Group by resource type
jq '.resources | group_by(.resource_type) | map({type: .[0].resource_type, count: length})' public-ip-resources.json

# Find all RDS instances
jq '.resources[] | select(.resource_type == "RDS Instance")' public-ip-resources.json

# Get summary statistics
jq '.metadata' public-ip-resources.json
```

### Import into Excel/Google Sheets

1. Open Excel or Google Sheets
2. Import `public-ip-resources.csv`
3. Use filters and pivot tables to analyze data

### Import into Database

```bash
# PostgreSQL example
psql -d mydb -c "CREATE TABLE public_ip_resources (
    region VARCHAR(50),
    vpc_id VARCHAR(50),
    vpc_name VARCHAR(100),
    resource_type VARCHAR(50),
    resource_id VARCHAR(100),
    resource_name VARCHAR(100),
    public_ip VARCHAR(50),
    public_dns VARCHAR(255),
    state VARCHAR(50),
    additional_info TEXT
);"

psql -d mydb -c "\COPY public_ip_resources FROM 'public-ip-resources.csv' WITH CSV HEADER"
```

## Security Best Practices

### Minimize Public Exposure

1. **Use Private Subnets**: Place resources in private subnets when possible
2. **Use Load Balancers**: Front-end applications with ALB/NLB instead of direct public IPs
3. **Bastion Hosts**: Use bastion hosts or Session Manager instead of public EC2 instances
4. **Security Groups**: Restrict inbound rules to known IP ranges
5. **VPN/Direct Connect**: Use VPN or Direct Connect for administrative access

### Review Findings

After running the script:

1. **Question every public resource**: Does it need to be public?
2. **Check RDS instances**: Publicly accessible RDS is rarely necessary
3. **Review security groups**: Ensure proper restrictions on public resources
4. **Remove unused EIPs**: Release unassociated Elastic IPs to save costs
5. **Document public resources**: Maintain a record of approved public endpoints

### Regular Audits

- Run this script monthly or quarterly
- Compare results over time to track changes
- Alert on unexpected new public resources
- Integrate into CI/CD for infrastructure changes

## Troubleshooting

### Script runs but finds no resources

**Possible causes**:
1. All resources are in private subnets (good!)
2. AWS credentials don't have sufficient permissions
3. No resources exist in any region

**Solution**: Verify permissions and check AWS Console manually

### "jq: command not found"

**Impact**: Script runs but with limited functionality

**Solution**: Install jq:
```bash
# Ubuntu/Debian
sudo apt-get install jq

# macOS
brew install jq

# Amazon Linux/RHEL
sudo yum install jq
```

### Timeout or slow performance

**Causes**:
- Many regions enabled
- Large number of resources
- API rate limiting

**Solutions**:
- Be patient; script shows progress
- Run during off-peak hours
- Consider filtering to specific regions if needed

### Permission errors

**Error**: `An error occurred (UnauthorizedOperation)`

**Solution**: Ensure IAM user/role has required permissions (see Prerequisites)

### Empty output files

**Causes**:
- Script terminated early
- Write permission issues

**Solution**:
- Check for error messages
- Ensure write permissions in current directory
- Run with `bash -x` for debugging

## Performance Considerations

- **API calls**: Makes multiple API calls per region
- **Rate limiting**: AWS may throttle requests; the script handles this gracefully
- **Regions**: Checks all enabled regions (typically 17-25)
- **Resources**: Scales well even with thousands of resources

## Integration Examples

### CI/CD Pipeline

Fail deployment if unexpected public resources are created:

```bash
#!/bin/bash
# Run inventory
./find-public-ip-resources.sh

# Check for new public resources
NEW_COUNT=$(tail -n +2 public-ip-resources.csv | wc -l)
EXPECTED_COUNT=10  # Adjust based on your environment

if [ "$NEW_COUNT" -gt "$EXPECTED_COUNT" ]; then
  echo "ERROR: Found $NEW_COUNT public resources, expected $EXPECTED_COUNT"
  echo "Review public-ip-resources.csv for details"
  exit 1
fi
```

### CloudWatch Events + Lambda

Trigger the script on a schedule using Lambda:

```python
import subprocess
import boto3

def lambda_handler(event, context):
    # Run script
    result = subprocess.run(['./find-public-ip-resources.sh'],
                          capture_output=True, text=True)

    # Upload results to S3
    s3 = boto3.client('s3')
    s3.upload_file('public-ip-resources.csv',
                   'my-security-bucket',
                   f'public-ips/{datetime.now().isoformat()}.csv')

    return {'statusCode': 200, 'body': 'Inventory complete'}
```

### Slack Notifications

Send summary to Slack:

```bash
#!/bin/bash
./find-public-ip-resources.sh

TOTAL=$(tail -n +2 public-ip-resources.csv | wc -l)

curl -X POST -H 'Content-type: application/json' \
  --data "{\"text\":\"Public IP Inventory: Found $TOTAL resources with public IPs\"}" \
  $SLACK_WEBHOOK_URL
```

## Advanced Usage

### Filter Specific Regions

Modify the script to check only specific regions:

```bash
# Edit the script and change the REGIONS line:
REGIONS="us-east-1 us-west-2 eu-west-1"
# Instead of:
# REGIONS=$(aws ec2 describe-regions --query 'Regions[].RegionName' --output text)
```

### Custom Output Location

Specify output directory:

```bash
# Edit script variables at the top:
OUTPUT_DIR="/var/reports"
CSV_OUTPUT="$OUTPUT_DIR/public-ip-resources.csv"
JSON_OUTPUT="$OUTPUT_DIR/public-ip-resources.json"
REPORT_FILE="$OUTPUT_DIR/public-ip-resources-report.txt"
```

### Add Email Notification

Add at the end of the script:

```bash
# Email results
mail -s "Public IP Inventory - $TOTAL_RESOURCES resources found" \
     -a "$CSV_OUTPUT" \
     security@company.com < "$REPORT_FILE"
```

## Limitations

1. **Point-in-time snapshot**: Resources may change after the script runs
2. **API-based**: Relies on AWS API accuracy
3. **No cost information**: Doesn't calculate actual costs
4. **No historical tracking**: Use separate tools for trending
5. **ECS/EKS**: Limited coverage of container-based resources

## Best Practices

1. **Run regularly**: Monthly or quarterly audits
2. **Version control**: Track output files in git for historical comparison
3. **Automate**: Schedule via cron or Lambda
4. **Review**: Don't just collect data—act on findings
5. **Document**: Maintain a record of approved public resources
6. **Alert**: Set up alerts for unexpected changes

## License

This project is provided as-is for AWS security auditing purposes.
