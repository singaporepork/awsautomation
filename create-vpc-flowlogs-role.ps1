#Requires -Version 5.0

<#
.SYNOPSIS
    Creates an IAM role for VPC Flow Logs to CloudWatch Logs

.DESCRIPTION
    This script creates an IAM role with the necessary trust policy and permissions
    for VPC Flow Logs to publish flow log data to CloudWatch Logs.
    Based on AWS documentation for VPC Flow Logs.

.PARAMETER RoleName
    Name of the IAM role to create (default: VPCFlowLogsRole)

.PARAMETER PolicyName
    Name of the inline policy to attach (default: VPCFlowLogsPolicy)

.PARAMETER Force
    Skip confirmation prompts when updating existing role

.EXAMPLE
    .\create-vpc-flowlogs-role.ps1

.EXAMPLE
    .\create-vpc-flowlogs-role.ps1 -RoleName "MyVPCFlowLogsRole"

.EXAMPLE
    .\create-vpc-flowlogs-role.ps1 -Force

.NOTES
    Requires AWS CLI to be installed and configured
    Compatible with PowerShell 5.0 and later
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$RoleName = "VPCFlowLogsRole",

    [Parameter()]
    [string]$PolicyName = "VPCFlowLogsPolicy",

    [Parameter()]
    [switch]$Force
)

# Set strict mode
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Description = "IAM role for VPC Flow Logs to publish to CloudWatch Logs"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "VPC Flow Logs IAM Role Setup" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Check if AWS CLI is installed
try {
    $null = Get-Command aws -ErrorAction Stop
} catch {
    Write-Host "Error: AWS CLI is not installed" -ForegroundColor Red
    Write-Host "Please install AWS CLI from: https://aws.amazon.com/cli/" -ForegroundColor Yellow
    exit 1
}

# Check AWS credentials
try {
    $null = aws sts get-caller-identity 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "AWS credentials check failed"
    }
} catch {
    Write-Host "Error: AWS credentials not configured or invalid" -ForegroundColor Red
    Write-Host "Please run 'aws configure' to set up your credentials" -ForegroundColor Yellow
    exit 1
}

# Get Account ID
$accountIdJson = aws sts get-caller-identity --query 'Account' --output json
$accountId = $accountIdJson | ConvertFrom-Json

Write-Host "AWS Account ID: $accountId"
Write-Host "IAM Role Name: $RoleName"
Write-Host ""

# Create trust policy document for VPC Flow Logs
Write-Host "Creating trust policy document..." -ForegroundColor White
$trustPolicy = @{
    Version = "2012-10-17"
    Statement = @(
        @{
            Effect = "Allow"
            Principal = @{
                Service = "vpc-flow-logs.amazonaws.com"
            }
            Action = "sts:AssumeRole"
        }
    )
} | ConvertTo-Json -Depth 10 -Compress

# Create permissions policy document
Write-Host "Creating permissions policy document..." -ForegroundColor White
$permissionsPolicy = @{
    Version = "2012-10-17"
    Statement = @(
        @{
            Effect = "Allow"
            Action = @(
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "logs:DescribeLogGroups",
                "logs:DescribeLogStreams"
            )
            Resource = "*"
        }
    )
} | ConvertTo-Json -Depth 10 -Compress

# Check if role already exists
Write-Host "Checking if IAM role already exists..." -ForegroundColor White
try {
    $null = aws iam get-role --role-name $RoleName 2>&1
    $roleExists = ($LASTEXITCODE -eq 0)
} catch {
    $roleExists = $false
}

if ($roleExists) {
    Write-Host "Warning: IAM role '$RoleName' already exists" -ForegroundColor Yellow

    if (-not $Force) {
        $response = Read-Host "Do you want to update the existing role? (y/n)"
        if ($response -notmatch '^[Yy]') {
            Write-Host "Exiting without changes"
            exit 0
        }
    }

    Write-Host "Updating existing role..." -ForegroundColor White

    # Update trust policy
    Write-Host "Updating trust policy..." -ForegroundColor White
    $null = aws iam update-assume-role-policy `
        --role-name $RoleName `
        --policy-document $trustPolicy 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ Trust policy updated" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Failed to update trust policy" -ForegroundColor Red
        exit 1
    }

} else {
    # Create new IAM role
    Write-Host "Creating IAM role: $RoleName..." -ForegroundColor White

    $null = aws iam create-role `
        --role-name $RoleName `
        --assume-role-policy-document $trustPolicy `
        --description $Description `
        --tags Key=Purpose,Value=VPCFlowLogs Key=ManagedBy,Value=Script 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  ✓ IAM role created" -ForegroundColor Green
    } else {
        Write-Host "  ✗ Failed to create IAM role" -ForegroundColor Red
        exit 1
    }
}

# Check if inline policy already exists
Write-Host "Checking for existing inline policy..." -ForegroundColor White
try {
    $null = aws iam get-role-policy --role-name $RoleName --policy-name $PolicyName 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Updating existing inline policy..." -ForegroundColor White
    }
} catch {
    Write-Host "Creating inline policy..." -ForegroundColor White
}

# Put/Update inline policy
$null = aws iam put-role-policy `
    --role-name $RoleName `
    --policy-name $PolicyName `
    --policy-document $permissionsPolicy 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "  ✓ Permissions policy attached" -ForegroundColor Green
} else {
    Write-Host "  ✗ Failed to attach permissions policy" -ForegroundColor Red
    exit 1
}

# Get role ARN
$roleArnJson = aws iam get-role --role-name $RoleName --query 'Role.Arn' --output json
$roleArn = $roleArnJson | ConvertFrom-Json

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Setup Complete!" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Role Details:"
Write-Host "  Role Name: $RoleName"
Write-Host "  Role ARN:  $roleArn"
Write-Host ""
Write-Host "Next Steps:" -ForegroundColor Blue
Write-Host "1. Create a CloudWatch Logs log group (if not already created):"
Write-Host "   aws logs create-log-group --log-group-name /aws/vpc/flowlogs"
Write-Host ""
Write-Host "2. Enable VPC Flow Logs using this role:"
Write-Host "   For a VPC:"
Write-Host "   aws ec2 create-flow-logs \"
Write-Host "     --resource-type VPC \"
Write-Host "     --resource-ids vpc-xxxxxxxx \"
Write-Host "     --traffic-type ALL \"
Write-Host "     --log-destination-type cloud-watch-logs \"
Write-Host "     --log-group-name /aws/vpc/flowlogs \"
Write-Host "     --deliver-logs-permission-arn $roleArn"
Write-Host ""
Write-Host "   For a subnet:"
Write-Host "   aws ec2 create-flow-logs \"
Write-Host "     --resource-type Subnet \"
Write-Host "     --resource-ids subnet-xxxxxxxx \"
Write-Host "     --traffic-type ALL \"
Write-Host "     --log-destination-type cloud-watch-logs \"
Write-Host "     --log-group-name /aws/vpc/flowlogs \"
Write-Host "     --deliver-logs-permission-arn $roleArn"
Write-Host ""
Write-Host "   For a network interface:"
Write-Host "   aws ec2 create-flow-logs \"
Write-Host "     --resource-type NetworkInterface \"
Write-Host "     --resource-ids eni-xxxxxxxx \"
Write-Host "     --traffic-type ALL \"
Write-Host "     --log-destination-type cloud-watch-logs \"
Write-Host "     --log-group-name /aws/vpc/flowlogs \"
Write-Host "     --deliver-logs-permission-arn $roleArn"
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "IAM role for VPC Flow Logs is ready to use!" -ForegroundColor Green
