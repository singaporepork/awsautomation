# VPC Gateway Endpoints Setup Scripts

Scripts to automatically create VPC Gateway Endpoints for S3 and DynamoDB across all VPCs in all AWS regions with proper route table configuration using prefix list IDs.

**Available Versions:**
- `create-gateway-endpoints.sh` - Bash script for Linux/macOS
- `create-gateway-endpoints.ps1` - PowerShell script for Windows

Both scripts provide identical functionality for setting up gateway endpoints with automatic route table configuration.

## Overview

These scripts automate the deployment of VPC Gateway Endpoints across your entire AWS infrastructure. Gateway Endpoints allow private connections to AWS services (S3 and DynamoDB) without requiring an Internet Gateway, NAT device, VPN connection, or AWS Direct Connect.

### What Are Gateway Endpoints?

Gateway Endpoints are a VPC endpoint type that provides:
- **Private connectivity** to S3 and DynamoDB from your VPC
- **No data transfer charges** for traffic within the same region
- **No hourly charges** (completely free)
- **Improved security** by keeping traffic within the AWS network
- **Better performance** with lower latency

### What Gets Created

For each VPC in each region:

1. **VPC Gateway Endpoint**: Endpoint resource for the specified service (S3 or DynamoDB)
2. **Route Table Updates**: Routes added to all route tables in the VPC using prefix list IDs
3. **Automatic Association**: Endpoint is associated with all existing route tables

## Prerequisites

### Bash Script (Linux/macOS)

- AWS CLI installed and configured
- Bash 4.0 or higher
- AWS credentials with required permissions (see below)

### PowerShell Script (Windows)

- PowerShell 5.0 or later
- AWS CLI installed and configured
- AWS credentials with required permissions (see below)

### Required AWS Permissions

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:DescribeRegions",
        "ec2:DescribeVpcs",
        "ec2:DescribeRouteTables",
        "ec2:DescribeVpcEndpoints",
        "ec2:DescribePrefixLists",
        "ec2:CreateVpcEndpoint",
        "ec2:CreateRoute",
        "ec2:ModifyVpcEndpoint",
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
```

## Usage

### Basic Usage

**Bash - Create S3 Gateway Endpoints (default):**
```bash
./create-gateway-endpoints.sh
```

**PowerShell - Create S3 Gateway Endpoints (default):**
```powershell
.\create-gateway-endpoints.ps1
```

### Create DynamoDB Gateway Endpoints

**Bash:**
```bash
export SERVICE_NAME=dynamodb
./create-gateway-endpoints.sh
```

**PowerShell:**
```powershell
.\create-gateway-endpoints.ps1 -ServiceName dynamodb
```

### Dry Run Mode

Preview what would be created without making changes:

**Bash:**
```bash
DRY_RUN=true ./create-gateway-endpoints.sh
```

**PowerShell:**
```powershell
.\create-gateway-endpoints.ps1 -DryRun
```

### Create Both S3 and DynamoDB Endpoints

**Bash:**
```bash
# Create S3 endpoints
./create-gateway-endpoints.sh

# Create DynamoDB endpoints
export SERVICE_NAME=dynamodb
./create-gateway-endpoints.sh
```

**PowerShell:**
```powershell
# Create S3 endpoints
.\create-gateway-endpoints.ps1

# Create DynamoDB endpoints
.\create-gateway-endpoints.ps1 -ServiceName dynamodb
```

## Configuration Options

### Bash Script

Configure via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `SERVICE_NAME` | `s3` | Service name: `s3` or `dynamodb` |
| `DRY_RUN` | `false` | Preview mode without making changes |

### PowerShell Script

Configure via parameters:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-ServiceName` | `s3` | Service name: `s3` or `dynamodb` |
| `-DryRun` | Off | Switch to enable preview mode |

## Output

### Console Output

```
==========================================
VPC Gateway Endpoints Setup
==========================================

AWS Account ID: 123456789012
Service: s3

Fetching AWS regions...
Found 16 regions to check

Checking region: us-east-1
  Found 3 VPC(s)
  Prefix List ID: pl-63a5400a

  VPC: vpc-abc123 (Production)
  Creating gateway endpoint for s3...
  ✓ Endpoint created: vpce-0a1b2c3d4e5f6g7h8

  VPC: vpc-def456 (Development)
  Gateway endpoint already exists: vpce-1a2b3c4d5e6f7g8h9
  Checking routes in 2 route table(s)...
    ✓ Route exists in rtb-111111
    Adding missing route to rtb-222222...
    ✓ Route added to rtb-222222

==========================================
SUMMARY
==========================================
Total regions checked: 16
Total VPCs found: 25
Service: s3

Endpoints created: 18
Endpoints already existed: 7
Endpoints failed: 0

Routes added: 19
Routes already existed: 31
Routes failed: 0

Output files:
  Summary: gateway-endpoints-setup-summary.txt
  CSV:     gateway-endpoints-setup.csv

✓ Gateway endpoints setup complete!
==========================================
```

### CSV Output

File: `gateway-endpoints-setup.csv`

```csv
Region,VPC ID,VPC Name,Endpoint ID,Endpoint Status,Route Tables,Routes Added,Message
us-east-1,vpc-abc123,Production,vpce-0a1b2c3d4e5f6g7h8,Created,2,2,Successfully created
us-east-1,vpc-def456,Development,vpce-1a2b3c4d5e6f7g8h9,Already Exists,2,1,Endpoint already exists
us-west-2,vpc-ghi789,Staging,vpce-2a3b4c5d6e7f8g9h0,Created,3,3,Successfully created
```

### Summary File

File: `gateway-endpoints-setup-summary.txt`

```
VPC Gateway Endpoints Setup Summary
Generated: 2024-01-15 10:30:00
Account: 123456789012
Service: s3
Dry Run: false
========================================

  [CREATED] us-east-1 - vpc-abc123 (Production) - vpce-0a1b2c3d4e5f6g7h8 (2 route tables)
  [SKIP] us-east-1 - vpc-def456 (Development) - Already exists: vpce-1a2b3c4d5e6f7g8h9
  [CREATED] us-west-2 - vpc-ghi789 (Staging) - vpce-2a3b4c5d6e7f8g9h0 (3 route tables)

SUMMARY
========================================
Total regions checked: 16
Total VPCs found: 25
Service: s3

Endpoints created: 18
Endpoints already existed: 7
Endpoints failed: 0

Routes added: 19
Routes already existed: 31
Routes failed: 0
```

## Benefits

### Cost Savings

Gateway Endpoints provide significant cost savings:

**Without Gateway Endpoints:**
- Data transfer charges for S3/DynamoDB access via NAT Gateway
- NAT Gateway hourly charges ($0.045/hour = ~$32.40/month)
- NAT Gateway data processing charges ($0.045/GB)

**With Gateway Endpoints:**
- **No charges** for gateway endpoints (completely free)
- **No data transfer charges** within the same region
- **No NAT Gateway needed** for S3/DynamoDB traffic

**Example savings:**
- 1 TB/month S3 traffic: ~$45/month savings (data processing)
- Removing 1 NAT Gateway: ~$32/month savings (hourly charge)
- **Total: ~$77/month = $924/year per VPC**

### Security Benefits

1. **Private connectivity**: Traffic never leaves the AWS network
2. **No Internet Gateway required**: Reduces attack surface
3. **VPC-level access control**: Use VPC endpoint policies
4. **CloudTrail integration**: Full audit trail of API calls
5. **Security group support**: Control access at instance level

### Performance Benefits

1. **Lower latency**: Direct path to AWS services
2. **Higher throughput**: No NAT Gateway bottleneck
3. **Better reliability**: Fewer network hops
4. **Reduced complexity**: Simpler routing architecture

## Use Cases

### Cost Optimization

Enable S3 gateway endpoints to eliminate NAT Gateway costs:

```bash
# Enable S3 endpoints across all VPCs
./create-gateway-endpoints.sh

# Review potential savings in summary report
cat gateway-endpoints-setup-summary.txt
```

### Security Enhancement

Enable private connectivity to AWS services:

```bash
# Create S3 endpoints
./create-gateway-endpoints.sh

# Create DynamoDB endpoints
export SERVICE_NAME=dynamodb
./create-gateway-endpoints.sh
```

Then configure VPC endpoint policies to restrict access:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": "arn:aws:s3:::my-secure-bucket/*"
    }
  ]
}
```

### Compliance Requirements

Many compliance frameworks require private connectivity:

```bash
# PCI-DSS, HIPAA, SOC 2 compliance
./create-gateway-endpoints.sh
export SERVICE_NAME=dynamodb
./create-gateway-endpoints.sh
```

### Multi-Region Deployment

Deploy across all regions for consistent architecture:

```bash
# Bash - deploys to all regions automatically
./create-gateway-endpoints.sh

# PowerShell - deploys to all regions automatically
.\create-gateway-endpoints.ps1
```

### CI/CD Integration

Integrate into infrastructure deployment:

```bash
#!/bin/bash
# deploy-vpc-infrastructure.sh

# Create VPC
aws ec2 create-vpc --cidr-block 10.0.0.0/16

# Create subnets, route tables, etc.
# ...

# Add gateway endpoints automatically
./create-gateway-endpoints.sh
```

## Understanding Prefix Lists

### What Are Prefix Lists?

Prefix lists are AWS-managed lists of IP address ranges for AWS services. Instead of maintaining CIDR blocks manually, you reference the prefix list ID in routes.

### Why Use Prefix Lists?

1. **Automatic updates**: AWS manages the IP ranges
2. **No manual maintenance**: Ranges update automatically
3. **Correct syntax**: Required for gateway endpoints
4. **Service-specific**: Each service has its own prefix list

### How Routes Are Created

The scripts automatically:

1. **Get the prefix list ID** for the service in each region
   - Example: `pl-63a5400a` for S3 in us-east-1
2. **Create routes** in each route table:
   ```
   Destination: pl-63a5400a (prefix list ID)
   Target: vpce-xxxxxx (gateway endpoint ID)
   ```
3. **Verify routes** are properly configured

### Example Route Table

After running the script, your route table will look like:

```
Destination           Target                Type
10.0.0.0/16          local                 Local
0.0.0.0/0            igw-xxxxxx            Internet Gateway
pl-63a5400a          vpce-0a1b2c3d         Gateway Endpoint (S3)
```

## Advanced Configuration

### VPC Endpoint Policies

After creating endpoints, you can add policies for fine-grained access control:

```bash
# Get endpoint ID
ENDPOINT_ID=$(aws ec2 describe-vpc-endpoints \
    --filters "Name=vpc-id,Values=vpc-abc123" "Name=service-name,Values=com.amazonaws.us-east-1.s3" \
    --query 'VpcEndpoints[0].VpcEndpointId' \
    --output text)

# Create policy document
cat > endpoint-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": [
        "arn:aws:s3:::my-allowed-bucket/*",
        "arn:aws:s3:::my-allowed-bucket"
      ]
    }
  ]
}
EOF

# Apply policy
aws ec2 modify-vpc-endpoint \
    --vpc-endpoint-id $ENDPOINT_ID \
    --policy-document file://endpoint-policy.json
```

### Selective Route Table Association

Modify the endpoint to associate with specific route tables:

```bash
# Modify endpoint associations
aws ec2 modify-vpc-endpoint \
    --vpc-endpoint-id vpce-xxxxxx \
    --add-route-table-ids rtb-111111 rtb-222222 \
    --remove-route-table-ids rtb-333333
```

### DNS Resolution

For S3, enable DNS resolution to use endpoint by default:

```bash
aws ec2 modify-vpc-endpoint \
    --vpc-endpoint-id vpce-xxxxxx \
    --private-dns-enabled
```

## Verification

### Verify Endpoints Are Created

```bash
# List all gateway endpoints in a VPC
aws ec2 describe-vpc-endpoints \
    --filters "Name=vpc-id,Values=vpc-abc123" "Name=vpc-endpoint-type,Values=Gateway" \
    --query 'VpcEndpoints[].{ID:VpcEndpointId,Service:ServiceName,State:State}' \
    --output table
```

Expected output:
```
---------------------------------------------------
|              DescribeVpcEndpoints              |
+----------------+------------------+-------------+
|       ID       |     Service      |    State    |
+----------------+------------------+-------------+
| vpce-0a1b2c3d | com.amazonaws... | available   |
+----------------+------------------+-------------+
```

### Verify Routes Are Added

```bash
# Check route table for prefix list routes
aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=vpc-abc123" \
    --query 'RouteTables[].Routes[?DestinationPrefixListId!=`null`]' \
    --output table
```

### Test Connectivity

From an EC2 instance in the VPC:

```bash
# Test S3 access (should use private endpoint)
aws s3 ls

# Check routing (should show private IP)
nslookup s3.amazonaws.com

# Trace route to S3 (should not go through NAT/IGW)
traceroute s3.amazonaws.com
```

### Monitor Usage

Use VPC Flow Logs to verify traffic is using the endpoint:

```bash
# Enable VPC Flow Logs (see enable-vpc-flowlogs.sh)
./enable-vpc-flowlogs.sh

# Query for S3 traffic
aws logs filter-log-events \
    --log-group-name /aws/vpc/flowlogs \
    --filter-pattern "[version, account, eni, source, destination, srcport, dstport, protocol, packets, bytes, windowstart, windowend, action=ACCEPT, flowlogstatus]" \
    --query 'events[].message' \
    --output text | grep "vpce-"
```

## Troubleshooting

### Endpoint Creation Fails

**Error**: `RouteAlreadyExists`

**Cause**: Route to prefix list already exists in route table

**Solution**: Script handles this automatically by checking existing routes first. If you see this error, existing routes are preserved.

**Error**: `InvalidParameter: VPC endpoint service not available`

**Cause**: Service not available in specific region

**Solution**: Script automatically skips regions where service is unavailable.

### Routes Not Being Added

**Issue**: Routes are created but traffic still goes through NAT

**Possible causes**:
1. Security groups blocking traffic
2. NACLs blocking traffic
3. S3 bucket policy restrictions

**Verification**:
```bash
# Check security groups allow outbound HTTPS
aws ec2 describe-security-groups \
    --group-ids sg-xxxxxx \
    --query 'SecurityGroups[].IpPermissionsEgress'

# Check NACLs
aws ec2 describe-network-acls \
    --filters "Name=vpc-id,Values=vpc-abc123"
```

### Prefix List Not Found

**Error**: `Prefix list not found`

**Cause**: Service doesn't support gateway endpoints in that region

**Solution**: Verify service availability:
```bash
# List available prefix lists
aws ec2 describe-prefix-lists \
    --query 'PrefixLists[].{Name:PrefixListName,ID:PrefixListId}' \
    --output table
```

### Permission Denied

**Error**: `UnauthorizedOperation`

**Solution**: Ensure IAM user/role has required permissions (see Prerequisites).

## Best Practices

### 1. Create Endpoints During VPC Setup

Include gateway endpoint creation in your VPC provisioning:

```bash
#!/bin/bash
# provision-vpc.sh

# Create VPC
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query 'Vpc.VpcId' --output text)

# Create route tables
# ...

# Add gateway endpoints
./create-gateway-endpoints.sh
```

### 2. Use VPC Endpoint Policies

Implement least privilege access:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::prod-data-bucket/*",
      "Condition": {
        "StringEquals": {
          "aws:PrincipalOrgID": "o-xxxxxxxxxx"
        }
      }
    }
  ]
}
```

### 3. Monitor Endpoint Usage

Track usage with CloudWatch and VPC Flow Logs:

```bash
# Enable flow logs
./enable-vpc-flowlogs.sh

# Create CloudWatch dashboard for endpoint metrics
aws cloudwatch put-dashboard \
    --dashboard-name VPCEndpoints \
    --dashboard-body file://dashboard.json
```

### 4. Document Endpoint Configuration

Maintain documentation of which services use endpoints:

```bash
# Generate endpoint inventory
aws ec2 describe-vpc-endpoints \
    --query 'VpcEndpoints[].{VPC:VpcId,Service:ServiceName,ID:VpcEndpointId}' \
    --output table > endpoint-inventory.txt
```

### 5. Regular Audits

Periodically verify endpoints are properly configured:

```bash
# Audit script (run monthly)
./create-gateway-endpoints.sh --dry-run
```

## Comparison: Gateway Endpoints vs. Interface Endpoints

| Feature | Gateway Endpoints | Interface Endpoints |
|---------|------------------|---------------------|
| **Services** | S3, DynamoDB only | Most AWS services |
| **Cost** | FREE | $0.01/hour per AZ (~$7.20/month) |
| **Implementation** | Route table entry | ENI in subnet |
| **DNS** | Uses service DNS | Private DNS names |
| **IP Addresses** | No IP addresses | Private IPs from subnet |
| **Security Groups** | No | Yes |
| **Routing** | Prefix list routes | Normal routing |
| **High Availability** | AWS managed | Multiple AZs recommended |

**When to use Gateway Endpoints:**
- Accessing S3 or DynamoDB
- Cost optimization priority
- Simple routing requirements

**When to use Interface Endpoints:**
- Other AWS services (EC2, SNS, SQS, etc.)
- Need security group controls
- Require private DNS

## Cost Analysis

### Gateway Endpoints: Completely Free

- **Hourly charges**: $0.00
- **Data processing**: $0.00
- **Data transfer (same region)**: $0.00

### Comparison with NAT Gateway

For 1 TB/month of S3 traffic:

**With NAT Gateway:**
- NAT Gateway hourly: $0.045/hour × 730 hours = $32.85
- Data processing: $0.045/GB × 1000 GB = $45.00
- **Total: $77.85/month**

**With Gateway Endpoint:**
- Gateway endpoint: $0.00
- Data transfer: $0.00
- **Total: $0.00/month**

**Savings: $77.85/month = $934.20/year per VPC**

### ROI for This Script

If you have:
- 20 VPCs across multiple regions
- Average 500 GB/month S3 traffic per VPC

**Monthly savings:**
- NAT Gateway hourly: 20 × $32.85 = $657
- Data processing: 20 × (500 GB × $0.045) = $450
- **Total: $1,107/month = $13,284/year**

**Time investment:**
- Running this script: < 10 minutes
- **ROI: Immediate and ongoing**

## References

- [AWS VPC Endpoints Documentation](https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints.html)
- [Gateway Endpoints for S3](https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints-s3.html)
- [Gateway Endpoints for DynamoDB](https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints-ddb.html)
- [VPC Endpoint Policies](https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints-access.html)
- [Prefix Lists](https://docs.aws.amazon.com/vpc/latest/userguide/managed-prefix-lists.html)

## License

This project is provided as-is for AWS automation purposes.
