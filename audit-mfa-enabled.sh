#!/bin/bash

# Script to identify IAM users without MFA (Multi-Factor Authentication) enabled
# Helps maintain security by identifying users with inadequate authentication protection

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Output files
OUTPUT_FILE="users_without_mfa_report.txt"
CSV_FILE="users_without_mfa.csv"

echo "=========================================="
echo "IAM MFA Audit"
echo "=========================================="
echo "Identifying users without MFA enabled"
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
echo "IAM MFA Audit Report" > "$OUTPUT_FILE"
echo "Generated: $(date)" >> "$OUTPUT_FILE"
echo "Identifying users without MFA enabled" >> "$OUTPUT_FILE"
echo "==========================================" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Initialize CSV file
echo "UserName,MFA Enabled,MFA Device Count,Device ARNs" > "$CSV_FILE"

USERS_WITHOUT_MFA=0
USERS_WITH_MFA=0

# Process each user
for username in $USERS; do
    echo "Checking user: $username" >> "$OUTPUT_FILE"

    # Get MFA devices for the user
    mfa_devices=$(aws iam list-mfa-devices --user-name "$username" --query 'MFADevices[*].SerialNumber' --output text 2>/dev/null || echo "")

    if [ -z "$mfa_devices" ]; then
        # No MFA devices found
        USERS_WITHOUT_MFA=$((USERS_WITHOUT_MFA + 1))
        echo "  ✗ MFA: Not enabled" >> "$OUTPUT_FILE"
        echo -e "${RED}✗${NC} $username - MFA not enabled"

        # Add to CSV
        echo "$username,No,0,None" >> "$CSV_FILE"
    else
        # MFA devices found
        USERS_WITH_MFA=$((USERS_WITH_MFA + 1))
        device_count=$(echo "$mfa_devices" | wc -w)

        echo "  ✓ MFA: Enabled ($device_count device(s))" >> "$OUTPUT_FILE"

        # List each device
        for device in $mfa_devices; do
            echo "    - Device: $device" >> "$OUTPUT_FILE"
        done

        echo -e "${GREEN}✓${NC} $username - MFA enabled ($device_count device(s))"

        # Add to CSV (replace spaces with semicolons for multiple devices)
        device_list=$(echo "$mfa_devices" | tr ' ' ';')
        echo "$username,Yes,$device_count,$device_list" >> "$CSV_FILE"
    fi

    echo "" >> "$OUTPUT_FILE"
done

# Summary
echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo "Total users checked: $USER_COUNT"
echo ""
echo -e "${GREEN}Users with MFA enabled: $USERS_WITH_MFA${NC}"
echo -e "${RED}Users without MFA enabled: $USERS_WITHOUT_MFA${NC}"
echo ""

if [ $USERS_WITHOUT_MFA -gt 0 ]; then
    echo -e "${YELLOW}WARNING: Found $USERS_WITHOUT_MFA user(s) without MFA enabled${NC}"
    echo -e "${YELLOW}These users should enable MFA to enhance account security${NC}"
    echo ""

    echo -e "${YELLOW}Users without MFA:${NC}"
    grep ",No," "$CSV_FILE" | cut -d',' -f1 | grep -v "^UserName$" | while read -r user; do
        echo -e "  ${RED}✗${NC} $user"
    done
    echo ""
fi

echo "Detailed report saved to: $OUTPUT_FILE"
echo "CSV export saved to: $CSV_FILE"
echo ""
echo -e "${BLUE}Recommendation:${NC} Enable MFA for all users, especially those with console access"
echo -e "${BLUE}MFA adds an extra layer of security:${NC} Even if passwords are compromised, accounts remain protected"
