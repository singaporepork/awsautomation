#!/bin/bash

# Script to identify IAM users with access keys older than 365 days
# Helps maintain security by identifying potentially stale credentials

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
MAX_AGE_DAYS=365
OUTPUT_FILE="old_access_keys_report.txt"
CSV_FILE="old_access_keys.csv"

echo "=========================================="
echo "IAM Access Keys Age Audit"
echo "=========================================="
echo "Checking for access keys older than $MAX_AGE_DAYS days"
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

echo "Fetching IAM users..."
USERS=$(aws iam list-users --query 'Users[*].UserName' --output text)

if [ -z "$USERS" ]; then
    echo -e "${YELLOW}No IAM users found${NC}"
    exit 0
fi

USER_COUNT=$(echo "$USERS" | wc -w)
echo "Found $USER_COUNT IAM users"
echo ""

# Initialize output files
echo "IAM Access Keys Age Audit Report" > "$OUTPUT_FILE"
echo "Generated: $(date)" >> "$OUTPUT_FILE"
echo "Checking for access keys older than $MAX_AGE_DAYS days" >> "$OUTPUT_FILE"
echo "==========================================" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Initialize CSV file
echo "UserName,AccessKeyId,Status,Age (Days),Created Date" > "$CSV_FILE"

# Get current date in seconds since epoch
CURRENT_DATE=$(date +%s)

OLD_KEYS_COUNT=0
TOTAL_KEYS_COUNT=0
USERS_WITH_OLD_KEYS=0

# Function to calculate age in days
calculate_age_days() {
    local create_date=$1
    local create_date_seconds

    # Convert ISO 8601 date to seconds since epoch
    create_date_seconds=$(date -d "$create_date" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${create_date%%+*}" +%s 2>/dev/null || echo "0")

    if [ "$create_date_seconds" -eq 0 ]; then
        echo "0"
        return
    fi

    local age_seconds=$((CURRENT_DATE - create_date_seconds))
    local age_days=$((age_seconds / 86400))

    echo "$age_days"
}

# Process each user
for username in $USERS; do
    echo "Checking user: $username" >> "$OUTPUT_FILE"

    # Get access keys for the user
    access_keys=$(aws iam list-access-keys --user-name "$username" --query 'AccessKeyMetadata[*].[AccessKeyId,Status,CreateDate]' --output text 2>/dev/null || echo "")

    if [ -z "$access_keys" ]; then
        echo "  No access keys" >> "$OUTPUT_FILE"
        echo -e "${BLUE}○${NC} $username - No access keys"
        echo "" >> "$OUTPUT_FILE"
        continue
    fi

    user_has_old_key=false

    while IFS=$'\t' read -r key_id status create_date; do
        [ -z "$key_id" ] && continue

        TOTAL_KEYS_COUNT=$((TOTAL_KEYS_COUNT + 1))

        # Calculate age in days
        age_days=$(calculate_age_days "$create_date")

        # Format create date for display
        create_date_formatted=$(date -d "$create_date" "+%Y-%m-%d" 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%S" "${create_date%%+*}" "+%Y-%m-%d" 2>/dev/null || echo "$create_date")

        if [ "$age_days" -gt "$MAX_AGE_DAYS" ]; then
            OLD_KEYS_COUNT=$((OLD_KEYS_COUNT + 1))
            user_has_old_key=true

            echo "  ✗ Access Key: $key_id" >> "$OUTPUT_FILE"
            echo "    Status: $status" >> "$OUTPUT_FILE"
            echo "    Age: $age_days days" >> "$OUTPUT_FILE"
            echo "    Created: $create_date_formatted" >> "$OUTPUT_FILE"

            # Add to CSV
            echo "$username,$key_id,$status,$age_days,$create_date_formatted" >> "$CSV_FILE"
        else
            echo "  ✓ Access Key: $key_id (Age: $age_days days)" >> "$OUTPUT_FILE"
        fi
    done <<< "$access_keys"

    if [ "$user_has_old_key" = true ]; then
        USERS_WITH_OLD_KEYS=$((USERS_WITH_OLD_KEYS + 1))
        echo -e "${RED}✗${NC} $username - Has access key(s) older than $MAX_AGE_DAYS days"
    else
        echo -e "${GREEN}✓${NC} $username - All access keys are within acceptable age"
    fi

    echo "" >> "$OUTPUT_FILE"
done

# Summary
echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo "Total users checked: $USER_COUNT"
echo "Total access keys found: $TOTAL_KEYS_COUNT"
echo ""
echo -e "${GREEN}Access keys within $MAX_AGE_DAYS days: $((TOTAL_KEYS_COUNT - OLD_KEYS_COUNT))${NC}"
echo -e "${RED}Access keys older than $MAX_AGE_DAYS days: $OLD_KEYS_COUNT${NC}"
echo -e "${RED}Users with old access keys: $USERS_WITH_OLD_KEYS${NC}"
echo ""

if [ $OLD_KEYS_COUNT -gt 0 ]; then
    echo -e "${YELLOW}WARNING: Found $OLD_KEYS_COUNT access key(s) older than $MAX_AGE_DAYS days${NC}"
    echo -e "${YELLOW}These keys should be rotated as part of security best practices${NC}"
    echo ""
fi

echo "Detailed report saved to: $OUTPUT_FILE"
echo "CSV export saved to: $CSV_FILE"
echo ""
echo -e "${BLUE}Recommendation:${NC} Rotate access keys at least every 90 days"
echo -e "${BLUE}To rotate:${NC} Create new key, update applications, then delete old key"
