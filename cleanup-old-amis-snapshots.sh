#!/bin/bash

# Script to cleanup AMIs older than 180 days and their associated snapshots
# Scans a single region for AMIs owned by the account, identifies those older than
# 180 days, deregisters them, and deletes associated EBS snapshots.

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
REGION="${AWS_REGION:-us-east-1}"
DRY_RUN="${DRY_RUN:-true}"
AGE_DAYS="${AGE_DAYS:-180}"
OUTPUT_CSV="old-amis-cleanup.csv"
SUMMARY_FILE="old-amis-cleanup-summary.txt"

# Counters
TOTAL_AMIS=0
OLD_AMIS=0
RECENT_AMIS=0
AMIS_DEREGISTERED=0
AMIS_FAILED=0
SNAPSHOTS_DELETED=0
SNAPSHOTS_FAILED=0

echo -e "${CYAN}==========================================${NC}"
echo -e "${CYAN}AMI and Snapshot Cleanup${NC}"
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

# Check if jq is installed (for JSON parsing)
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is not installed${NC}"
    echo "Please install jq for JSON parsing: https://stedolan.github.io/jq/"
    exit 1
fi

# Get Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "AWS Account ID: $ACCOUNT_ID"
echo "Region: $REGION"
echo "Age threshold: $AGE_DAYS days"

if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}DRY RUN MODE: No changes will be made${NC}"
fi

echo ""

# Calculate the cutoff date (180 days ago)
CUTOFF_DATE=$(date -u -d "$AGE_DAYS days ago" '+%Y-%m-%dT%H:%M:%S.000Z' 2>/dev/null || date -u -v-${AGE_DAYS}d '+%Y-%m-%dT%H:%M:%S.000Z' 2>/dev/null)

if [[ -z "$CUTOFF_DATE" ]]; then
    echo -e "${RED}Error: Unable to calculate cutoff date${NC}"
    echo "Your system's date command may not support the required options"
    exit 1
fi

echo "Cutoff date: $CUTOFF_DATE"
echo "AMIs created before this date will be targeted for cleanup"
echo ""

# Initialize CSV output
echo "AMI ID,AMI Name,Creation Date,Age (Days),State,Snapshot IDs,Action,Status" > "$OUTPUT_CSV"

# Initialize summary file
cat > "$SUMMARY_FILE" <<EOF
AMI and Snapshot Cleanup Summary
Generated: $(date)
Account: $ACCOUNT_ID
Region: $REGION
Age threshold: $AGE_DAYS days
Cutoff date: $CUTOFF_DATE
Dry Run: $DRY_RUN
========================================

EOF

# Function to calculate age in days
calculate_age_days() {
    local creation_date=$1
    local now_epoch=$(date +%s)
    local creation_epoch=$(date -d "$creation_date" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${creation_date%.*}" +%s 2>/dev/null)

    if [[ -z "$creation_epoch" ]]; then
        echo "0"
        return
    fi

    local age_seconds=$((now_epoch - creation_epoch))
    local age_days=$((age_seconds / 86400))
    echo "$age_days"
}

# Function to get snapshot IDs from AMI
get_ami_snapshots() {
    local ami_id=$1

    local snapshot_ids=$(aws ec2 describe-images \
        --region "$REGION" \
        --image-ids "$ami_id" \
        --query 'Images[0].BlockDeviceMappings[?Ebs.SnapshotId!=`null`].Ebs.SnapshotId' \
        --output text 2>/dev/null || echo "")

    echo "$snapshot_ids"
}

# Function to deregister AMI
deregister_ami() {
    local ami_id=$1
    local ami_name=$2

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "    ${YELLOW}[DRY RUN] Would deregister AMI: $ami_id${NC}"
        return 0
    fi

    local result=$(aws ec2 deregister-image \
        --region "$REGION" \
        --image-id "$ami_id" 2>&1)

    if [[ $? -eq 0 ]]; then
        echo -e "    ${GREEN}✓ Deregistered AMI: $ami_id${NC}"
        return 0
    else
        echo -e "    ${RED}✗ Failed to deregister AMI: $ami_id${NC}"
        echo "    Error: $result"
        return 1
    fi
}

# Function to delete snapshot
delete_snapshot() {
    local snapshot_id=$1

    if [[ "$DRY_RUN" == "true" ]]; then
        echo -e "      ${YELLOW}[DRY RUN] Would delete snapshot: $snapshot_id${NC}"
        return 0
    fi

    local result=$(aws ec2 delete-snapshot \
        --region "$REGION" \
        --snapshot-id "$snapshot_id" 2>&1)

    if [[ $? -eq 0 ]]; then
        echo -e "      ${GREEN}✓ Deleted snapshot: $snapshot_id${NC}"
        return 0
    else
        echo -e "      ${RED}✗ Failed to delete snapshot: $snapshot_id${NC}"
        echo "      Error: $result"
        return 1
    fi
}

# Get all AMIs owned by this account
echo "Fetching AMIs owned by account $ACCOUNT_ID in region $REGION..."
AMIS_JSON=$(aws ec2 describe-images \
    --region "$REGION" \
    --owners "$ACCOUNT_ID" \
    --query 'Images[*].[ImageId,Name,CreationDate,State]' \
    --output json)

TOTAL_AMIS=$(echo "$AMIS_JSON" | jq '. | length')

if [[ $TOTAL_AMIS -eq 0 ]]; then
    echo "No AMIs found owned by this account in $REGION"
    exit 0
fi

echo "Found $TOTAL_AMIS AMI(s) owned by this account"
echo ""

# Process each AMI
echo "Analyzing AMIs..."
echo ""

for i in $(seq 0 $((TOTAL_AMIS - 1))); do
    AMI_ID=$(echo "$AMIS_JSON" | jq -r ".[$i][0]")
    AMI_NAME=$(echo "$AMIS_JSON" | jq -r ".[$i][1]")
    CREATION_DATE=$(echo "$AMIS_JSON" | jq -r ".[$i][2]")
    AMI_STATE=$(echo "$AMIS_JSON" | jq -r ".[$i][3]")

    # Handle null AMI name
    if [[ "$AMI_NAME" == "null" ]]; then
        AMI_NAME="<unnamed>"
    fi

    # Calculate age
    AGE=$(calculate_age_days "$CREATION_DATE")

    echo -e "${BLUE}AMI: $AMI_ID${NC}"
    echo "  Name: $AMI_NAME"
    echo "  Created: $CREATION_DATE ($AGE days ago)"
    echo "  State: $AMI_STATE"

    # Check if AMI is older than threshold
    if [[ $AGE -ge $AGE_DAYS ]]; then
        OLD_AMIS=$((OLD_AMIS + 1))
        echo -e "  ${YELLOW}→ AMI is older than $AGE_DAYS days${NC}"

        # Get associated snapshots
        SNAPSHOT_IDS=$(get_ami_snapshots "$AMI_ID")
        SNAPSHOT_COUNT=0
        if [[ -n "$SNAPSHOT_IDS" ]]; then
            SNAPSHOT_COUNT=$(echo "$SNAPSHOT_IDS" | wc -w)
        fi

        echo "  Associated snapshots ($SNAPSHOT_COUNT): $SNAPSHOT_IDS"

        # Deregister AMI
        echo -e "  ${BLUE}Deregistering AMI...${NC}"
        if deregister_ami "$AMI_ID" "$AMI_NAME"; then
            AMIS_DEREGISTERED=$((AMIS_DEREGISTERED + 1))
            AMI_ACTION="Deregister"
            AMI_STATUS="Success"

            # Delete associated snapshots
            if [[ -n "$SNAPSHOT_IDS" ]]; then
                echo "  Deleting associated snapshots..."
                for snapshot_id in $SNAPSHOT_IDS; do
                    if delete_snapshot "$snapshot_id"; then
                        SNAPSHOTS_DELETED=$((SNAPSHOTS_DELETED + 1))
                    else
                        SNAPSHOTS_FAILED=$((SNAPSHOTS_FAILED + 1))
                    fi
                done
            fi
        else
            AMIS_FAILED=$((AMIS_FAILED + 1))
            AMI_ACTION="Deregister"
            AMI_STATUS="Failed"
        fi

        # Write to CSV
        SNAPSHOT_IDS_CSV=$(echo "$SNAPSHOT_IDS" | tr ' ' ';')
        echo "$AMI_ID,\"$AMI_NAME\",$CREATION_DATE,$AGE,$AMI_STATE,\"$SNAPSHOT_IDS_CSV\",$AMI_ACTION,$AMI_STATUS" >> "$OUTPUT_CSV"

        # Write to summary
        echo "  [OLD] $AMI_ID - $AMI_NAME ($AGE days) - $AMI_STATUS" >> "$SUMMARY_FILE"
    else
        RECENT_AMIS=$((RECENT_AMIS + 1))
        echo -e "  ${GREEN}→ AMI is recent (< $AGE_DAYS days)${NC}"
        echo "$AMI_ID,\"$AMI_NAME\",$CREATION_DATE,$AGE,$AMI_STATE,,Skip,Recent" >> "$OUTPUT_CSV"
    fi

    echo ""
done

# Generate summary
cat >> "$SUMMARY_FILE" <<EOF

SUMMARY
========================================
Total AMIs found: $TOTAL_AMIS
AMIs older than $AGE_DAYS days: $OLD_AMIS
Recent AMIs (< $AGE_DAYS days): $RECENT_AMIS

AMIs deregistered: $AMIS_DEREGISTERED
AMIs failed: $AMIS_FAILED

Snapshots deleted: $SNAPSHOTS_DELETED
Snapshots failed: $SNAPSHOTS_FAILED

EOF

# Display summary
echo -e "${CYAN}==========================================${NC}"
echo -e "${CYAN}SUMMARY${NC}"
echo -e "${CYAN}==========================================${NC}"
echo "Total AMIs found: $TOTAL_AMIS"
echo -e "AMIs older than $AGE_DAYS days: ${YELLOW}$OLD_AMIS${NC}"
echo -e "Recent AMIs (< $AGE_DAYS days): ${GREEN}$RECENT_AMIS${NC}"
echo ""
echo -e "AMIs deregistered: ${GREEN}$AMIS_DEREGISTERED${NC}"
if [[ $AMIS_FAILED -gt 0 ]]; then
    echo -e "AMIs failed: ${RED}$AMIS_FAILED${NC}"
fi
echo ""
echo -e "Snapshots deleted: ${GREEN}$SNAPSHOTS_DELETED${NC}"
if [[ $SNAPSHOTS_FAILED -gt 0 ]]; then
    echo -e "Snapshots failed: ${RED}$SNAPSHOTS_FAILED${NC}"
fi
echo ""
echo "Output files:"
echo "  Summary: $SUMMARY_FILE"
echo "  CSV:     $OUTPUT_CSV"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${BLUE}This was a dry run. No changes were made.${NC}"
    echo "Run with DRY_RUN=false to actually deregister AMIs and delete snapshots."
    echo ""
fi

if [[ $AMIS_DEREGISTERED -gt 0 || $SNAPSHOTS_DELETED -gt 0 ]]; then
    echo -e "${GREEN}✓ Cleanup complete!${NC}"
elif [[ $OLD_AMIS -eq 0 ]]; then
    echo -e "${GREEN}No old AMIs found. Nothing to clean up.${NC}"
elif [[ $AMIS_FAILED -gt 0 || $SNAPSHOTS_FAILED -gt 0 ]]; then
    echo -e "${RED}Some operations failed. Check the summary for details.${NC}"
    exit 1
fi

echo -e "${CYAN}==========================================${NC}"
