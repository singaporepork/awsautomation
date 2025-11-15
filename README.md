# AWS Security Automation

This repository contains tools and Infrastructure as Code (IaC) for AWS security automation, compliance monitoring, and security service deployment.

## Contents

- **[IAM Audit Scripts](#iam-audit-scripts)**: Bash and PowerShell scripts for auditing IAM security configurations
- **[Network Security Scripts](#network-security-scripts)**: Scripts for network security and public exposure analysis
- **[Python Scripts](#python-scripts)**: Python tools for exporting and analyzing security data
- **[Terraform Modules](#terraform-modules)**: Infrastructure as Code for deploying AWS security services

---

## Terraform Modules

### Security Services Deployment

**Location**: `terraform/`

Terraform module to enable and configure AWS security services across multiple regions:

- **AWS Config**: Configuration recording and compliance monitoring
- **AWS GuardDuty**: Threat detection and continuous security monitoring
- **AWS Security Hub**: Centralized security findings aggregation

**Regions**: us-east-1 and us-west-2

**Quick Start**:
```bash
cd terraform/
terraform init
terraform plan
terraform apply
```

See the [Terraform README](terraform/README.md) for complete documentation.

---

## Python Scripts

### Security Hub Findings Exporter

**File**: `export-securityhub-findings.py`

Python script to export AWS Security Hub findings from a single region to JSON format with comprehensive filtering and metadata.

**Features**:
- Complete findings export with automatic pagination
- Filter by severity, workflow status, compliance status, and record state
- Rich metadata including export timestamp and summary statistics
- Summary report with findings breakdown
- AWS profile support for multi-account access

**Prerequisites**:
- Python 3.6 or higher
- boto3 library: `pip install -r requirements.txt`
- AWS credentials configured
- Security Hub enabled in target region

**Quick Start**:
```bash
# Install dependencies
pip install -r requirements.txt

# Export all findings
./export-securityhub-findings.py --region us-east-1 --output findings.json

# Export only CRITICAL findings
./export-securityhub-findings.py \
  --region us-east-1 \
  --severity CRITICAL \
  --output critical-findings.json

# View summary only
./export-securityhub-findings.py --region us-east-1 --summary-only
```

**Common Use Cases**:
```bash
# Export NEW critical/high findings for immediate review
./export-securityhub-findings.py \
  --region us-east-1 \
  --severity CRITICAL HIGH \
  --workflow-status NEW \
  --output new-critical.json

# Export failed compliance checks
./export-securityhub-findings.py \
  --region us-east-1 \
  --compliance-status FAILED \
  --output compliance-failures.json

# Multi-region export
for region in us-east-1 us-west-2; do
  ./export-securityhub-findings.py \
    --region $region \
    --output findings-${region}.json
done
```

See [SECURITY-HUB-EXPORT.md](SECURITY-HUB-EXPORT.md) for complete documentation, including advanced filtering, integration examples, and troubleshooting.

### AMI and Snapshot Cleanup

**Files**:
- `cleanup-old-amis-snapshots.sh` - Bash script for Linux/macOS
- `cleanup-old-amis-snapshots.ps1` - PowerShell script for Windows

Scripts to identify and cleanup Amazon Machine Images (AMIs) older than a specified age threshold and their associated EBS snapshots. This helps reduce storage costs and maintain a clean AWS environment.

**Features**:
- Identifies AMIs older than specified age (default: 180 days)
- Automatically discovers and deletes associated EBS snapshots
- Dry run mode for safe preview (default behavior)
- Scans single region (configurable)
- CSV and summary file outputs
- Calculates AMI age in days
- Color-coded progress updates
- Safe deregistration with confirmation

**Prerequisites**:
- AWS CLI installed and configured
- **Bash version**: jq for JSON parsing: `sudo apt-get install jq` or `brew install jq`
- **PowerShell version**: PowerShell 5.0+ (no additional dependencies)
- AWS credentials configured
- EC2 permissions (describe-images, deregister-image, delete-snapshot)

**Quick Start**:

Bash (Linux/macOS):
```bash
# Dry run - identify old AMIs without removing them (default)
DRY_RUN=true ./cleanup-old-amis-snapshots.sh

# Cleanup old AMIs and snapshots in default region (us-east-1)
DRY_RUN=false ./cleanup-old-amis-snapshots.sh

# Cleanup in specific region with custom age threshold
AWS_REGION=us-west-2 AGE_DAYS=90 DRY_RUN=false ./cleanup-old-amis-snapshots.sh

# Preview what would be cleaned up in production region
AWS_REGION=eu-west-1 DRY_RUN=true ./cleanup-old-amis-snapshots.sh
```

PowerShell (Windows):
```powershell
# Dry run - identify old AMIs without removing them
.\cleanup-old-amis-snapshots.ps1 -DryRun

# Cleanup old AMIs and snapshots in default region (us-east-1)
.\cleanup-old-amis-snapshots.ps1

# Cleanup in specific region with custom age threshold
.\cleanup-old-amis-snapshots.ps1 -Region us-west-2 -AgeDays 90

# Preview what would be cleaned up in production region
.\cleanup-old-amis-snapshots.ps1 -Region eu-west-1 -DryRun
```

**Configuration Options**:

Bash:
- **AWS_REGION**: Target region (default: us-east-1)
- **AGE_DAYS**: Age threshold in days (default: 180)
- **DRY_RUN**: Preview mode without making changes (default: true)

PowerShell:
- **-Region**: Target region (default: us-east-1)
- **-AgeDays**: Age threshold in days (default: 180)
- **-DryRun**: Switch to enable preview mode

**Common Use Cases**:

Bash:
```bash
# Monthly cleanup of AMIs older than 180 days
DRY_RUN=false AWS_REGION=us-east-1 ./cleanup-old-amis-snapshots.sh

# Review old AMIs before cleanup
DRY_RUN=true ./cleanup-old-amis-snapshots.sh
# Review old-amis-cleanup.csv
DRY_RUN=false ./cleanup-old-amis-snapshots.sh

# Cleanup across multiple regions
for region in us-east-1 us-west-2 eu-west-1; do
  echo "Cleaning up region: $region"
  AWS_REGION=$region DRY_RUN=false ./cleanup-old-amis-snapshots.sh
done

# Aggressive cleanup (90 days)
AGE_DAYS=90 DRY_RUN=false ./cleanup-old-amis-snapshots.sh
```

PowerShell:
```powershell
# Monthly cleanup of AMIs older than 180 days
.\cleanup-old-amis-snapshots.ps1 -Region us-east-1

# Review old AMIs before cleanup
.\cleanup-old-amis-snapshots.ps1 -DryRun
# Review old-amis-cleanup.csv
.\cleanup-old-amis-snapshots.ps1

# Cleanup across multiple regions
@('us-east-1', 'us-west-2', 'eu-west-1') | ForEach-Object {
    Write-Host "Cleaning up region: $_"
    .\cleanup-old-amis-snapshots.ps1 -Region $_
}

# Aggressive cleanup (90 days)
.\cleanup-old-amis-snapshots.ps1 -AgeDays 90
```

**Cost Savings**:
- AMI storage is billed based on snapshot storage costs
- EBS snapshots cost $0.05 per GB-month (standard)
- Example: 100 GB AMI with snapshots = $5/month = $60/year per AMI
- 50 old AMIs × $60/year = **$3,000/year in storage savings**

**Safety Features**:
- Dry run mode available for safe preview
  - Bash: Default is true (must explicitly set `DRY_RUN=false`)
  - PowerShell: Use `-DryRun` switch to enable
- Only processes AMIs owned by your account
- Age verification before deletion
- Detailed logging of all operations
- CSV output for audit trail
- Automatically handles snapshot cleanup after AMI deregistration

**Output Example**:
```
==========================================
AMI and Snapshot Cleanup
==========================================

AWS Account ID: 123456789012
Region: us-east-1
Age threshold: 180 days
DRY RUN MODE: No changes will be made

Cutoff date: 2024-05-18T00:00:00.000Z
AMIs created before this date will be targeted for cleanup

Found 45 AMI(s) owned by this account

Analyzing AMIs...

AMI: ami-12345678
  Name: web-server-2023-01-15
  Created: 2023-01-15T10:30:00.000Z (304 days ago)
  State: available
  → AMI is older than 180 days
  Associated snapshots (2): snap-abc123 snap-def456
  Deregistering AMI...
    [DRY RUN] Would deregister AMI: ami-12345678
  Deleting associated snapshots...
      [DRY RUN] Would delete snapshot: snap-abc123
      [DRY RUN] Would delete snapshot: snap-def456

AMI: ami-87654321
  Name: app-server-2024-10-01
  Created: 2024-10-01T14:20:00.000Z (45 days ago)
  State: available
  → AMI is recent (< 180 days)

SUMMARY
==========================================
Total AMIs found: 45
AMIs older than 180 days: 23
Recent AMIs (< 180 days): 22

AMIs deregistered: 23
Snapshots deleted: 58

Output files:
  Summary: old-amis-cleanup-summary.txt
  CSV:     old-amis-cleanup.csv

This was a dry run. No changes were made.
Run with DRY_RUN=false to actually deregister AMIs and delete snapshots.
```

**Required AWS Permissions**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeImages",
        "ec2:DeregisterImage",
        "ec2:DescribeSnapshots",
        "ec2:DeleteSnapshot"
      ],
      "Resource": "*"
    }
  ]
}
```

**Integration Examples**:

Bash (Cron jobs):
```bash
# Monthly cleanup job - dry run for review
0 0 1 * * /usr/local/bin/cleanup-old-amis-snapshots.sh

# Quarterly aggressive cleanup
0 0 1 */3 * DRY_RUN=false AGE_DAYS=180 /usr/local/bin/cleanup-old-amis-snapshots.sh

# Pre-deployment cleanup with approval
./cleanup-old-amis-snapshots.sh > review.txt
# Review review.txt and approve
DRY_RUN=false ./cleanup-old-amis-snapshots.sh

# Multi-region with different thresholds
AWS_REGION=us-east-1 AGE_DAYS=365 DRY_RUN=false ./cleanup-old-amis-snapshots.sh
AWS_REGION=us-west-2 AGE_DAYS=180 DRY_RUN=false ./cleanup-old-amis-snapshots.sh
```

PowerShell (Scheduled tasks):
```powershell
# Monthly cleanup job via Task Scheduler
# Create scheduled task that runs:
powershell.exe -File "C:\Scripts\cleanup-old-amis-snapshots.ps1" -DryRun

# Pre-deployment cleanup with approval
.\cleanup-old-amis-snapshots.ps1 -DryRun | Out-File review.txt
# Review review.txt and approve
.\cleanup-old-amis-snapshots.ps1

# Multi-region with different thresholds
.\cleanup-old-amis-snapshots.ps1 -Region us-east-1 -AgeDays 365
.\cleanup-old-amis-snapshots.ps1 -Region us-west-2 -AgeDays 180
```

**Important Notes**:
- **AMI deregistration is irreversible** - Ensure you have proper backups
- Always run in dry-run mode first to review what will be deleted
- Consider keeping "golden images" or production AMIs regardless of age
- Use tags to mark AMIs that should be retained
- The script only processes AMIs owned by your account (not shared or public AMIs)
- Snapshots are only deleted if they were associated with the deregistered AMI

---

### Route 53 Empty Zones Cleanup

**File**: `cleanup-empty-route53-zones.py`

Python script to identify and delete Route 53 hosted zones that only contain NS and SOA records (default records). These empty zones are often leftover from testing or decommissioned applications and cost $0.50/month each.

**Features**:
- Identifies hosted zones with only default NS and SOA records
- Dry run mode for safe preview (default behavior)
- Delete mode with confirmation prompt or force flag
- CSV and JSON export of findings
- Calculates potential monthly cost savings
- Supports both public and private hosted zones
- Detailed summary reports

**Prerequisites**:
- Python 3.6 or higher
- boto3 library: `pip install -r requirements.txt`
- AWS credentials configured
- Route 53 permissions (list and delete hosted zones)

**Quick Start**:
```bash
# Install dependencies
pip install -r requirements.txt

# Dry run - identify empty zones without deleting
./cleanup-empty-route53-zones.py --dry-run

# Delete empty zones with confirmation prompt
./cleanup-empty-route53-zones.py --delete

# Delete without confirmation (use with caution!)
./cleanup-empty-route53-zones.py --delete --force

# Export findings to CSV and JSON
./cleanup-empty-route53-zones.py --dry-run --output-csv empty-zones.csv --output-json empty-zones.json

# Use specific AWS profile
./cleanup-empty-route53-zones.py --profile production --dry-run
```

**Common Use Cases**:
```bash
# Identify all empty zones and potential savings
./cleanup-empty-route53-zones.py --dry-run

# Review and export before cleanup
./cleanup-empty-route53-zones.py --dry-run --output-csv zones-to-delete.csv
# Review zones-to-delete.csv
./cleanup-empty-route53-zones.py --delete --force

# Clean up in specific account
./cleanup-empty-route53-zones.py --profile production --delete

# Automated cleanup in CI/CD (after review)
./cleanup-empty-route53-zones.py --delete --force --output-json cleanup-report.json
```

**Cost Savings**:
- Each hosted zone costs $0.50/month
- Empty zones provide no value but still incur charges
- Script calculates potential monthly savings
- Example: 20 empty zones = $10/month = $120/year in savings

**Safety Features**:
- Dry run mode by default (must explicitly use `--delete`)
- Confirmation prompt before deletion (unless `--force` used)
- Only deletes zones with ONLY NS and SOA records
- Never deletes zones with A, CNAME, MX, TXT, or other record types
- Detailed reporting of what will be/was deleted

**Output Example**:
```
Route 53 Empty Hosted Zones Cleanup
Mode: DRY RUN (identification only)

Scanning Route 53 hosted zones...
Found 15 hosted zone(s) to analyze

[1/15] Checking zone: example.com. (Public)
  → Active zone (5 records: NS=1, SOA=1, A=2, CNAME=1)
[2/15] Checking zone: old-test.com. (Public)
  → Empty zone (only NS and SOA records)
[3/15] Checking zone: staging.internal. (Private)
  → Empty zone (only NS and SOA records)
...

Empty zones found: 8
Active zones found: 7
Potential monthly savings: $4.00

SUMMARY
Total hosted zones:        15
Empty zones (NS/SOA only): 8
Active zones:              7
Potential monthly savings: $4.00

Empty zones found:
  - old-test.com. (Public)
  - staging.internal. (Private)
  - dev-environment.com. (Public)
  ...

This was a DRY RUN - no zones were deleted.
Run without --dry-run to actually delete the zones.
```

**Required AWS Permissions**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "route53:ListHostedZones",
        "route53:ListResourceRecordSets",
        "route53:GetHostedZone",
        "route53:DeleteHostedZone"
      ],
      "Resource": "*"
    }
  ]
}
```

**Integration Examples**:
```bash
# Monthly cleanup job (cron)
0 0 1 * * /usr/local/bin/cleanup-empty-route53-zones.py --delete --force --output-json /var/log/route53-cleanup.json

# Pre-deployment cleanup
./cleanup-empty-route53-zones.py --dry-run --output-csv zones.csv
if [ $(grep "Empty" zones.csv | wc -l) -gt 0 ]; then
  echo "Found empty zones to clean up"
  ./cleanup-empty-route53-zones.py --delete --force
fi

# Multi-account cleanup
for account in prod staging dev; do
  echo "Cleaning up account: $account"
  ./cleanup-empty-route53-zones.py --profile $account --delete --force
done
```

---

## Network Security Scripts

### Public IP Resources Inventory

**Files**:
- `find-public-ip-resources.sh` - Bash script for Linux/macOS
- `find-public-ip-resources.ps1` - PowerShell script for Windows

Comprehensive scripts to identify all AWS resources with public IP addresses across all VPCs in all regions.

**Resource Types Detected**:
- EC2 instances with public IPs
- NAT Gateways
- Elastic IPs (associated and unassociated)
- Load Balancers (Classic, ALB, NLB - internet-facing)
- RDS instances (publicly accessible)
- Network Interfaces with public IPs

**Features**:
- Scans all AWS regions automatically
- Generates CSV, JSON, and text report outputs
- Provides summary statistics by region, VPC, and resource type
- Color-coded console output with progress updates
- Identifies cost-saving opportunities (unassociated EIPs)

**Prerequisites**:
- AWS CLI installed and configured
- **Bash version**: jq (recommended for full functionality)
- **PowerShell version**: PowerShell 5.0+ (no additional dependencies)
- Read-only AWS permissions for EC2, ELB, RDS

**Quick Start**:
```bash
# Bash (Linux/macOS)
./find-public-ip-resources.sh

# PowerShell (Windows)
.\find-public-ip-resources.ps1

# Review outputs (same for both)
cat public-ip-resources.csv              # CSV format
cat public-ip-resources.json             # JSON format
cat public-ip-resources-report.txt       # Human-readable report
```

**Common Use Cases**:
```bash
# Find unassociated Elastic IPs (cost savings)
grep "Elastic IP" public-ip-resources.csv | grep "Unassociated"

# List all public EC2 instances
grep "EC2 Instance" public-ip-resources.csv

# Resources in specific VPC
grep "vpc-12345" public-ip-resources.csv

# Resources in production environment
grep "Production" public-ip-resources.csv

# Extract with jq
jq -r '.resources[] | select(.resource_type == "RDS Instance")' public-ip-resources.json
```

**Security Benefits**:
- Identify all publicly exposed resources for security audits
- Ensure compliance with security policies
- Find unauthorized public resources
- Support incident response investigations
- Minimize attack surface by identifying unnecessary public IPs

**Output Files**:
- `public-ip-resources.csv` - Spreadsheet-compatible format
- `public-ip-resources.json` - Machine-readable with metadata
- `public-ip-resources-report.txt` - Summary report with statistics

See [PUBLIC-IP-INVENTORY.md](PUBLIC-IP-INVENTORY.md) for complete documentation, including detailed examples, integration patterns, and analysis techniques.

### VPC Flow Logs IAM Role Setup

**Files**:
- `create-vpc-flowlogs-role.sh` - Bash script for Linux/macOS
- `create-vpc-flowlogs-role.ps1` - PowerShell script for Windows

Scripts to create an IAM role with proper trust policy and permissions for VPC Flow Logs to publish to CloudWatch Logs.

**Features**:
- Creates IAM role with VPC Flow Logs trust policy
- Attaches inline policy with required CloudWatch Logs permissions
- Updates existing role if already created
- Provides next steps for enabling flow logs
- Tags role for identification

**Prerequisites**:
- AWS CLI installed and configured
- IAM permissions to create roles and policies

**Quick Start**:
```bash
# Bash (Linux/macOS)
./create-vpc-flowlogs-role.sh

# PowerShell (Windows)
.\create-vpc-flowlogs-role.ps1

# Custom role name (PowerShell)
.\create-vpc-flowlogs-role.ps1 -RoleName "MyVPCFlowLogsRole"
```

**What Gets Created**:
- IAM role with trust policy for `vpc-flow-logs.amazonaws.com`
- Inline policy granting CloudWatch Logs permissions:
  - `logs:CreateLogGroup`
  - `logs:CreateLogStream`
  - `logs:PutLogEvents`
  - `logs:DescribeLogGroups`
  - `logs:DescribeLogStreams`

**After Running**:
```bash
# 1. Create CloudWatch log group
aws logs create-log-group --log-group-name /aws/vpc/flowlogs

# 2. Enable VPC Flow Logs
aws ec2 create-flow-logs \
  --resource-type VPC \
  --resource-ids vpc-xxxxxxxx \
  --traffic-type ALL \
  --log-destination-type cloud-watch-logs \
  --log-group-name /aws/vpc/flowlogs \
  --deliver-logs-permission-arn arn:aws:iam::ACCOUNT-ID:role/VPCFlowLogsRole
```

See [VPC-FLOWLOGS-ROLE.md](VPC-FLOWLOGS-ROLE.md) for complete documentation, including detailed usage examples, cost considerations, and troubleshooting.

### VPC Flow Logs Enablement

**Files**:
- `enable-vpc-flowlogs.sh` - Bash script for Linux/macOS
- `enable-vpc-flowlogs.ps1` - PowerShell script for Windows

Automated scripts to enable VPC Flow Logs on all VPCs across all AWS regions with CloudWatch Logs as the destination.

**Features**:
- Automatic region discovery and VPC enumeration
- CloudWatch Log Group creation (one per region)
- Checks for existing flow logs to avoid duplicates
- Dry run mode for previewing changes
- Configurable traffic type (ALL, ACCEPT, REJECT)
- CSV and summary file outputs
- Color-coded progress updates

**Prerequisites**:
- AWS CLI installed and configured
- **Bash version**: jq recommended for full functionality
- **PowerShell version**: PowerShell 5.0+ (no additional dependencies)
- IAM role for VPC Flow Logs (see VPC Flow Logs IAM Role Setup above)
- AWS permissions for EC2, CloudWatch Logs, and IAM

**Quick Start**:
```bash
# Bash (Linux/macOS)
./enable-vpc-flowlogs.sh

# PowerShell (Windows)
.\enable-vpc-flowlogs.ps1

# Dry run mode
DRY_RUN=true ./enable-vpc-flowlogs.sh              # Bash
.\enable-vpc-flowlogs.ps1 -DryRun                  # PowerShell

# Custom configuration (Bash)
export ROLE_ARN="arn:aws:iam::123456789012:role/MyFlowLogsRole"
export LOG_GROUP_PREFIX="/aws/vpc/flowlogs"
export TRAFFIC_TYPE=REJECT
./enable-vpc-flowlogs.sh

# Custom configuration (PowerShell)
.\enable-vpc-flowlogs.ps1 `
  -RoleArn "arn:aws:iam::123456789012:role/MyFlowLogsRole" `
  -LogGroupPrefix "/aws/vpc/flowlogs" `
  -TrafficType REJECT
```

**Configuration Options**:
- **Role ARN**: Auto-detected (VPCFlowLogsRole) or custom
- **Log Group Prefix**: Default `/aws/vpc/flowlogs`
- **Traffic Type**: `ALL` (default), `ACCEPT`, or `REJECT`
- **Dry Run**: Preview mode without making changes

**What Gets Enabled**:
- VPC Flow Logs on all VPCs without existing flow logs
- CloudWatch Log Groups in each region
- Traffic logging with specified type (ALL/ACCEPT/REJECT)
- Automatic tagging and organization

**Output Files**:
- `vpc-flowlogs-enablement.csv` - List of all VPCs with enablement status
- `vpc-flowlogs-enablement-summary.txt` - Detailed summary report

**Common Use Cases**:
```bash
# Enable flow logs on all VPCs (comprehensive monitoring)
./enable-vpc-flowlogs.sh

# Security monitoring (rejected traffic only, reduces costs)
export TRAFFIC_TYPE=REJECT
./enable-vpc-flowlogs.sh

# Preview what would be enabled
DRY_RUN=true ./enable-vpc-flowlogs.sh

# Review outputs
cat vpc-flowlogs-enablement.csv          # Spreadsheet view
cat vpc-flowlogs-enablement-summary.txt  # Summary report

# Verify flow logs are working (wait 10-15 minutes)
aws logs tail /aws/vpc/flowlogs --follow
```

**Cost Optimization**:
- Use `TRAFFIC_TYPE=REJECT` to log only rejected traffic (80-95% cost reduction)
- Set retention policies: `aws logs put-retention-policy --log-group-name /aws/vpc/flowlogs --retention-in-days 7`
- Consider S3 destination for long-term storage (cheaper than CloudWatch)
- Use custom log format to reduce data volume

**Security Benefits**:
- Comprehensive network traffic visibility
- Detect unusual traffic patterns and potential attacks
- Meet compliance requirements (PCI-DSS, HIPAA, SOC 2, NIST)
- Support incident response and forensic investigations
- Troubleshoot connectivity issues

See [VPC-FLOWLOGS-ENABLEMENT.md](VPC-FLOWLOGS-ENABLEMENT.md) for complete documentation, including advanced usage, cost analysis, verification steps, and troubleshooting.

### VPC Gateway Endpoints Setup

**Files**:
- `create-gateway-endpoints.sh` - Bash script for Linux/macOS
- `create-gateway-endpoints.ps1` - PowerShell script for Windows

Automated scripts to create VPC Gateway Endpoints (S3 and DynamoDB) in all VPCs across all AWS regions with automatic route table configuration using prefix list IDs.

**Features**:
- Creates gateway endpoints for S3 or DynamoDB services
- Automatic route table discovery and configuration
- Uses prefix list IDs for routing (not CIDR blocks)
- Checks for existing endpoints to avoid duplicates
- Dry run mode for previewing changes
- Supports both public and private VPCs
- CSV and summary file outputs
- Color-coded progress updates

**Prerequisites**:
- AWS CLI installed and configured
- **Bash version**: Bash 4.0+
- **PowerShell version**: PowerShell 5.0+ (no additional dependencies)
- AWS permissions for EC2 VPC endpoint and route management

**Quick Start**:
```bash
# Bash - Create S3 gateway endpoints (default)
./create-gateway-endpoints.sh

# Bash - Create DynamoDB gateway endpoints
export SERVICE_NAME=dynamodb
./create-gateway-endpoints.sh

# Bash - Dry run mode
DRY_RUN=true ./create-gateway-endpoints.sh

# PowerShell - Create S3 gateway endpoints (default)
.\create-gateway-endpoints.ps1

# PowerShell - Create DynamoDB gateway endpoints
.\create-gateway-endpoints.ps1 -ServiceName dynamodb

# PowerShell - Dry run mode
.\create-gateway-endpoints.ps1 -DryRun
```

**Configuration Options**:
- **Service Name**: `s3` (default) or `dynamodb`
- **Dry Run**: Preview mode without making changes

**What Gets Created**:
- VPC Gateway Endpoint for the specified service in each VPC
- Routes in all route tables using prefix list IDs as destinations
- Automatic association with existing route tables
- No additional AWS resources required

**Output Files**:
- `gateway-endpoints-setup.csv` - List of all VPCs with endpoint status
- `gateway-endpoints-setup-summary.txt` - Detailed summary report

**Cost Savings**:
Gateway Endpoints are **completely FREE** and provide significant cost savings:
- **No hourly charges** for the endpoint (unlike NAT Gateway's $0.045/hour)
- **No data processing charges** for S3/DynamoDB traffic
- **No data transfer charges** within the same region
- Example: Replacing NAT Gateway for S3 access saves ~$78/month per VPC
- 20 VPCs × $78/month = **$1,560/month = $18,720/year in savings**

**Security Benefits**:
- Private connectivity to AWS services (traffic never leaves AWS network)
- No Internet Gateway required for S3/DynamoDB access
- Reduced attack surface
- VPC endpoint policies for fine-grained access control
- CloudTrail integration for full audit trail

**Common Use Cases**:
```bash
# Cost optimization - eliminate NAT Gateway for S3
./create-gateway-endpoints.sh

# Enable both S3 and DynamoDB endpoints
./create-gateway-endpoints.sh
export SERVICE_NAME=dynamodb
./create-gateway-endpoints.sh

# Preview what would be created
DRY_RUN=true ./create-gateway-endpoints.sh

# Review outputs
cat gateway-endpoints-setup.csv          # Spreadsheet view
cat gateway-endpoints-setup-summary.txt  # Summary report

# Verify endpoints are working
aws ec2 describe-vpc-endpoints --filters "Name=vpc-endpoint-type,Values=Gateway"
```

**Route Configuration**:
Routes are created using **prefix list IDs** (not CIDR blocks):
```
Destination: pl-63a5400a (S3 prefix list for us-east-1)
Target: vpce-xxxxxx (gateway endpoint ID)
```

Prefix lists are AWS-managed and automatically updated with current IP ranges.

**Integration Examples**:
```bash
# Include in VPC provisioning
./create-vpc.sh && ./create-gateway-endpoints.sh

# Monthly audit to ensure all VPCs have endpoints
./create-gateway-endpoints.sh --dry-run

# Multi-service deployment
for service in s3 dynamodb; do
  export SERVICE_NAME=$service
  ./create-gateway-endpoints.sh
done
```

**Performance Benefits**:
- Lower latency (direct path to AWS services)
- Higher throughput (no NAT Gateway bottleneck)
- Better reliability (fewer network hops)
- Simpler routing architecture

See [GATEWAY-ENDPOINTS.md](GATEWAY-ENDPOINTS.md) for complete documentation, including cost analysis, advanced configuration, VPC endpoint policies, and troubleshooting.

---

## IAM Audit Scripts

Security audit scripts for AWS IAM to help identify potential security issues and maintain compliance with AWS best practices.

### Available Scripts

### IAM Password Policy Audit
Identifies IAM users who do not have the "IAMUserChangePassword" policy attached.
- `audit-iam-password-policy.sh` - Bash script for Linux/macOS
- `audit-iam-password-policy.ps1` - PowerShell script for Windows

### Old Access Keys Audit
Identifies IAM users with access keys older than 365 days.
- `audit-old-access-keys.sh` - Bash script for Linux/macOS
- `audit-old-access-keys.ps1` - PowerShell script for Windows

### MFA Enabled Audit
Identifies IAM users who do not have Multi-Factor Authentication (MFA) enabled.
- `audit-mfa-enabled.sh` - Bash script for Linux/macOS
- `audit-mfa-enabled.ps1` - PowerShell script for Windows

---

# IAM Password Policy Audit

## Overview

These scripts audit all IAM users in your AWS account and identify those who lack the ability to change their own password. They check for the `iam:ChangePassword` permission through:

- **Direct policy attachments**: Managed and inline policies attached directly to the user
- **Group memberships**: Policies (both managed and inline) attached to groups the user belongs to

Both scripts provide identical functionality and output format, allowing you to use the appropriate version for your operating system.

---

## Bash Script (Linux/macOS)

### File: `audit-iam-password-policy.sh`

### Prerequisites

1. **AWS CLI**: Must be installed and configured
2. **jq**: JSON processor (required for parsing policy documents)
   ```bash
   # Install on Ubuntu/Debian
   sudo apt-get install jq

   # Install on macOS
   brew install jq

   # Install on Amazon Linux/RHEL/CentOS
   sudo yum install jq
   ```

3. **AWS Credentials**: Must be configured with appropriate permissions (see Required Permissions below)

### Usage

```bash
chmod +x audit-iam-password-policy.sh
./audit-iam-password-policy.sh
```

---

## PowerShell Script (Windows)

### File: `audit-iam-password-policy.ps1`

### Prerequisites

1. **PowerShell 5.0 or later**: Included with Windows 10/11 and Windows Server 2016+
   - Check version: `$PSVersionTable.PSVersion`

2. **AWS CLI**: Must be installed and configured
   - Download from: https://aws.amazon.com/cli/
   - Install using MSI installer or via command line

3. **AWS Credentials**: Must be configured with appropriate permissions (see Required Permissions below)

### Usage

```powershell
# Run from PowerShell console
.\audit-iam-password-policy.ps1

# If you encounter execution policy errors, you may need to allow script execution:
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

## Required AWS Permissions

Both scripts require the following IAM permissions:

- `iam:ListUsers`
- `iam:ListAttachedUserPolicies`
- `iam:ListUserPolicies`
- `iam:GetUserPolicy`
- `iam:ListGroupsForUser`
- `iam:ListAttachedGroupPolicies`
- `iam:ListGroupPolicies`
- `iam:GetGroupPolicy`
- `iam:GetPolicy`
- `iam:GetPolicyVersion`

---

## Output

Both scripts provide:

1. **Console output**: Color-coded results showing which users have/don't have the permission
   - ✓ (Green) - User has change password permission
   - ✗ (Red) - User lacks change password permission

2. **Detailed report** (`iam_password_policy_audit_report.txt`): Comprehensive audit trail showing:
   - Each user checked
   - How they have (or don't have) the permission
   - Source of permissions (direct policy, group, etc.)

3. **Users list** (`users_without_change_password_policy.txt`): Simple list of usernames that lack the permission

## Example Output

```
==========================================
IAM Password Policy Audit
==========================================

Fetching IAM users...
Found 5 IAM users

✓ admin-user - Has change password permission
✗ service-account - Missing change password permission
✓ developer1 - Has change password permission
✗ readonly-user - Missing change password permission
✓ developer2 - Has change password permission

==========================================
Summary
==========================================
Total users: 5
Users with change password permission: 3
Users without change password permission: 2

Users without IAMUserChangePassword policy:
service-account
readonly-user

Detailed report saved to: iam_password_policy_audit_report.txt
Users without policy saved to: users_without_change_password_policy.txt
```

---

# Old Access Keys Audit

## Overview

These scripts identify IAM users with access keys that are older than 365 days (configurable). Regular rotation of access keys is a critical security best practice to reduce the risk of compromised credentials.

**Key Features:**
- Identifies access keys older than a specified age (default: 365 days)
- Shows age in days for each access key
- Provides both detailed report and CSV export
- Color-coded console output for quick review

---

## Bash Script (Linux/macOS)

### File: `audit-old-access-keys.sh`

### Prerequisites

1. **AWS CLI**: Must be installed and configured
2. **AWS Credentials**: Must be configured with appropriate permissions (see Required Permissions below)

### Usage

```bash
chmod +x audit-old-access-keys.sh
./audit-old-access-keys.sh
```

---

## PowerShell Script (Windows)

### File: `audit-old-access-keys.ps1`

### Prerequisites

1. **PowerShell 5.0 or later**: Included with Windows 10/11 and Windows Server 2016+
2. **AWS CLI**: Must be installed and configured
3. **AWS Credentials**: Must be configured with appropriate permissions (see Required Permissions below)

### Usage

```powershell
# Run with default 365 days threshold
.\audit-old-access-keys.ps1

# Run with custom threshold (e.g., 90 days)
.\audit-old-access-keys.ps1 -MaxAgeDays 90

# If you encounter execution policy errors:
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

## Required AWS Permissions

Both scripts require the following IAM permissions:

- `iam:ListUsers`
- `iam:ListAccessKeys`

---

## Output

Both scripts provide:

1. **Console output**: Color-coded results showing access key status
   - ✓ (Green) - All keys within acceptable age
   - ✗ (Red) - Has one or more keys older than threshold
   - ○ (Blue) - No access keys

2. **Detailed report** (`old_access_keys_report.txt`): Comprehensive audit showing:
   - Each user and their access keys
   - Age in days for each key
   - Status (Active/Inactive)
   - Creation date

3. **CSV export** (`old_access_keys.csv`): Machine-readable format with columns:
   - UserName
   - AccessKeyId
   - Status
   - Age (Days)
   - Created Date

## Example Output

```
==========================================
IAM Access Keys Age Audit
==========================================
Checking for access keys older than 365 days

Fetching IAM users...
Found 5 IAM users

✓ developer1 - All access keys are within acceptable age
✗ service-account - Has access key(s) older than 365 days
○ admin-user - No access keys
✓ developer2 - All access keys are within acceptable age
✗ old-user - Has access key(s) older than 365 days

==========================================
Summary
==========================================
Total users checked: 5
Total access keys found: 6

Access keys within 365 days: 2
Access keys older than 365 days: 4
Users with old access keys: 2

WARNING: Found 4 access key(s) older than 365 days
These keys should be rotated as part of security best practices

Detailed report saved to: old_access_keys_report.txt
CSV export saved to: old_access_keys.csv

Recommendation: Rotate access keys at least every 90 days
To rotate: Create new key, update applications, then delete old key
```

---

# MFA Enabled Audit

## Overview

These scripts identify IAM users who do not have Multi-Factor Authentication (MFA) enabled. MFA is a critical security best practice that adds an extra layer of protection beyond just passwords.

**Key Features:**
- Identifies users without any MFA devices configured
- Shows count of MFA devices for users who have them
- Lists specific MFA device ARNs in detailed report
- Provides both detailed report and CSV export
- Color-coded console output for quick review

---

## Bash Script (Linux/macOS)

### File: `audit-mfa-enabled.sh`

### Prerequisites

1. **AWS CLI**: Must be installed and configured
2. **AWS Credentials**: Must be configured with appropriate permissions (see Required Permissions below)

### Usage

```bash
chmod +x audit-mfa-enabled.sh
./audit-mfa-enabled.sh
```

---

## PowerShell Script (Windows)

### File: `audit-mfa-enabled.ps1`

### Prerequisites

1. **PowerShell 5.0 or later**: Included with Windows 10/11 and Windows Server 2016+
2. **AWS CLI**: Must be installed and configured
3. **AWS Credentials**: Must be configured with appropriate permissions (see Required Permissions below)

### Usage

```powershell
# Run the MFA audit
.\audit-mfa-enabled.ps1

# If you encounter execution policy errors:
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

## Required AWS Permissions

Both scripts require the following IAM permissions:

- `iam:ListUsers`
- `iam:ListMFADevices`

---

## Output

Both scripts provide:

1. **Console output**: Color-coded results showing MFA status
   - ✓ (Green) - MFA enabled
   - ✗ (Red) - MFA not enabled

2. **Detailed report** (`users_without_mfa_report.txt`): Comprehensive audit showing:
   - Each user and their MFA status
   - Number of MFA devices (if any)
   - Specific device ARNs

3. **CSV export** (`users_without_mfa.csv`): Machine-readable format with columns:
   - UserName
   - MFA Enabled (Yes/No)
   - MFA Device Count
   - Device ARNs

## Example Output

```
==========================================
IAM MFA Audit
==========================================
Identifying users without MFA enabled

Fetching IAM users...
Found 6 IAM users

✓ admin-user - MFA enabled (1 device(s))
✗ service-account - MFA not enabled
✓ developer1 - MFA enabled (2 device(s))
✗ readonly-user - MFA not enabled
✓ developer2 - MFA enabled (1 device(s))
✗ temp-user - MFA not enabled

==========================================
Summary
==========================================
Total users checked: 6

Users with MFA enabled: 3
Users without MFA enabled: 3

WARNING: Found 3 user(s) without MFA enabled
These users should enable MFA to enhance account security

Users without MFA:
  ✗ service-account
  ✗ readonly-user
  ✗ temp-user

Detailed report saved to: users_without_mfa_report.txt
CSV export saved to: users_without_mfa.csv

Recommendation: Enable MFA for all users, especially those with console access
MFA adds an extra layer of security: Even if passwords are compromised, accounts remain protected
```

---

## Security Best Practices

### Password Change Policy

According to AWS best practices, IAM users should be able to change their own passwords. This allows for:

- **User autonomy**: Users can update expired or compromised passwords
- **Security compliance**: Meets common security framework requirements
- **Reduced admin overhead**: Users don't need to request password changes from administrators

### Access Key Rotation

AWS recommends rotating access keys regularly to reduce security risks:

- **Recommended rotation**: Every 90 days
- **Maximum age**: 365 days (for compliance purposes)
- **Risk mitigation**: Limits the window of exposure if keys are compromised
- **Compliance requirement**: Many security frameworks (CIS, PCI-DSS, SOC 2) mandate regular key rotation

### Multi-Factor Authentication (MFA)

MFA is one of the most effective security controls for protecting AWS accounts:

- **Critical protection**: Even if passwords are compromised, MFA prevents unauthorized access
- **Required for privileged users**: Essential for all users with administrative or sensitive permissions
- **Compliance mandate**: Required by most security frameworks (CIS AWS Foundations, PCI-DSS, SOC 2)
- **Types of MFA devices**:
  - Virtual MFA (Google Authenticator, Authy, Microsoft Authenticator)
  - Hardware MFA (YubiKey, Gemalto tokens)
  - SMS MFA (not recommended for root or privileged accounts)
- **Best practice**: Enable MFA for 100% of human users, especially those with console access

---

## Remediation

### Grant Password Change Permission

To grant users the ability to change their password, attach the AWS managed policy:

**Using AWS CLI (works in both Bash and PowerShell):**

```bash
# Attach to a specific user
aws iam attach-user-policy \
  --user-name USERNAME \
  --policy-arn arn:aws:iam::aws:policy/IAMUserChangePassword

# Attach to a group (recommended)
aws iam attach-group-policy \
  --group-name GROUPNAME \
  --policy-arn arn:aws:iam::aws:policy/IAMUserChangePassword
```

The `IAMUserChangePassword` policy allows users to change only their own password and manage their own MFA devices.

### Rotate Old Access Keys

To rotate access keys safely:

**Step 1: Create a new access key**
```bash
aws iam create-access-key --user-name USERNAME
```

**Step 2: Update all applications and services** to use the new access key

**Step 3: Test thoroughly** to ensure the new key works in all environments

**Step 4: Deactivate the old key** (allows for quick rollback if needed)
```bash
aws iam update-access-key --user-name USERNAME --access-key-id OLD_KEY_ID --status Inactive
```

**Step 5: Monitor for a few days**, then delete the old key
```bash
aws iam delete-access-key --user-name USERNAME --access-key-id OLD_KEY_ID
```

**Tip:** Never have more than one active access key per user during normal operations.

### Enable MFA for Users

There are two main ways to enable MFA: through the AWS Console (user self-service) or via AWS CLI (administrator).

#### Method 1: AWS Console (User Self-Service - Recommended)

Users can enable MFA for themselves through the AWS Console:

1. Sign in to the AWS Console
2. Click on your username in the top-right → Security credentials
3. In the "Multi-factor authentication (MFA)" section, click "Assign MFA device"
4. Choose MFA device type:
   - **Virtual MFA device** (Google Authenticator, Authy, etc.) - Most common
   - **Hardware TOTP token** (Physical device like YubiKey)
   - **FIDO security key** (USB security key)
5. Follow the on-screen instructions to complete setup

#### Method 2: AWS CLI (Virtual MFA - Administrator)

Administrators can enable virtual MFA for users via CLI:

**Step 1: Create a virtual MFA device**
```bash
aws iam create-virtual-mfa-device \
  --virtual-mfa-device-name USERNAME-mfa \
  --outfile /tmp/QRCode.png \
  --bootstrap-method QRCodePNG
```

**Step 2: User scans QR code** from `/tmp/QRCode.png` with their authenticator app

**Step 3: Enable the MFA device** (requires two consecutive authentication codes)
```bash
aws iam enable-mfa-device \
  --user-name USERNAME \
  --serial-number arn:aws:iam::ACCOUNT-ID:mfa/USERNAME-mfa \
  --authentication-code1 123456 \
  --authentication-code2 789012
```

**Note:** Replace `ACCOUNT-ID` with your AWS account ID, and use actual codes from the authenticator app.

#### Require MFA for Privileged Actions

Create a policy that requires MFA for sensitive operations:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "DenyAllExceptListedIfNoMFA",
      "Effect": "Deny",
      "NotAction": [
        "iam:CreateVirtualMFADevice",
        "iam:EnableMFADevice",
        "iam:GetUser",
        "iam:ListMFADevices",
        "iam:ListVirtualMFADevices",
        "iam:ResyncMFADevice",
        "sts:GetSessionToken"
      ],
      "Resource": "*",
      "Condition": {
        "BoolIfExists": {
          "aws:MultiFactorAuthPresent": "false"
        }
      }
    }
  ]
}
```

Apply this policy to groups or users to enforce MFA for all operations except MFA setup.

---

## Troubleshooting

### Common Issues (Both Scripts)

**Error: AWS CLI is not installed**
- Install AWS CLI following the [official documentation](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)

**Error: AWS credentials not configured or invalid**
- Run `aws configure` to set up your credentials
- Ensure your IAM user/role has the required permissions listed above

**Script runs but shows no users**
- Verify your AWS credentials have the `iam:ListUsers` permission
- Check that you're querying the correct AWS account with `aws sts get-caller-identity`

### Bash-Specific Issues

**Error: jq command not found**
- Install jq using the instructions in the Prerequisites section

**Permission denied when running script**
- Make the script executable: `chmod +x audit-iam-password-policy.sh`

### PowerShell-Specific Issues

**Error: Cannot be loaded because running scripts is disabled**
- You need to allow script execution: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser`
- For more information, see [About Execution Policies](https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies)

**ConvertFrom-Json errors**
- Ensure you're using PowerShell 5.0 or later: `$PSVersionTable.PSVersion`
- Some AWS CLI output may need to be properly formatted; the script handles this automatically

## License

This project is provided as-is for AWS security auditing purposes.
