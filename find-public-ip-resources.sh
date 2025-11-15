#!/bin/bash

# Script to identify all resources with public IP addresses across all VPCs in all AWS regions
# This helps identify potential security exposure points in your AWS infrastructure

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Output files
CSV_OUTPUT="public-ip-resources.csv"
JSON_OUTPUT="public-ip-resources.json"
REPORT_FILE="public-ip-resources-report.txt"

# Counters
TOTAL_RESOURCES=0
TOTAL_REGIONS_CHECKED=0

# Temporary file for JSON accumulation
TEMP_JSON=$(mktemp)
echo '{"resources": [' > "$TEMP_JSON"
FIRST_RESOURCE=true

echo "==========================================="
echo "Public IP Resources Inventory"
echo "==========================================="
echo ""

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}"
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}Warning: jq is not installed. JSON output will be limited.${NC}"
    echo -e "${YELLOW}Install jq for better JSON formatting: sudo apt-get install jq${NC}"
    HAS_JQ=false
else
    HAS_JQ=true
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${RED}Error: AWS credentials not configured or invalid${NC}"
    exit 1
fi

# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "AWS Account: $ACCOUNT_ID"
echo ""

# Initialize CSV output
echo "Region,VPC ID,VPC Name,Resource Type,Resource ID,Resource Name,Public IP,Public DNS,State,Additional Info" > "$CSV_OUTPUT"

# Initialize report
{
    echo "Public IP Resources Inventory Report"
    echo "Generated: $(date)"
    echo "AWS Account: $ACCOUNT_ID"
    echo "========================================"
    echo ""
} > "$REPORT_FILE"

# Function to get VPC name from tags
get_vpc_name() {
    local region=$1
    local vpc_id=$2

    if [ -z "$vpc_id" ] || [ "$vpc_id" == "null" ]; then
        echo "N/A"
        return
    fi

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

# Function to get resource name from tags
get_resource_name() {
    local tags=$1

    if [ -z "$tags" ] || [ "$tags" == "null" ] || [ "$tags" == "None" ]; then
        echo "Unnamed"
        return
    fi

    echo "$tags"
}

# Function to add resource to outputs
add_resource() {
    local region=$1
    local vpc_id=$2
    local vpc_name=$3
    local resource_type=$4
    local resource_id=$5
    local resource_name=$6
    local public_ip=$7
    local public_dns=$8
    local state=$9
    local additional_info=${10:-""}

    # CSV output
    echo "$region,$vpc_id,$vpc_name,$resource_type,$resource_id,$resource_name,$public_ip,$public_dns,$state,$additional_info" >> "$CSV_OUTPUT"

    # JSON output
    if [ "$FIRST_RESOURCE" = true ]; then
        FIRST_RESOURCE=false
    else
        echo "," >> "$TEMP_JSON"
    fi

    cat >> "$TEMP_JSON" <<EOF
{
  "region": "$region",
  "vpc_id": "$vpc_id",
  "vpc_name": "$vpc_name",
  "resource_type": "$resource_type",
  "resource_id": "$resource_id",
  "resource_name": "$resource_name",
  "public_ip": "$public_ip",
  "public_dns": "$public_dns",
  "state": "$state",
  "additional_info": "$additional_info"
}
EOF

    TOTAL_RESOURCES=$((TOTAL_RESOURCES + 1))
}

# Function to check EC2 instances
check_ec2_instances() {
    local region=$1

    echo -n "  Checking EC2 instances... "

    local instances=$(aws ec2 describe-instances \
        --region "$region" \
        --query 'Reservations[].Instances[?PublicIpAddress!=`null`].[InstanceId,VpcId,Tags[?Key==`Name`].Value|[0],PublicIpAddress,PublicDnsName,State.Name,InstanceType,PrivateIpAddress]' \
        --output json 2>/dev/null || echo "[]")

    local count=0
    if [ "$HAS_JQ" = true ]; then
        count=$(echo "$instances" | jq '. | length')

        if [ "$count" -gt 0 ]; then
            echo "$instances" | jq -c '.[]' | while read -r instance; do
                instance_id=$(echo "$instance" | jq -r '.[0]')
                vpc_id=$(echo "$instance" | jq -r '.[1]')
                name=$(echo "$instance" | jq -r '.[2] // "Unnamed"')
                public_ip=$(echo "$instance" | jq -r '.[3]')
                public_dns=$(echo "$instance" | jq -r '.[4]')
                state=$(echo "$instance" | jq -r '.[5]')
                instance_type=$(echo "$instance" | jq -r '.[6]')
                private_ip=$(echo "$instance" | jq -r '.[7]')

                vpc_name=$(get_vpc_name "$region" "$vpc_id")

                add_resource "$region" "$vpc_id" "$vpc_name" "EC2 Instance" "$instance_id" "$name" \
                    "$public_ip" "$public_dns" "$state" "Type: $instance_type, Private IP: $private_ip"
            done
        fi
    fi

    echo -e "${GREEN}$count found${NC}"
}

# Function to check NAT Gateways
check_nat_gateways() {
    local region=$1

    echo -n "  Checking NAT Gateways... "

    local nat_gateways=$(aws ec2 describe-nat-gateways \
        --region "$region" \
        --query 'NatGateways[?State==`available`].[NatGatewayId,VpcId,Tags[?Key==`Name`].Value|[0],NatGatewayAddresses[0].PublicIp,State,SubnetId]' \
        --output json 2>/dev/null || echo "[]")

    local count=0
    if [ "$HAS_JQ" = true ]; then
        count=$(echo "$nat_gateways" | jq '. | length')

        if [ "$count" -gt 0 ]; then
            echo "$nat_gateways" | jq -c '.[]' | while read -r nat; do
                nat_id=$(echo "$nat" | jq -r '.[0]')
                vpc_id=$(echo "$nat" | jq -r '.[1]')
                name=$(echo "$nat" | jq -r '.[2] // "Unnamed"')
                public_ip=$(echo "$nat" | jq -r '.[3]')
                state=$(echo "$nat" | jq -r '.[4]')
                subnet_id=$(echo "$nat" | jq -r '.[5]')

                vpc_name=$(get_vpc_name "$region" "$vpc_id")

                add_resource "$region" "$vpc_id" "$vpc_name" "NAT Gateway" "$nat_id" "$name" \
                    "$public_ip" "N/A" "$state" "Subnet: $subnet_id"
            done
        fi
    fi

    echo -e "${GREEN}$count found${NC}"
}

# Function to check Elastic IPs
check_elastic_ips() {
    local region=$1

    echo -n "  Checking Elastic IPs... "

    local eips=$(aws ec2 describe-addresses \
        --region "$region" \
        --query 'Addresses[].[AllocationId,PublicIp,InstanceId,NetworkInterfaceId,AssociationId,Domain,Tags[?Key==`Name`].Value|[0],PrivateIpAddress]' \
        --output json 2>/dev/null || echo "[]")

    local count=0
    if [ "$HAS_JQ" = true ]; then
        count=$(echo "$eips" | jq '. | length')

        if [ "$count" -gt 0 ]; then
            echo "$eips" | jq -c '.[]' | while read -r eip; do
                allocation_id=$(echo "$eip" | jq -r '.[0]')
                public_ip=$(echo "$eip" | jq -r '.[1]')
                instance_id=$(echo "$eip" | jq -r '.[2] // "Unassociated"')
                eni_id=$(echo "$eip" | jq -r '.[3] // "N/A"')
                association_id=$(echo "$eip" | jq -r '.[4] // "N/A"')
                domain=$(echo "$eip" | jq -r '.[5]')
                name=$(echo "$eip" | jq -r '.[6] // "Unnamed"')
                private_ip=$(echo "$eip" | jq -r '.[7] // "N/A"')

                # Try to get VPC from instance or ENI
                vpc_id="N/A"
                if [ "$instance_id" != "Unassociated" ]; then
                    vpc_id=$(aws ec2 describe-instances \
                        --region "$region" \
                        --instance-ids "$instance_id" \
                        --query 'Reservations[0].Instances[0].VpcId' \
                        --output text 2>/dev/null || echo "N/A")
                elif [ "$eni_id" != "N/A" ]; then
                    vpc_id=$(aws ec2 describe-network-interfaces \
                        --region "$region" \
                        --network-interface-ids "$eni_id" \
                        --query 'NetworkInterfaces[0].VpcId' \
                        --output text 2>/dev/null || echo "N/A")
                fi

                vpc_name=$(get_vpc_name "$region" "$vpc_id")

                local state="Associated"
                if [ "$instance_id" == "Unassociated" ]; then
                    state="Unassociated"
                fi

                add_resource "$region" "$vpc_id" "$vpc_name" "Elastic IP" "$allocation_id" "$name" \
                    "$public_ip" "N/A" "$state" "Instance: $instance_id, ENI: $eni_id, Private IP: $private_ip"
            done
        fi
    fi

    echo -e "${GREEN}$count found${NC}"
}

# Function to check Load Balancers (Classic)
check_classic_load_balancers() {
    local region=$1

    echo -n "  Checking Classic Load Balancers... "

    local elbs=$(aws elb describe-load-balancers \
        --region "$region" \
        --query 'LoadBalancerDescriptions[?Scheme==`internet-facing`].[LoadBalancerName,DNSName,VPCId,Scheme,Instances[].InstanceId|join(`,`,@)]' \
        --output json 2>/dev/null || echo "[]")

    local count=0
    if [ "$HAS_JQ" = true ]; then
        count=$(echo "$elbs" | jq '. | length')

        if [ "$count" -gt 0 ]; then
            echo "$elbs" | jq -c '.[]' | while read -r elb; do
                lb_name=$(echo "$elb" | jq -r '.[0]')
                dns_name=$(echo "$elb" | jq -r '.[1]')
                vpc_id=$(echo "$elb" | jq -r '.[2] // "EC2-Classic"')
                scheme=$(echo "$elb" | jq -r '.[3]')
                instances=$(echo "$elb" | jq -r '.[4] // "None"')

                vpc_name=$(get_vpc_name "$region" "$vpc_id")

                add_resource "$region" "$vpc_id" "$vpc_name" "Classic Load Balancer" "$lb_name" "$lb_name" \
                    "N/A (DNS-based)" "$dns_name" "Active" "Scheme: $scheme, Instances: $instances"
            done
        fi
    fi

    echo -e "${GREEN}$count found${NC}"
}

# Function to check Application/Network Load Balancers
check_alb_nlb() {
    local region=$1

    echo -n "  Checking ALB/NLB Load Balancers... "

    local lbs=$(aws elbv2 describe-load-balancers \
        --region "$region" \
        --query 'LoadBalancers[?Scheme==`internet-facing`].[LoadBalancerArn,LoadBalancerName,DNSName,VpcId,Type,State.Code]' \
        --output json 2>/dev/null || echo "[]")

    local count=0
    if [ "$HAS_JQ" = true ]; then
        count=$(echo "$lbs" | jq '. | length')

        if [ "$count" -gt 0 ]; then
            echo "$lbs" | jq -c '.[]' | while read -r lb; do
                lb_arn=$(echo "$lb" | jq -r '.[0]')
                lb_name=$(echo "$lb" | jq -r '.[1]')
                dns_name=$(echo "$lb" | jq -r '.[2]')
                vpc_id=$(echo "$lb" | jq -r '.[3]')
                lb_type=$(echo "$lb" | jq -r '.[4]')
                state=$(echo "$lb" | jq -r '.[5]')

                vpc_name=$(get_vpc_name "$region" "$vpc_id")

                local resource_type="Application Load Balancer"
                if [ "$lb_type" == "network" ]; then
                    resource_type="Network Load Balancer"
                elif [ "$lb_type" == "gateway" ]; then
                    resource_type="Gateway Load Balancer"
                fi

                add_resource "$region" "$vpc_id" "$vpc_name" "$resource_type" "$lb_name" "$lb_name" \
                    "N/A (DNS-based)" "$dns_name" "$state" "Type: $lb_type"
            done
        fi
    fi

    echo -e "${GREEN}$count found${NC}"
}

# Function to check RDS instances
check_rds_instances() {
    local region=$1

    echo -n "  Checking RDS instances... "

    local rds_instances=$(aws rds describe-db-instances \
        --region "$region" \
        --query 'DBInstances[?PubliclyAccessible==`true`].[DBInstanceIdentifier,Endpoint.Address,DBSubnetGroup.VpcId,DBInstanceStatus,Engine,DBInstanceClass]' \
        --output json 2>/dev/null || echo "[]")

    local count=0
    if [ "$HAS_JQ" = true ]; then
        count=$(echo "$rds_instances" | jq '. | length')

        if [ "$count" -gt 0 ]; then
            echo "$rds_instances" | jq -c '.[]' | while read -r rds; do
                db_id=$(echo "$rds" | jq -r '.[0]')
                endpoint=$(echo "$rds" | jq -r '.[1] // "N/A"')
                vpc_id=$(echo "$rds" | jq -r '.[2] // "N/A"')
                status=$(echo "$rds" | jq -r '.[3]')
                engine=$(echo "$rds" | jq -r '.[4]')
                instance_class=$(echo "$rds" | jq -r '.[5]')

                vpc_name=$(get_vpc_name "$region" "$vpc_id")

                add_resource "$region" "$vpc_id" "$vpc_name" "RDS Instance" "$db_id" "$db_id" \
                    "N/A (Endpoint-based)" "$endpoint" "$status" "Engine: $engine, Class: $instance_class"
            done
        fi
    fi

    echo -e "${GREEN}$count found${NC}"
}

# Function to check Network Interfaces with public IPs
check_network_interfaces() {
    local region=$1

    echo -n "  Checking Network Interfaces... "

    local enis=$(aws ec2 describe-network-interfaces \
        --region "$region" \
        --query 'NetworkInterfaces[?Association.PublicIp!=`null`].[NetworkInterfaceId,VpcId,Association.PublicIp,Association.PublicDnsName,Status,Description,InterfaceType,Attachment.InstanceId]' \
        --output json 2>/dev/null || echo "[]")

    local count=0
    if [ "$HAS_JQ" = true ]; then
        count=$(echo "$enis" | jq '. | length')

        if [ "$count" -gt 0 ]; then
            echo "$enis" | jq -c '.[]' | while read -r eni; do
                eni_id=$(echo "$eni" | jq -r '.[0]')
                vpc_id=$(echo "$eni" | jq -r '.[1]')
                public_ip=$(echo "$eni" | jq -r '.[2]')
                public_dns=$(echo "$eni" | jq -r '.[3] // "N/A"')
                status=$(echo "$eni" | jq -r '.[4]')
                description=$(echo "$eni" | jq -r '.[5]')
                interface_type=$(echo "$eni" | jq -r '.[6]')
                instance_id=$(echo "$eni" | jq -r '.[7] // "Not attached"')

                vpc_name=$(get_vpc_name "$region" "$vpc_id")

                # Skip if already counted as EC2 instance or NAT gateway
                if [[ "$description" == *"NAT Gateway"* ]]; then
                    continue
                fi

                add_resource "$region" "$vpc_id" "$vpc_name" "Network Interface" "$eni_id" "$description" \
                    "$public_ip" "$public_dns" "$status" "Type: $interface_type, Instance: $instance_id"
            done
        fi
    fi

    echo -e "${GREEN}$count found${NC}"
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
    TOTAL_REGIONS_CHECKED=$((TOTAL_REGIONS_CHECKED + 1))

    # Check different resource types
    if [ "$HAS_JQ" = true ]; then
        check_ec2_instances "$region"
        check_nat_gateways "$region"
        check_elastic_ips "$region"
        check_classic_load_balancers "$region"
        check_alb_nlb "$region"
        check_rds_instances "$region"
        check_network_interfaces "$region"
    else
        echo -e "  ${YELLOW}Skipping detailed checks (jq not installed)${NC}"
    fi

    echo ""
done

# Finalize JSON output
echo "" >> "$TEMP_JSON"
echo "]}," >> "$TEMP_JSON"
echo "\"metadata\": {" >> "$TEMP_JSON"
echo "  \"generated_at\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"," >> "$TEMP_JSON"
echo "  \"account_id\": \"$ACCOUNT_ID\"," >> "$TEMP_JSON"
echo "  \"total_resources\": $TOTAL_RESOURCES," >> "$TEMP_JSON"
echo "  \"regions_checked\": $TOTAL_REGIONS_CHECKED" >> "$TEMP_JSON"
echo "}" >> "$TEMP_JSON"
echo "}" >> "$TEMP_JSON"

# Format JSON if jq is available
if [ "$HAS_JQ" = true ]; then
    jq '.' "$TEMP_JSON" > "$JSON_OUTPUT" 2>/dev/null || mv "$TEMP_JSON" "$JSON_OUTPUT"
else
    mv "$TEMP_JSON" "$JSON_OUTPUT"
fi

rm -f "$TEMP_JSON"

# Generate summary report
{
    echo ""
    echo "SUMMARY"
    echo "========================================"
    echo "Total regions checked: $TOTAL_REGIONS_CHECKED"
    echo "Total resources with public IPs: $TOTAL_RESOURCES"
    echo ""
    echo "Resources by type:"

    if [ "$HAS_JQ" = true ] && [ -f "$JSON_OUTPUT" ]; then
        jq -r '.resources | group_by(.resource_type) | .[] | "\(.| length) - \(.[0].resource_type)"' "$JSON_OUTPUT" 2>/dev/null | while read -r line; do
            echo "  $line"
        done
    else
        tail -n +2 "$CSV_OUTPUT" | cut -d',' -f4 | sort | uniq -c | while read -r count type; do
            echo "  $count - $type"
        done
    fi

    echo ""
    echo "Resources by region:"
    tail -n +2 "$CSV_OUTPUT" | cut -d',' -f1 | sort | uniq -c | while read -r count region; do
        echo "  $count - $region"
    done

    echo ""
    echo "Resources by VPC:"
    tail -n +2 "$CSV_OUTPUT" | cut -d',' -f2,3 | sort | uniq -c | while read -r count vpc_info; do
        echo "  $count - $vpc_info"
    done

} >> "$REPORT_FILE"

# Display summary
echo ""
echo "==========================================="
echo "SUMMARY"
echo "==========================================="
echo "Total regions checked: $TOTAL_REGIONS_CHECKED"
echo -e "Total resources with public IPs: ${YELLOW}$TOTAL_RESOURCES${NC}"
echo ""
echo "Output files generated:"
echo -e "  ${GREEN}✓${NC} CSV:    $CSV_OUTPUT"
echo -e "  ${GREEN}✓${NC} JSON:   $JSON_OUTPUT"
echo -e "  ${GREEN}✓${NC} Report: $REPORT_FILE"
echo ""

if [ $TOTAL_RESOURCES -gt 0 ]; then
    echo -e "${YELLOW}⚠ Warning: Found resources with public IP addresses${NC}"
    echo "Review the output files to assess security exposure"
    echo ""
    echo "Top resource types found:"
    tail -n +2 "$CSV_OUTPUT" | cut -d',' -f4 | sort | uniq -c | sort -rn | head -5
else
    echo -e "${GREEN}✓ No resources with public IPs found${NC}"
fi

echo ""
echo "==========================================="
