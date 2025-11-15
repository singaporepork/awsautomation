#!/bin/bash

# Script to create VPC Gateway Endpoints in all VPCs across all AWS regions
# Supports S3 and DynamoDB Gateway Endpoints with automatic route table configuration
# Uses prefix list IDs for routing instead of CIDR blocks

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
SERVICE_NAME="${SERVICE_NAME:-s3}"  # s3 or dynamodb
DRY_RUN="${DRY_RUN:-false}"
OUTPUT_CSV="gateway-endpoints-setup.csv"
SUMMARY_FILE="gateway-endpoints-setup-summary.txt"

# Counters
TOTAL_VPCS=0
ENDPOINTS_CREATED=0
ENDPOINTS_EXISTING=0
ENDPOINTS_FAILED=0
ROUTES_ADDED=0
ROUTES_EXISTING=0
ROUTES_FAILED=0
TOTAL_REGIONS=0

echo -e "${CYAN}==========================================${NC}"
echo -e "${CYAN}VPC Gateway Endpoints Setup${NC}"
echo -e "${CYAN}==========================================${NC}"
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}"
    echo "Please install AWS CLI from: https://aws.amazon.com/cli/"
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}Error: AWS credentials not configured or invalid${NC}"
    echo "Please run 'aws configure' to set up your credentials"
    exit 1
fi

# Validate service name
if [[ ! "$SERVICE_NAME" =~ ^(s3|dynamodb)$ ]]; then
    echo -e "${RED}Error: Invalid service name. Must be 's3' or 'dynamodb'${NC}"
    echo "Set SERVICE_NAME environment variable: export SERVICE_NAME=s3"
    exit 1
fi

# Get Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "AWS Account ID: $ACCOUNT_ID"
echo "Service: $SERVICE_NAME"

if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}DRY RUN MODE: No changes will be made${NC}"
fi

echo ""

# Initialize CSV output
echo "Region,VPC ID,VPC Name,Endpoint ID,Endpoint Status,Route Tables,Routes Added,Message" > "$OUTPUT_CSV"

# Initialize summary file
cat > "$SUMMARY_FILE" <<EOF
VPC Gateway Endpoints Setup Summary
Generated: $(date)
Account: $ACCOUNT_ID
Service: $SERVICE_NAME
Dry Run: $DRY_RUN
========================================

EOF

# Function to get VPC name from tags
get_vpc_name() {
    local region=$1
    local vpc_id=$2

    local vpc_name=$(aws ec2 describe-vpcs \
        --region "$region" \
        --vpc-ids "$vpc_id" \
        --query 'Vpcs[0].Tags[?Key==`Name`].Value' \
        --output text 2>/dev/null || echo "")

    if [[ -z "$vpc_name" ]]; then
        echo "Unnamed"
    else
        echo "$vpc_name"
    fi
}

# Function to check if gateway endpoint already exists
check_existing_endpoint() {
    local region=$1
    local vpc_id=$2
    local service=$3

    local service_name="com.amazonaws.${region}.${service}"

    local endpoint_id=$(aws ec2 describe-vpc-endpoints \
        --region "$region" \
        --filters "Name=vpc-id,Values=$vpc_id" "Name=service-name,Values=$service_name" "Name=vpc-endpoint-type,Values=Gateway" \
        --query 'VpcEndpoints[0].VpcEndpointId' \
        --output text 2>/dev/null || echo "")

    if [[ "$endpoint_id" != "None" && -n "$endpoint_id" ]]; then
        echo "$endpoint_id"
    else
        echo ""
    fi
}

# Function to get all route tables for a VPC
get_route_tables() {
    local region=$1
    local vpc_id=$2

    aws ec2 describe-route-tables \
        --region "$region" \
        --filters "Name=vpc-id,Values=$vpc_id" \
        --query 'RouteTables[].RouteTableId' \
        --output text 2>/dev/null || echo ""
}

# Function to get prefix list ID for a service
get_prefix_list_id() {
    local region=$1
    local service=$2

    local service_name="com.amazonaws.${region}.${service}"

    local prefix_list_id=$(aws ec2 describe-prefix-lists \
        --region "$region" \
        --filters "Name=prefix-list-name,Values=$service_name" \
        --query 'PrefixLists[0].PrefixListId' \
        --output text 2>/dev/null || echo "")

    if [[ "$prefix_list_id" != "None" && -n "$prefix_list_id" ]]; then
        echo "$prefix_list_id"
    else
        echo ""
    fi
}

# Function to check if route already exists
check_route_exists() {
    local region=$1
    local route_table_id=$2
    local prefix_list_id=$3

    local existing_route=$(aws ec2 describe-route-tables \
        --region "$region" \
        --route-table-ids "$route_table_id" \
        --query "RouteTables[0].Routes[?DestinationPrefixListId=='$prefix_list_id'].DestinationPrefixListId" \
        --output text 2>/dev/null || echo "")

    if [[ -n "$existing_route" && "$existing_route" != "None" ]]; then
        return 0  # Route exists
    else
        return 1  # Route does not exist
    fi
}

# Function to create gateway endpoint
create_gateway_endpoint() {
    local region=$1
    local vpc_id=$2
    local vpc_name=$3
    local service=$4

    local service_name="com.amazonaws.${region}.${service}"

    echo -e "  ${BLUE}Creating gateway endpoint for $service...${NC}"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "  ${YELLOW}[DRY RUN] Would create endpoint${NC}"
        echo "$region,$vpc_id,$vpc_name,DRY-RUN,Would Create,N/A,0,Dry run mode" >> "$OUTPUT_CSV"
        echo "  [DRY RUN] $region - $vpc_id ($vpc_name)" >> "$SUMMARY_FILE"
        ENDPOINTS_CREATED=$((ENDPOINTS_CREATED + 1))
        return 0
    fi

    # Get all route tables for the VPC
    local route_tables=$(get_route_tables "$region" "$vpc_id")

    if [[ -z "$route_tables" ]]; then
        echo -e "  ${RED}✗ No route tables found${NC}"
        echo "$region,$vpc_id,$vpc_name,FAILED,No Route Tables,0,0,No route tables found" >> "$OUTPUT_CSV"
        echo "  [FAILED] $region - $vpc_id ($vpc_name) - No route tables" >> "$SUMMARY_FILE"
        ENDPOINTS_FAILED=$((ENDPOINTS_FAILED + 1))
        return 1
    fi

    # Create endpoint with route table associations
    local endpoint_result=$(aws ec2 create-vpc-endpoint \
        --region "$region" \
        --vpc-id "$vpc_id" \
        --service-name "$service_name" \
        --vpc-endpoint-type Gateway \
        --route-table-ids $route_tables \
        --query 'VpcEndpoint.VpcEndpointId' \
        --output text 2>&1)

    if [[ $? -eq 0 && "$endpoint_result" != "None" && -n "$endpoint_result" ]]; then
        local endpoint_id="$endpoint_result"
        echo -e "  ${GREEN}✓ Endpoint created: $endpoint_id${NC}"

        # Count route tables
        local rt_count=$(echo "$route_tables" | wc -w)

        echo "$region,$vpc_id,$vpc_name,$endpoint_id,Created,$rt_count,$rt_count,Successfully created" >> "$OUTPUT_CSV"
        echo "  [CREATED] $region - $vpc_id ($vpc_name) - $endpoint_id ($rt_count route tables)" >> "$SUMMARY_FILE"
        ENDPOINTS_CREATED=$((ENDPOINTS_CREATED + 1))
        ROUTES_ADDED=$((ROUTES_ADDED + rt_count))
        return 0
    else
        echo -e "  ${RED}✗ Failed to create endpoint${NC}"
        echo "  Error: $endpoint_result"
        echo "$region,$vpc_id,$vpc_name,FAILED,Creation Failed,0,0,$endpoint_result" >> "$OUTPUT_CSV"
        echo "  [FAILED] $region - $vpc_id ($vpc_name) - $endpoint_result" >> "$SUMMARY_FILE"
        ENDPOINTS_FAILED=$((ENDPOINTS_FAILED + 1))
        return 1
    fi
}

# Function to add route to route table using prefix list
add_route_to_table() {
    local region=$1
    local route_table_id=$2
    local gateway_endpoint_id=$3
    local prefix_list_id=$4

    # Check if route already exists
    if check_route_exists "$region" "$route_table_id" "$prefix_list_id"; then
        echo -e "    ${YELLOW}Route already exists in $route_table_id${NC}"
        ROUTES_EXISTING=$((ROUTES_EXISTING + 1))
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "    ${YELLOW}[DRY RUN] Would add route to $route_table_id${NC}"
        ROUTES_ADDED=$((ROUTES_ADDED + 1))
        return 0
    fi

    local result=$(aws ec2 create-route \
        --region "$region" \
        --route-table-id "$route_table_id" \
        --destination-prefix-list-id "$prefix_list_id" \
        --gateway-id "$gateway_endpoint_id" 2>&1)

    if [[ $? -eq 0 ]]; then
        echo -e "    ${GREEN}✓ Route added to $route_table_id${NC}"
        ROUTES_ADDED=$((ROUTES_ADDED + 1))
        return 0
    else
        echo -e "    ${RED}✗ Failed to add route to $route_table_id${NC}"
        echo "    Error: $result"
        ROUTES_FAILED=$((ROUTES_FAILED + 1))
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
    VPCS=$(aws ec2 describe-vpcs \
        --region "$region" \
        --query 'Vpcs[].[VpcId]' \
        --output text 2>/dev/null || echo "")

    if [[ -z "$VPCS" ]]; then
        echo "  No VPCs found"
        echo ""
        continue
    fi

    VPC_COUNT=$(echo "$VPCS" | wc -l)
    echo "  Found $VPC_COUNT VPC(s)"

    # Get prefix list ID for the service in this region
    PREFIX_LIST_ID=$(get_prefix_list_id "$region" "$SERVICE_NAME")

    if [[ -z "$PREFIX_LIST_ID" ]]; then
        echo -e "  ${YELLOW}⚠ Service $SERVICE_NAME not available in $region${NC}"
        echo ""
        continue
    fi

    echo "  Prefix List ID: $PREFIX_LIST_ID"

    # Process each VPC
    while IFS= read -r vpc_id; do
        [[ -z "$vpc_id" ]] && continue

        TOTAL_VPCS=$((TOTAL_VPCS + 1))
        vpc_name=$(get_vpc_name "$region" "$vpc_id")

        echo ""
        echo -e "  VPC: ${BLUE}$vpc_id${NC} ($vpc_name)"

        # Check if endpoint already exists
        existing_endpoint=$(check_existing_endpoint "$region" "$vpc_id" "$SERVICE_NAME")

        if [[ -n "$existing_endpoint" ]]; then
            echo -e "  ${YELLOW}Gateway endpoint already exists: $existing_endpoint${NC}"

            # Get route tables
            route_tables=$(get_route_tables "$region" "$vpc_id")
            rt_count=$(echo "$route_tables" | wc -w)

            echo "$region,$vpc_id,$vpc_name,$existing_endpoint,Already Exists,$rt_count,0,Endpoint already exists" >> "$OUTPUT_CSV"
            echo "  [SKIP] $region - $vpc_id ($vpc_name) - Already exists: $existing_endpoint" >> "$SUMMARY_FILE"
            ENDPOINTS_EXISTING=$((ENDPOINTS_EXISTING + 1))

            # Check routes
            echo "  Checking routes in $rt_count route table(s)..."
            for rt_id in $route_tables; do
                if ! check_route_exists "$region" "$rt_id" "$PREFIX_LIST_ID"; then
                    echo -e "    ${BLUE}Adding missing route to $rt_id...${NC}"
                    add_route_to_table "$region" "$rt_id" "$existing_endpoint" "$PREFIX_LIST_ID"
                else
                    echo -e "    ${GREEN}✓ Route exists in $rt_id${NC}"
                    ROUTES_EXISTING=$((ROUTES_EXISTING + 1))
                fi
            done

            continue
        fi

        # Create gateway endpoint
        create_gateway_endpoint "$region" "$vpc_id" "$vpc_name" "$SERVICE_NAME"

    done <<< "$VPCS"

    echo ""
done

# Generate summary
cat >> "$SUMMARY_FILE" <<EOF

SUMMARY
========================================
Total regions checked: $TOTAL_REGIONS
Total VPCs found: $TOTAL_VPCS
Service: $SERVICE_NAME

Endpoints created: $ENDPOINTS_CREATED
Endpoints already existed: $ENDPOINTS_EXISTING
Endpoints failed: $ENDPOINTS_FAILED

Routes added: $ROUTES_ADDED
Routes already existed: $ROUTES_EXISTING
Routes failed: $ROUTES_FAILED

EOF

# Display summary
echo -e "${CYAN}==========================================${NC}"
echo -e "${CYAN}SUMMARY${NC}"
echo -e "${CYAN}==========================================${NC}"
echo "Total regions checked: $TOTAL_REGIONS"
echo "Total VPCs found: $TOTAL_VPCS"
echo "Service: $SERVICE_NAME"
echo ""
echo -e "Endpoints created: ${GREEN}$ENDPOINTS_CREATED${NC}"
echo -e "Endpoints already existed: ${YELLOW}$ENDPOINTS_EXISTING${NC}"
if [[ $ENDPOINTS_FAILED -gt 0 ]]; then
    echo -e "Endpoints failed: ${RED}$ENDPOINTS_FAILED${NC}"
fi
echo ""
echo -e "Routes added: ${GREEN}$ROUTES_ADDED${NC}"
echo -e "Routes already existed: ${YELLOW}$ROUTES_EXISTING${NC}"
if [[ $ROUTES_FAILED -gt 0 ]]; then
    echo -e "Routes failed: ${RED}$ROUTES_FAILED${NC}"
fi
echo ""
echo "Output files:"
echo "  Summary: $SUMMARY_FILE"
echo "  CSV:     $OUTPUT_CSV"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${BLUE}This was a dry run. No changes were made.${NC}"
    echo "Run without DRY_RUN to actually create endpoints."
    echo ""
fi

if [[ $ENDPOINTS_CREATED -gt 0 || $ROUTES_ADDED -gt 0 ]]; then
    echo -e "${GREEN}✓ Gateway endpoints setup complete!${NC}"
elif [[ $ENDPOINTS_EXISTING -eq $TOTAL_VPCS && $TOTAL_VPCS -gt 0 ]]; then
    echo -e "${YELLOW}All VPCs already have gateway endpoints configured.${NC}"
elif [[ $ENDPOINTS_FAILED -gt 0 || $ROUTES_FAILED -gt 0 ]]; then
    echo -e "${RED}Some operations failed. Check the summary for details.${NC}"
    exit 1
fi

echo -e "${CYAN}==========================================${NC}"
