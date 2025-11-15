#!/bin/bash

# Script to enable VPC Flow Logs on all VPCs in all AWS regions
# Automatically creates CloudWatch Log Groups and enables flow logs

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration - can be overridden with environment variables
ROLE_ARN="${ROLE_ARN:-}"
LOG_GROUP_PREFIX="${LOG_GROUP_PREFIX:-/aws/vpc/flowlogs}"
TRAFFIC_TYPE="${TRAFFIC_TYPE:-ALL}"  # ALL, ACCEPT, or REJECT
DRY_RUN="${DRY_RUN:-false}"

# Output files
SUMMARY_FILE="vpc-flowlogs-enablement-summary.txt"
CSV_OUTPUT="vpc-flowlogs-enablement.csv"

# Counters
TOTAL_VPCS=0
ENABLED_VPCS=0
ALREADY_ENABLED_VPCS=0
FAILED_VPCS=0
TOTAL_REGIONS=0

echo "==========================================="
echo "VPC Flow Logs Enablement"
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

# Get or validate IAM role ARN
if [ -z "$ROLE_ARN" ]; then
    echo "No IAM role ARN provided. Checking for default VPCFlowLogsRole..."

    if aws iam get-role --role-name VPCFlowLogsRole &>/dev/null; then
        ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/VPCFlowLogsRole"
        echo "Using role: $ROLE_ARN"
    else
        echo -e "${RED}Error: No IAM role found${NC}"
        echo ""
        echo "Please either:"
        echo "  1. Run create-vpc-flowlogs-role.sh to create the role"
        echo "  2. Set ROLE_ARN environment variable with your role ARN:"
        echo "     export ROLE_ARN='arn:aws:iam::$ACCOUNT_ID:role/YourRoleName'"
        exit 1
    fi
else
    echo "Using role: $ROLE_ARN"
fi

echo "Log Group Prefix: $LOG_GROUP_PREFIX"
echo "Traffic Type: $TRAFFIC_TYPE"

if [ "$DRY_RUN" == "true" ]; then
    echo -e "${YELLOW}DRY RUN MODE: No changes will be made${NC}"
fi

echo ""

# Validate traffic type
if [[ ! "$TRAFFIC_TYPE" =~ ^(ALL|ACCEPT|REJECT)$ ]]; then
    echo -e "${RED}Error: TRAFFIC_TYPE must be ALL, ACCEPT, or REJECT${NC}"
    exit 1
fi

# Initialize CSV output
echo "Region,VPC ID,VPC Name,Status,Flow Log ID,Message" > "$CSV_OUTPUT"

# Initialize summary file
{
    echo "VPC Flow Logs Enablement Summary"
    echo "Generated: $(date)"
    echo "Account: $ACCOUNT_ID"
    echo "IAM Role: $ROLE_ARN"
    echo "Traffic Type: $TRAFFIC_TYPE"
    echo "Dry Run: $DRY_RUN"
    echo "========================================"
    echo ""
} > "$SUMMARY_FILE"

# Function to get VPC name from tags
get_vpc_name() {
    local region=$1
    local vpc_id=$2

    local vpc_name=$(aws ec2 describe-vpcs \
        --region "$region" \
        --vpc-ids "$vpc_id" \
        --query 'Vpcs[0].Tags[?Key==`Name`].Value' \
        --output text 2>/dev/null || echo "")

    if [ -z "$vpc_name" ]; then
        echo "Unnamed"
    else
        echo "$vpc_name"
    fi
}

# Function to check if flow logs are already enabled
check_existing_flowlogs() {
    local region=$1
    local vpc_id=$2

    local flowlogs=$(aws ec2 describe-flow-logs \
        --region "$region" \
        --filter "Name=resource-id,Values=$vpc_id" \
        --query 'FlowLogs[?FlowLogStatus==`ACTIVE`].FlowLogId' \
        --output text 2>/dev/null || echo "")

    if [ -n "$flowlogs" ]; then
        echo "$flowlogs"
    else
        echo ""
    fi
}

# Function to create log group if it doesn't exist
create_log_group() {
    local region=$1
    local log_group=$2

    # Check if log group exists
    if aws logs describe-log-groups \
        --region "$region" \
        --log-group-name-prefix "$log_group" \
        --query "logGroups[?logGroupName=='$log_group'].logGroupName" \
        --output text 2>/dev/null | grep -q "$log_group"; then
        return 0
    fi

    # Create log group
    if [ "$DRY_RUN" == "false" ]; then
        if aws logs create-log-group \
            --region "$region" \
            --log-group-name "$log_group" 2>/dev/null; then
            return 0
        else
            return 1
        fi
    else
        return 0
    fi
}

# Function to enable flow logs for a VPC
enable_flowlogs() {
    local region=$1
    local vpc_id=$2
    local vpc_name=$3
    local log_group=$4

    echo -n "  Enabling flow logs... "

    if [ "$DRY_RUN" == "true" ]; then
        echo -e "${BLUE}(dry run - skipped)${NC}"
        echo "$region,$vpc_id,$vpc_name,Would Enable,N/A,Dry run mode" >> "$CSV_OUTPUT"
        echo "  [DRY RUN] $region - $vpc_id ($vpc_name)" >> "$SUMMARY_FILE"
        ENABLED_VPCS=$((ENABLED_VPCS + 1))
        return 0
    fi

    # Create flow logs
    local result=$(aws ec2 create-flow-logs \
        --region "$region" \
        --resource-type VPC \
        --resource-ids "$vpc_id" \
        --traffic-type "$TRAFFIC_TYPE" \
        --log-destination-type cloud-watch-logs \
        --log-group-name "$log_group" \
        --deliver-logs-permission-arn "$ROLE_ARN" \
        --output json 2>&1)

    if echo "$result" | grep -q "FlowLogIds"; then
        local flow_log_id=$(echo "$result" | grep -o '"fl-[a-z0-9]*"' | tr -d '"' | head -1)
        echo -e "${GREEN}✓ Success${NC}"
        echo "$region,$vpc_id,$vpc_name,Enabled,$flow_log_id,Successfully enabled" >> "$CSV_OUTPUT"
        echo "  [ENABLED] $region - $vpc_id ($vpc_name) - $flow_log_id" >> "$SUMMARY_FILE"
        ENABLED_VPCS=$((ENABLED_VPCS + 1))
        return 0
    else
        local error_msg=$(echo "$result" | grep -o '"message": *"[^"]*"' | cut -d'"' -f4 | head -1)
        if [ -z "$error_msg" ]; then
            error_msg="Unknown error"
        fi
        echo -e "${RED}✗ Failed${NC}"
        echo "    Error: $error_msg"
        echo "$region,$vpc_id,$vpc_name,Failed,N/A,$error_msg" >> "$CSV_OUTPUT"
        echo "  [FAILED] $region - $vpc_id ($vpc_name) - $error_msg" >> "$SUMMARY_FILE"
        FAILED_VPCS=$((FAILED_VPCS + 1))
        return 1
    fi
}

# Get all regions
echo "Fetching AWS regions..."
REGIONS=$(aws ec2 describe-regions --query 'Regions[].RegionName' --output text)
REGION_COUNT=$(echo "$REGIONS" | wc -w)
echo "Found $REGION_COUNT regions to check"
echo ""

# Process each region
for region in $REGIONS; do
    echo -e "${CYAN}Checking region: $region${NC}"
    TOTAL_REGIONS=$((TOTAL_REGIONS + 1))

    # Get all VPCs in the region
    vpcs=$(aws ec2 describe-vpcs \
        --region "$region" \
        --query 'Vpcs[].[VpcId,Tags[?Key==`Name`].Value|[0]]' \
        --output text 2>/dev/null || echo "")

    if [ -z "$vpcs" ]; then
        echo "  No VPCs found"
        echo ""
        continue
    fi

    vpc_count=$(echo "$vpcs" | wc -l)
    echo "  Found $vpc_count VPC(s)"

    # Process each VPC
    while IFS=$'\t' read -r vpc_id vpc_name; do
        [ -z "$vpc_id" ] && continue

        TOTAL_VPCS=$((TOTAL_VPCS + 1))

        if [ -z "$vpc_name" ] || [ "$vpc_name" == "None" ]; then
            vpc_name="Unnamed"
        fi

        echo -n "  VPC: $vpc_id ($vpc_name) - "

        # Check if flow logs already enabled
        existing_flowlogs=$(check_existing_flowlogs "$region" "$vpc_id")

        if [ -n "$existing_flowlogs" ]; then
            echo -e "${YELLOW}Already enabled${NC}"
            echo "    Existing flow log(s): $existing_flowlogs"
            echo "$region,$vpc_id,$vpc_name,Already Enabled,$existing_flowlogs,Flow logs already active" >> "$CSV_OUTPUT"
            echo "  [SKIP] $region - $vpc_id ($vpc_name) - Already enabled: $existing_flowlogs" >> "$SUMMARY_FILE"
            ALREADY_ENABLED_VPCS=$((ALREADY_ENABLED_VPCS + 1))
            continue
        fi

        echo ""

        # Create log group for this region
        log_group="${LOG_GROUP_PREFIX}"
        if [ "$DRY_RUN" == "false" ]; then
            echo -n "  Creating/verifying log group... "
            if create_log_group "$region" "$log_group"; then
                echo -e "${GREEN}✓${NC}"
            else
                echo -e "${RED}✗ Failed${NC}"
                echo "$region,$vpc_id,$vpc_name,Failed,N/A,Failed to create log group" >> "$CSV_OUTPUT"
                FAILED_VPCS=$((FAILED_VPCS + 1))
                continue
            fi
        fi

        # Enable flow logs
        enable_flowlogs "$region" "$vpc_id" "$vpc_name" "$log_group"

    done <<< "$vpcs"

    echo ""
done

# Generate summary
{
    echo ""
    echo "SUMMARY"
    echo "========================================"
    echo "Total regions checked: $TOTAL_REGIONS"
    echo "Total VPCs found: $TOTAL_VPCS"
    echo "VPCs with flow logs enabled: $ENABLED_VPCS"
    echo "VPCs already had flow logs: $ALREADY_ENABLED_VPCS"
    echo "VPCs failed: $FAILED_VPCS"
    echo ""
} >> "$SUMMARY_FILE"

# Display summary
echo "==========================================="
echo "SUMMARY"
echo "==========================================="
echo "Total regions checked: $TOTAL_REGIONS"
echo "Total VPCs found: $TOTAL_VPCS"
echo ""
echo -e "${GREEN}VPCs with flow logs enabled: $ENABLED_VPCS${NC}"
echo -e "${YELLOW}VPCs already had flow logs: $ALREADY_ENABLED_VPCS${NC}"
if [ $FAILED_VPCS -gt 0 ]; then
    echo -e "${RED}VPCs failed: $FAILED_VPCS${NC}"
fi
echo ""
echo "Output files:"
echo "  Summary: $SUMMARY_FILE"
echo "  CSV:     $CSV_OUTPUT"
echo ""

if [ "$DRY_RUN" == "true" ]; then
    echo -e "${BLUE}This was a dry run. No changes were made.${NC}"
    echo "Run without DRY_RUN=true to actually enable flow logs."
    echo ""
fi

if [ $ENABLED_VPCS -gt 0 ]; then
    echo -e "${GREEN}✓ VPC Flow Logs enablement complete!${NC}"
elif [ $ALREADY_ENABLED_VPCS -eq $TOTAL_VPCS ] && [ $TOTAL_VPCS -gt 0 ]; then
    echo -e "${YELLOW}All VPCs already have flow logs enabled.${NC}"
elif [ $FAILED_VPCS -gt 0 ]; then
    echo -e "${RED}Some VPCs failed to enable flow logs. Check the summary for details.${NC}"
    exit 1
fi

echo "==========================================="
