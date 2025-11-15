#!/bin/bash

# Script to create an IAM role for VPC Flow Logs to CloudWatch Logs
# Based on AWS documentation for VPC Flow Logs
# https://docs.aws.amazon.com/vpc/latest/tgw/flow-logs-cwl.html

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ROLE_NAME="${ROLE_NAME:-VPCFlowLogsRole}"
POLICY_NAME="${POLICY_NAME:-VPCFlowLogsPolicy}"
DESCRIPTION="IAM role for VPC Flow Logs to publish to CloudWatch Logs"

echo "==========================================="
echo "VPC Flow Logs IAM Role Setup"
echo "==========================================="
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}Error: AWS credentials not configured or invalid${NC}"
    exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "AWS Account ID: $ACCOUNT_ID"
echo "IAM Role Name: $ROLE_NAME"
echo ""

# Create trust policy document for VPC Flow Logs
echo "Creating trust policy document..."
TRUST_POLICY=$(cat <<EOF
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
EOF
)

# Create permissions policy document
echo "Creating permissions policy document..."
PERMISSIONS_POLICY=$(cat <<EOF
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
EOF
)

# Check if role already exists
echo "Checking if IAM role already exists..."
if aws iam get-role --role-name "$ROLE_NAME" &>/dev/null; then
    echo -e "${YELLOW}Warning: IAM role '$ROLE_NAME' already exists${NC}"
    read -p "Do you want to update the existing role? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Exiting without changes"
        exit 0
    fi

    echo "Updating existing role..."

    # Update trust policy
    echo "Updating trust policy..."
    aws iam update-assume-role-policy \
        --role-name "$ROLE_NAME" \
        --policy-document "$TRUST_POLICY"
    echo -e "${GREEN}✓${NC} Trust policy updated"

else
    # Create new IAM role
    echo "Creating IAM role: $ROLE_NAME..."
    aws iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document "$TRUST_POLICY" \
        --description "$DESCRIPTION" \
        --tags Key=Purpose,Value=VPCFlowLogs Key=ManagedBy,Value=Script
    echo -e "${GREEN}✓${NC} IAM role created"
fi

# Check if inline policy already exists
echo "Checking for existing inline policy..."
if aws iam get-role-policy --role-name "$ROLE_NAME" --policy-name "$POLICY_NAME" &>/dev/null; then
    echo "Updating existing inline policy..."
else
    echo "Creating inline policy..."
fi

# Put/Update inline policy
aws iam put-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-name "$POLICY_NAME" \
    --policy-document "$PERMISSIONS_POLICY"
echo -e "${GREEN}✓${NC} Permissions policy attached"

# Get role ARN
ROLE_ARN=$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.Arn' --output text)

echo ""
echo "==========================================="
echo "Setup Complete!"
echo "==========================================="
echo ""
echo "Role Details:"
echo "  Role Name: $ROLE_NAME"
echo "  Role ARN:  $ROLE_ARN"
echo ""
echo -e "${BLUE}Next Steps:${NC}"
echo "1. Create a CloudWatch Logs log group (if not already created):"
echo "   aws logs create-log-group --log-group-name /aws/vpc/flowlogs"
echo ""
echo "2. Enable VPC Flow Logs using this role:"
echo "   aws ec2 create-flow-logs \\"
echo "     --resource-type VPC \\"
echo "     --resource-ids vpc-xxxxxxxx \\"
echo "     --traffic-type ALL \\"
echo "     --log-destination-type cloud-watch-logs \\"
echo "     --log-group-name /aws/vpc/flowlogs \\"
echo "     --deliver-logs-permission-arn $ROLE_ARN"
echo ""
echo "   Or for a subnet:"
echo "   aws ec2 create-flow-logs \\"
echo "     --resource-type Subnet \\"
echo "     --resource-ids subnet-xxxxxxxx \\"
echo "     --traffic-type ALL \\"
echo "     --log-destination-type cloud-watch-logs \\"
echo "     --log-group-name /aws/vpc/flowlogs \\"
echo "     --deliver-logs-permission-arn $ROLE_ARN"
echo ""
echo "   Or for a network interface:"
echo "   aws ec2 create-flow-logs \\"
echo "     --resource-type NetworkInterface \\"
echo "     --resource-ids eni-xxxxxxxx \\"
echo "     --traffic-type ALL \\"
echo "     --log-destination-type cloud-watch-logs \\"
echo "     --log-group-name /aws/vpc/flowlogs \\"
echo "     --deliver-logs-permission-arn $ROLE_ARN"
echo ""
echo "==========================================="
echo ""
echo -e "${GREEN}IAM role for VPC Flow Logs is ready to use!${NC}"
