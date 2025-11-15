#!/bin/bash

# Script to identify IAM users without the IAMUserChangePassword policy
# This checks both direct policy attachments and group membership policies

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Output files
USERS_WITHOUT_POLICY="users_without_change_password_policy.txt"
DETAILED_REPORT="iam_password_policy_audit_report.txt"

echo "=========================================="
echo "IAM Password Policy Audit"
echo "=========================================="
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
> "$USERS_WITHOUT_POLICY"
> "$DETAILED_REPORT"

echo "IAM Password Policy Audit Report" >> "$DETAILED_REPORT"
echo "Generated: $(date)" >> "$DETAILED_REPORT"
echo "========================================" >> "$DETAILED_REPORT"
echo "" >> "$DETAILED_REPORT"

USERS_WITHOUT_POLICY_COUNT=0

# Function to check if a policy grants iam:ChangePassword permission
check_policy_for_change_password() {
    local policy_arn=$1

    # Get the default policy version
    default_version=$(aws iam get-policy --policy-arn "$policy_arn" --query 'Policy.DefaultVersionId' --output text 2>/dev/null || echo "")

    if [ -z "$default_version" ]; then
        return 1
    fi

    # Get the policy document
    policy_doc=$(aws iam get-policy-version --policy-arn "$policy_arn" --version-id "$default_version" --query 'PolicyVersion.Document' --output json 2>/dev/null || echo "")

    if [ -z "$policy_doc" ]; then
        return 1
    fi

    # Check if the policy contains iam:ChangePassword or iam:*
    if echo "$policy_doc" | jq -e '.Statement[] | select(.Effect == "Allow") | select(.Action | if type == "array" then . else [.] end | .[] | test("^(iam:ChangePassword|iam:\\*|\\*)$"))' &> /dev/null; then
        return 0
    fi

    return 1
}

# Function to check inline policy for change password permission
check_inline_policy_for_change_password() {
    local policy_doc=$1

    # Check if the policy contains iam:ChangePassword or iam:*
    if echo "$policy_doc" | jq -e '.Statement[] | select(.Effect == "Allow") | select(.Action | if type == "array" then . else [.] end | .[] | test("^(iam:ChangePassword|iam:\\*|\\*)$"))' &> /dev/null; then
        return 0
    fi

    return 1
}

# Function to check if user has change password permission
user_has_change_password_permission() {
    local username=$1
    local has_permission=0

    # Check directly attached managed policies
    attached_policies=$(aws iam list-attached-user-policies --user-name "$username" --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null || echo "")

    for policy_arn in $attached_policies; do
        if [ "$policy_arn" == "arn:aws:iam::aws:policy/IAMUserChangePassword" ]; then
            echo "  ✓ Has IAMUserChangePassword policy attached directly" >> "$DETAILED_REPORT"
            has_permission=1
            break
        fi

        if check_policy_for_change_password "$policy_arn"; then
            echo "  ✓ Has iam:ChangePassword permission via policy: $policy_arn" >> "$DETAILED_REPORT"
            has_permission=1
            break
        fi
    done

    # Check inline policies
    if [ $has_permission -eq 0 ]; then
        inline_policies=$(aws iam list-user-policies --user-name "$username" --query 'PolicyNames[*]' --output text 2>/dev/null || echo "")

        for policy_name in $inline_policies; do
            policy_doc=$(aws iam get-user-policy --user-name "$username" --policy-name "$policy_name" --query 'PolicyDocument' --output json 2>/dev/null || echo "")

            if [ -n "$policy_doc" ] && check_inline_policy_for_change_password "$policy_doc"; then
                echo "  ✓ Has iam:ChangePassword permission via inline policy: $policy_name" >> "$DETAILED_REPORT"
                has_permission=1
                break
            fi
        done
    fi

    # Check group memberships
    if [ $has_permission -eq 0 ]; then
        groups=$(aws iam list-groups-for-user --user-name "$username" --query 'Groups[*].GroupName' --output text 2>/dev/null || echo "")

        for group in $groups; do
            # Check group's attached managed policies
            group_attached_policies=$(aws iam list-attached-group-policies --group-name "$group" --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null || echo "")

            for policy_arn in $group_attached_policies; do
                if [ "$policy_arn" == "arn:aws:iam::aws:policy/IAMUserChangePassword" ]; then
                    echo "  ✓ Has IAMUserChangePassword policy via group: $group" >> "$DETAILED_REPORT"
                    has_permission=1
                    break 2
                fi

                if check_policy_for_change_password "$policy_arn"; then
                    echo "  ✓ Has iam:ChangePassword permission via group '$group' policy: $policy_arn" >> "$DETAILED_REPORT"
                    has_permission=1
                    break 2
                fi
            done

            # Check group's inline policies
            if [ $has_permission -eq 0 ]; then
                group_inline_policies=$(aws iam list-group-policies --group-name "$group" --query 'PolicyNames[*]' --output text 2>/dev/null || echo "")

                for policy_name in $group_inline_policies; do
                    policy_doc=$(aws iam get-group-policy --group-name "$group" --policy-name "$policy_name" --query 'PolicyDocument' --output json 2>/dev/null || echo "")

                    if [ -n "$policy_doc" ] && check_inline_policy_for_change_password "$policy_doc"; then
                        echo "  ✓ Has iam:ChangePassword permission via group '$group' inline policy: $policy_name" >> "$DETAILED_REPORT"
                        has_permission=1
                        break 2
                    fi
                done
            fi
        done
    fi

    return $((1 - has_permission))
}

# Process each user
for username in $USERS; do
    echo "Checking user: $username" >> "$DETAILED_REPORT"

    if user_has_change_password_permission "$username"; then
        echo -e "${GREEN}✓${NC} $username - Has change password permission"
    else
        echo -e "${RED}✗${NC} $username - Missing change password permission"
        echo "  ✗ Does NOT have iam:ChangePassword permission" >> "$DETAILED_REPORT"
        echo "$username" >> "$USERS_WITHOUT_POLICY"
        USERS_WITHOUT_POLICY_COUNT=$((USERS_WITHOUT_POLICY_COUNT + 1))
    fi

    echo "" >> "$DETAILED_REPORT"
done

# Summary
echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo "Total users: $USER_COUNT"
echo -e "${GREEN}Users with change password permission: $((USER_COUNT - USERS_WITHOUT_POLICY_COUNT))${NC}"
echo -e "${RED}Users without change password permission: $USERS_WITHOUT_POLICY_COUNT${NC}"
echo ""

if [ $USERS_WITHOUT_POLICY_COUNT -gt 0 ]; then
    echo -e "${YELLOW}Users without IAMUserChangePassword policy:${NC}"
    cat "$USERS_WITHOUT_POLICY"
    echo ""
fi

echo "Detailed report saved to: $DETAILED_REPORT"
echo "Users without policy saved to: $USERS_WITHOUT_POLICY"
