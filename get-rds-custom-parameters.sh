#!/bin/bash

# Script to identify custom parameters in an RDS parameter group
# Takes region and parameter group name as arguments
# Filters out system parameters and shows custom parameter values with defaults

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to display usage
usage() {
    echo "Usage: $0 <region> <parameter-group-name>"
    echo ""
    echo "Arguments:"
    echo "  region               AWS region (e.g., us-east-1)"
    echo "  parameter-group-name Name of the RDS parameter group"
    echo ""
    echo "Example:"
    echo "  $0 us-east-1 my-custom-params"
    exit 1
}

# Check arguments
if [[ $# -ne 2 ]]; then
    usage
fi

REGION=$1
PARAM_GROUP=$2

echo -e "${CYAN}==========================================${NC}"
echo -e "${CYAN}RDS Custom Parameters Report${NC}"
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
    echo -e "${RED}Error: jq is required for this script${NC}"
    echo "Please install jq: https://stedolan.github.io/jq/"
    exit 1
fi

# Get Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
echo "AWS Account ID: $ACCOUNT_ID"
echo "Region: $REGION"
echo "Parameter Group: $PARAM_GROUP"
echo "Report Date: $(date)"
echo ""

# Verify the parameter group exists
echo "Verifying parameter group..."
if ! aws rds describe-db-parameter-groups \
    --region "$REGION" \
    --db-parameter-group-name "$PARAM_GROUP" \
    --output json &> /dev/null; then
    echo -e "${RED}Error: Parameter group '$PARAM_GROUP' not found in region '$REGION'${NC}"
    exit 1
fi

# Get parameter group details
PARAM_GROUP_DETAILS=$(aws rds describe-db-parameter-groups \
    --region "$REGION" \
    --db-parameter-group-name "$PARAM_GROUP" \
    --output json)

PARAM_FAMILY=$(echo "$PARAM_GROUP_DETAILS" | jq -r '.DBParameterGroups[0].DBParameterGroupFamily')
DESCRIPTION=$(echo "$PARAM_GROUP_DETAILS" | jq -r '.DBParameterGroups[0].Description')

echo -e "${GREEN}✓${NC} Parameter group found"
echo "  Family: $PARAM_FAMILY"
echo "  Description: $DESCRIPTION"
echo ""

# Get all parameters from the parameter group
echo "Fetching parameters..."
PARAMS_JSON=$(aws rds describe-db-parameters \
    --region "$REGION" \
    --db-parameter-group-name "$PARAM_GROUP" \
    --output json)

TOTAL_PARAMS=$(echo "$PARAMS_JSON" | jq '.Parameters | length')
echo -e "${GREEN}✓${NC} Retrieved $TOTAL_PARAMS total parameters"
echo ""

# Filter for custom parameters (excluding source=system)
CUSTOM_PARAMS=$(echo "$PARAMS_JSON" | jq '[.Parameters[] | select(.Source != "system")]')
CUSTOM_COUNT=$(echo "$CUSTOM_PARAMS" | jq 'length')

if [[ $CUSTOM_COUNT -eq 0 ]]; then
    echo -e "${YELLOW}No custom parameters found (all parameters are using system/default values)${NC}"
    exit 0
fi

echo -e "${CYAN}Found $CUSTOM_COUNT custom parameter(s):${NC}"
echo ""

# Get the default parameter group for comparison
DEFAULT_PARAM_GROUP="default.${PARAM_FAMILY}"
echo "Attempting to fetch default values from '$DEFAULT_PARAM_GROUP'..."

DEFAULT_PARAMS_JSON=""
if aws rds describe-db-parameters \
    --region "$REGION" \
    --db-parameter-group-name "$DEFAULT_PARAM_GROUP" \
    --output json &> /dev/null; then
    DEFAULT_PARAMS_JSON=$(aws rds describe-db-parameters \
        --region "$REGION" \
        --db-parameter-group-name "$DEFAULT_PARAM_GROUP" \
        --output json)
    echo -e "${GREEN}✓${NC} Default parameter group values retrieved"
else
    echo -e "${YELLOW}⚠${NC} Could not retrieve default parameter group (will show allowed values instead)"
fi
echo ""

# Display custom parameters
echo -e "${CYAN}==========================================${NC}"
echo -e "${CYAN}CUSTOM PARAMETERS${NC}"
echo -e "${CYAN}==========================================${NC}"
echo ""

for i in $(seq 0 $((CUSTOM_COUNT - 1))); do
    PARAM=$(echo "$CUSTOM_PARAMS" | jq -r ".[$i]")

    PARAM_NAME=$(echo "$PARAM" | jq -r '.ParameterName')
    PARAM_VALUE=$(echo "$PARAM" | jq -r '.ParameterValue // "N/A"')
    PARAM_SOURCE=$(echo "$PARAM" | jq -r '.Source')
    PARAM_TYPE=$(echo "$PARAM" | jq -r '.DataType')
    PARAM_DESC=$(echo "$PARAM" | jq -r '.Description // "No description"')
    PARAM_MODIFIABLE=$(echo "$PARAM" | jq -r '.IsModifiable')
    PARAM_APPLY_TYPE=$(echo "$PARAM" | jq -r '.ApplyType // "N/A"')
    ALLOWED_VALUES=$(echo "$PARAM" | jq -r '.AllowedValues // "N/A"')

    echo -e "${YELLOW}[$((i + 1))/$CUSTOM_COUNT] $PARAM_NAME${NC}"
    echo "  Current Value: ${GREEN}$PARAM_VALUE${NC}"
    echo "  Source: $PARAM_SOURCE"
    echo "  Data Type: $PARAM_TYPE"
    echo "  Modifiable: $PARAM_MODIFIABLE"
    echo "  Apply Type: $PARAM_APPLY_TYPE"

    # Try to get default value
    if [[ -n "$DEFAULT_PARAMS_JSON" ]]; then
        DEFAULT_VALUE=$(echo "$DEFAULT_PARAMS_JSON" | jq -r --arg name "$PARAM_NAME" \
            '.Parameters[] | select(.ParameterName == $name) | .ParameterValue // "N/A"')

        if [[ -n "$DEFAULT_VALUE" ]] && [[ "$DEFAULT_VALUE" != "N/A" ]]; then
            if [[ "$DEFAULT_VALUE" == "$PARAM_VALUE" ]]; then
                echo "  Default Value: $DEFAULT_VALUE ${CYAN}(matches current)${NC}"
            else
                echo "  Default Value: ${BLUE}$DEFAULT_VALUE${NC}"
            fi
        else
            echo "  Default Value: Not available"
        fi
    fi

    # Show allowed values if available
    if [[ "$ALLOWED_VALUES" != "N/A" ]] && [[ ${#ALLOWED_VALUES} -lt 200 ]]; then
        echo "  Allowed Values: $ALLOWED_VALUES"
    fi

    # Show description
    echo "  Description: $PARAM_DESC"
    echo ""
done

# Summary
echo -e "${CYAN}==========================================${NC}"
echo -e "${CYAN}SUMMARY${NC}"
echo -e "${CYAN}==========================================${NC}"
echo "Total parameters: $TOTAL_PARAMS"
echo "Custom parameters: $CUSTOM_COUNT"
echo "System parameters: $((TOTAL_PARAMS - CUSTOM_COUNT))"
echo ""

# Create CSV output
OUTPUT_CSV="rds-custom-params-${PARAM_GROUP}-${REGION}.csv"
echo "Generating CSV report: $OUTPUT_CSV"

echo "Parameter Name,Current Value,Default Value,Source,Data Type,Modifiable,Apply Type,Description" > "$OUTPUT_CSV"

for i in $(seq 0 $((CUSTOM_COUNT - 1))); do
    PARAM=$(echo "$CUSTOM_PARAMS" | jq -r ".[$i]")

    PARAM_NAME=$(echo "$PARAM" | jq -r '.ParameterName')
    PARAM_VALUE=$(echo "$PARAM" | jq -r '.ParameterValue // "N/A"')
    PARAM_SOURCE=$(echo "$PARAM" | jq -r '.Source')
    PARAM_TYPE=$(echo "$PARAM" | jq -r '.DataType')
    PARAM_DESC=$(echo "$PARAM" | jq -r '.Description // "No description"' | sed 's/"/""/g')
    PARAM_MODIFIABLE=$(echo "$PARAM" | jq -r '.IsModifiable')
    PARAM_APPLY_TYPE=$(echo "$PARAM" | jq -r '.ApplyType // "N/A"')

    # Get default value
    DEFAULT_VALUE="N/A"
    if [[ -n "$DEFAULT_PARAMS_JSON" ]]; then
        DEFAULT_VALUE=$(echo "$DEFAULT_PARAMS_JSON" | jq -r --arg name "$PARAM_NAME" \
            '.Parameters[] | select(.ParameterName == $name) | .ParameterValue // "N/A"')
    fi

    echo "\"$PARAM_NAME\",\"$PARAM_VALUE\",\"$DEFAULT_VALUE\",\"$PARAM_SOURCE\",\"$PARAM_TYPE\",\"$PARAM_MODIFIABLE\",\"$PARAM_APPLY_TYPE\",\"$PARAM_DESC\"" >> "$OUTPUT_CSV"
done

echo -e "${GREEN}✓${NC} CSV report saved to: $OUTPUT_CSV"
echo ""
echo -e "${CYAN}==========================================${NC}"
