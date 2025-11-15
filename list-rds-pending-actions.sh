#!/bin/bash

# Script to identify RDS instances with pending actions across all AWS regions
# Checks for pending maintenance actions and pending modifications

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
OUTPUT_CSV="rds-pending-actions.csv"
SUMMARY_FILE="rds-pending-actions-summary.txt"

# Counters
TOTAL_REGIONS=0
TOTAL_INSTANCES=0
INSTANCES_WITH_PENDING_ACTIONS=0
INSTANCES_WITH_PENDING_MAINTENANCE=0
INSTANCES_WITH_PENDING_MODIFICATIONS=0

echo -e "${CYAN}==========================================${NC}"
echo -e "${CYAN}RDS Pending Actions Report${NC}"
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

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}Warning: jq is not installed. Using basic text parsing.${NC}"
    echo "For best results, install jq: https://stedolan.github.io/jq/"
    echo ""
    USE_JQ=false
else
    USE_JQ=true
fi

# Get Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "AWS Account ID: $ACCOUNT_ID"
echo "Report Date: $(date)"
echo ""

# Initialize CSV output
echo "Region,DB Instance,DB Engine,DB Version,Instance Class,Status,Pending Maintenance,Pending Modifications" > "$OUTPUT_CSV"

# Initialize summary file
cat > "$SUMMARY_FILE" <<EOF
RDS Pending Actions Summary
Generated: $(date)
Account: $ACCOUNT_ID
========================================

EOF

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

    # Get all RDS instances in the region
    if [[ "$USE_JQ" == "true" ]]; then
        INSTANCES_JSON=$(aws rds describe-db-instances \
            --region "$region" \
            --query 'DBInstances[*].[DBInstanceIdentifier,Engine,EngineVersion,DBInstanceClass,DBInstanceStatus]' \
            --output json 2>/dev/null || echo "[]")

        INSTANCE_COUNT=$(echo "$INSTANCES_JSON" | jq '. | length')
    else
        INSTANCES_TEXT=$(aws rds describe-db-instances \
            --region "$region" \
            --query 'DBInstances[*].DBInstanceIdentifier' \
            --output text 2>/dev/null || echo "")

        if [[ -z "$INSTANCES_TEXT" ]]; then
            INSTANCE_COUNT=0
        else
            INSTANCE_COUNT=$(echo "$INSTANCES_TEXT" | wc -w)
        fi
    fi

    if [[ $INSTANCE_COUNT -eq 0 ]]; then
        echo "  No RDS instances found"
        echo ""
        continue
    fi

    echo "  Found $INSTANCE_COUNT RDS instance(s)"
    TOTAL_INSTANCES=$((TOTAL_INSTANCES + INSTANCE_COUNT))

    # Get pending maintenance actions for this region
    PENDING_MAINTENANCE=$(aws rds describe-pending-maintenance-actions \
        --region "$region" \
        --output json 2>/dev/null || echo '{"PendingMaintenanceActions":[]}')

    # Process each instance
    if [[ "$USE_JQ" == "true" ]]; then
        # Using jq for better parsing
        for i in $(seq 0 $((INSTANCE_COUNT - 1))); do
            DB_INSTANCE=$(echo "$INSTANCES_JSON" | jq -r ".[$i][0]")
            DB_ENGINE=$(echo "$INSTANCES_JSON" | jq -r ".[$i][1]")
            DB_VERSION=$(echo "$INSTANCES_JSON" | jq -r ".[$i][2]")
            DB_CLASS=$(echo "$INSTANCES_JSON" | jq -r ".[$i][3]")
            DB_STATUS=$(echo "$INSTANCES_JSON" | jq -r ".[$i][4]")

            # Get detailed instance info for pending modifications
            INSTANCE_DETAIL=$(aws rds describe-db-instances \
                --region "$region" \
                --db-instance-identifier "$DB_INSTANCE" \
                --output json 2>/dev/null)

            # Check for pending modifications
            PENDING_MODS=$(echo "$INSTANCE_DETAIL" | jq -r '.DBInstances[0].PendingModifiedValues // empty | to_entries | map("\(.key)=\(.value)") | join("; ")' 2>/dev/null || echo "")

            # Check for pending maintenance
            PENDING_MAINT=$(echo "$PENDING_MAINTENANCE" | jq -r --arg db "$DB_INSTANCE" \
                '.PendingMaintenanceActions[] | select(.ResourceIdentifier | contains($db)) | .PendingMaintenanceActionDetails[] | "\(.Action) (auto-apply: \(.AutoAppliedAfterDate // "N/A"), opt-in: \(.OptInStatus // "N/A"))"' 2>/dev/null | tr '\n' '; ' || echo "")

            # Display results
            if [[ -n "$PENDING_MAINT" ]] || [[ -n "$PENDING_MODS" ]]; then
                echo ""
                echo -e "  ${YELLOW}DB Instance: $DB_INSTANCE${NC}"
                echo "    Engine: $DB_ENGINE $DB_VERSION"
                echo "    Class: $DB_CLASS"
                echo "    Status: $DB_STATUS"

                if [[ -n "$PENDING_MAINT" ]]; then
                    echo -e "    ${RED}Pending Maintenance:${NC}"
                    echo "      $PENDING_MAINT" | sed 's/; /\n      /g'
                    INSTANCES_WITH_PENDING_MAINTENANCE=$((INSTANCES_WITH_PENDING_MAINTENANCE + 1))
                fi

                if [[ -n "$PENDING_MODS" ]]; then
                    echo -e "    ${YELLOW}Pending Modifications:${NC}"
                    echo "      $PENDING_MODS" | sed 's/; /\n      /g'
                    INSTANCES_WITH_PENDING_MODIFICATIONS=$((INSTANCES_WITH_PENDING_MODIFICATIONS + 1))
                fi

                INSTANCES_WITH_PENDING_ACTIONS=$((INSTANCES_WITH_PENDING_ACTIONS + 1))

                # Write to summary
                echo "  [$region] $DB_INSTANCE - Maintenance: ${PENDING_MAINT:-None} | Modifications: ${PENDING_MODS:-None}" >> "$SUMMARY_FILE"
            else
                echo -e "  ${GREEN}✓${NC} $DB_INSTANCE - No pending actions"
            fi

            # Write to CSV
            echo "$region,\"$DB_INSTANCE\",\"$DB_ENGINE\",\"$DB_VERSION\",\"$DB_CLASS\",\"$DB_STATUS\",\"${PENDING_MAINT:-None}\",\"${PENDING_MODS:-None}\"" >> "$OUTPUT_CSV"
        done
    else
        # Fallback without jq - basic parsing
        for DB_INSTANCE in $INSTANCES_TEXT; do
            # Get detailed instance info
            INSTANCE_DETAIL=$(aws rds describe-db-instances \
                --region "$region" \
                --db-instance-identifier "$DB_INSTANCE" \
                --query 'DBInstances[0].[Engine,EngineVersion,DBInstanceClass,DBInstanceStatus]' \
                --output text 2>/dev/null)

            DB_ENGINE=$(echo "$INSTANCE_DETAIL" | awk '{print $1}')
            DB_VERSION=$(echo "$INSTANCE_DETAIL" | awk '{print $2}')
            DB_CLASS=$(echo "$INSTANCE_DETAIL" | awk '{print $3}')
            DB_STATUS=$(echo "$INSTANCE_DETAIL" | awk '{print $4}')

            # Check for pending maintenance
            PENDING_MAINT=$(aws rds describe-pending-maintenance-actions \
                --region "$region" \
                --filters "Name=db-instance-id,Values=$DB_INSTANCE" \
                --query 'PendingMaintenanceActions[0].PendingMaintenanceActionDetails[*].[Action,AutoAppliedAfterDate]' \
                --output text 2>/dev/null | tr '\t' ':' | tr '\n' '; ' || echo "")

            # Check for pending modifications (basic check)
            PENDING_MODS=$(aws rds describe-db-instances \
                --region "$region" \
                --db-instance-identifier "$DB_INSTANCE" \
                --query 'DBInstances[0].PendingModifiedValues' \
                --output text 2>/dev/null)

            if [[ "$PENDING_MODS" != "None" ]] && [[ -n "$PENDING_MODS" ]]; then
                PENDING_MODS_TEXT="Yes"
            else
                PENDING_MODS_TEXT=""
            fi

            # Display results
            if [[ -n "$PENDING_MAINT" ]] || [[ -n "$PENDING_MODS_TEXT" ]]; then
                echo ""
                echo -e "  ${YELLOW}DB Instance: $DB_INSTANCE${NC}"
                echo "    Engine: $DB_ENGINE $DB_VERSION"
                echo "    Status: $DB_STATUS"

                if [[ -n "$PENDING_MAINT" ]]; then
                    echo -e "    ${RED}Pending Maintenance: $PENDING_MAINT${NC}"
                    INSTANCES_WITH_PENDING_MAINTENANCE=$((INSTANCES_WITH_PENDING_MAINTENANCE + 1))
                fi

                if [[ -n "$PENDING_MODS_TEXT" ]]; then
                    echo -e "    ${YELLOW}Pending Modifications: Yes${NC}"
                    INSTANCES_WITH_PENDING_MODIFICATIONS=$((INSTANCES_WITH_PENDING_MODIFICATIONS + 1))
                fi

                INSTANCES_WITH_PENDING_ACTIONS=$((INSTANCES_WITH_PENDING_ACTIONS + 1))

                # Write to summary
                echo "  [$region] $DB_INSTANCE - Maintenance: ${PENDING_MAINT:-None} | Modifications: ${PENDING_MODS_TEXT:-None}" >> "$SUMMARY_FILE"
            else
                echo -e "  ${GREEN}✓${NC} $DB_INSTANCE - No pending actions"
            fi

            # Write to CSV
            echo "$region,\"$DB_INSTANCE\",\"$DB_ENGINE\",\"$DB_VERSION\",\"$DB_CLASS\",\"$DB_STATUS\",\"${PENDING_MAINT:-None}\",\"${PENDING_MODS_TEXT:-None}\"" >> "$OUTPUT_CSV"
        done
    fi

    echo ""
done

# Generate summary
cat >> "$SUMMARY_FILE" <<EOF

SUMMARY
========================================
Total regions checked: $TOTAL_REGIONS
Total RDS instances: $TOTAL_INSTANCES

Instances with pending actions: $INSTANCES_WITH_PENDING_ACTIONS
Instances with pending maintenance: $INSTANCES_WITH_PENDING_MAINTENANCE
Instances with pending modifications: $INSTANCES_WITH_PENDING_MODIFICATIONS

EOF

# Display summary
echo -e "${CYAN}==========================================${NC}"
echo -e "${CYAN}SUMMARY${NC}"
echo -e "${CYAN}==========================================${NC}"
echo "Total regions checked: $TOTAL_REGIONS"
echo "Total RDS instances: $TOTAL_INSTANCES"
echo ""

if [[ $INSTANCES_WITH_PENDING_ACTIONS -gt 0 ]]; then
    echo -e "${YELLOW}Instances with pending actions: $INSTANCES_WITH_PENDING_ACTIONS${NC}"
    echo -e "  Pending maintenance: $INSTANCES_WITH_PENDING_MAINTENANCE"
    echo -e "  Pending modifications: $INSTANCES_WITH_PENDING_MODIFICATIONS"
else
    echo -e "${GREEN}No instances with pending actions found!${NC}"
fi

echo ""
echo "Output files:"
echo "  Summary: $SUMMARY_FILE"
echo "  CSV:     $OUTPUT_CSV"
echo ""

echo -e "${CYAN}==========================================${NC}"
