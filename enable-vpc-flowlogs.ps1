#Requires -Version 5.0

<#
.SYNOPSIS
    Enables VPC Flow Logs on all VPCs in all AWS regions

.DESCRIPTION
    This script automatically enables VPC Flow Logs on all VPCs across all AWS regions.
    It creates CloudWatch Log Groups as needed and configures flow logs with the
    specified IAM role and traffic type.

.PARAMETER RoleArn
    ARN of the IAM role for VPC Flow Logs (default: arn:aws:iam::ACCOUNT:role/VPCFlowLogsRole)

.PARAMETER LogGroupPrefix
    CloudWatch Logs log group prefix (default: /aws/vpc/flowlogs)

.PARAMETER TrafficType
    Type of traffic to log: ALL, ACCEPT, or REJECT (default: ALL)

.PARAMETER DryRun
    Preview changes without actually enabling flow logs

.EXAMPLE
    .\enable-vpc-flowlogs.ps1

.EXAMPLE
    .\enable-vpc-flowlogs.ps1 -TrafficType REJECT

.EXAMPLE
    .\enable-vpc-flowlogs.ps1 -DryRun

.EXAMPLE
    .\enable-vpc-flowlogs.ps1 -RoleArn "arn:aws:iam::123456789012:role/MyFlowLogsRole"

.NOTES
    Requires AWS CLI to be installed and configured
    Compatible with PowerShell 5.0 and later
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$RoleArn = "",

    [Parameter()]
    [string]$LogGroupPrefix = "/aws/vpc/flowlogs",

    [Parameter()]
    [ValidateSet("ALL", "ACCEPT", "REJECT")]
    [string]$TrafficType = "ALL",

    [Parameter()]
    [switch]$DryRun
)

# Set strict mode
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Output files
$SummaryFile = "vpc-flowlogs-enablement-summary.txt"
$CsvOutput = "vpc-flowlogs-enablement.csv"

# Counters
$TotalVpcs = 0
$EnabledVpcs = 0
$AlreadyEnabledVpcs = 0
$FailedVpcs = 0
$TotalRegions = 0

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "VPC Flow Logs Enablement" -ForegroundColor Cyan
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

# Get or validate IAM role ARN
if ([string]::IsNullOrEmpty($RoleArn)) {
    Write-Host "No IAM role ARN provided. Checking for default VPCFlowLogsRole..." -ForegroundColor White

    try {
        $null = aws iam get-role --role-name VPCFlowLogsRole 2>&1
        if ($LASTEXITCODE -eq 0) {
            $RoleArn = "arn:aws:iam::${accountId}:role/VPCFlowLogsRole"
            Write-Host "Using role: $RoleArn"
        } else {
            throw "Role not found"
        }
    } catch {
        Write-Host "Error: No IAM role found" -ForegroundColor Red
        Write-Host ""
        Write-Host "Please either:"
        Write-Host "  1. Run create-vpc-flowlogs-role.ps1 to create the role"
        Write-Host "  2. Specify -RoleArn parameter with your role ARN:"
        Write-Host "     .\enable-vpc-flowlogs.ps1 -RoleArn 'arn:aws:iam::$accountId:role/YourRoleName'"
        exit 1
    }
} else {
    Write-Host "Using role: $RoleArn"
}

Write-Host "Log Group Prefix: $LogGroupPrefix"
Write-Host "Traffic Type: $TrafficType"

if ($DryRun) {
    Write-Host "DRY RUN MODE: No changes will be made" -ForegroundColor Yellow
}

Write-Host ""

# Initialize CSV output
"Region,VPC ID,VPC Name,Status,Flow Log ID,Message" | Out-File -FilePath $CsvOutput -Encoding UTF8

# Initialize summary file
@"
VPC Flow Logs Enablement Summary
Generated: $(Get-Date)
Account: $accountId
IAM Role: $RoleArn
Traffic Type: $TrafficType
Dry Run: $DryRun
========================================

"@ | Out-File -FilePath $SummaryFile -Encoding UTF8

# Function to get VPC name from tags
function Get-VpcName {
    param(
        [string]$Region,
        [string]$VpcId
    )

    try {
        $vpcNameJson = aws ec2 describe-vpcs `
            --region $Region `
            --vpc-ids $VpcId `
            --query 'Vpcs[0].Tags[?Key==`Name`].Value' `
            --output json 2>&1

        if ($LASTEXITCODE -eq 0) {
            $vpcName = $vpcNameJson | ConvertFrom-Json
            if ($vpcName -and $vpcName.Count -gt 0) {
                return $vpcName[0]
            }
        }
    } catch {
        # Ignore errors
    }

    return "Unnamed"
}

# Function to check if flow logs are already enabled
function Test-ExistingFlowLogs {
    param(
        [string]$Region,
        [string]$VpcId
    )

    try {
        $flowLogsJson = aws ec2 describe-flow-logs `
            --region $Region `
            --filter "Name=resource-id,Values=$VpcId" `
            --query 'FlowLogs[?FlowLogStatus==`ACTIVE`].FlowLogId' `
            --output json 2>&1

        if ($LASTEXITCODE -eq 0) {
            $flowLogs = $flowLogsJson | ConvertFrom-Json
            if ($flowLogs -and $flowLogs.Count -gt 0) {
                return ($flowLogs -join ", ")
            }
        }
    } catch {
        # Ignore errors
    }

    return $null
}

# Function to create log group if it doesn't exist
function New-LogGroupIfNotExists {
    param(
        [string]$Region,
        [string]$LogGroup
    )

    try {
        $existingJson = aws logs describe-log-groups `
            --region $Region `
            --log-group-name-prefix $LogGroup `
            --query "logGroups[?logGroupName=='$LogGroup'].logGroupName" `
            --output json 2>&1

        if ($LASTEXITCODE -eq 0) {
            $existing = $existingJson | ConvertFrom-Json
            if ($existing -and $existing.Count -gt 0) {
                return $true
            }
        }
    } catch {
        # Log group doesn't exist, will create
    }

    if (-not $script:DryRun) {
        try {
            $null = aws logs create-log-group `
                --region $Region `
                --log-group-name $LogGroup 2>&1

            return ($LASTEXITCODE -eq 0)
        } catch {
            return $false
        }
    }

    return $true
}

# Function to enable flow logs for a VPC
function Enable-VpcFlowLogs {
    param(
        [string]$Region,
        [string]$VpcId,
        [string]$VpcName,
        [string]$LogGroup
    )

    Write-Host "  Enabling flow logs... " -NoNewline

    if ($script:DryRun) {
        Write-Host "(dry run - skipped)" -ForegroundColor Blue
        "$Region,$VpcId,$VpcName,Would Enable,N/A,Dry run mode" | Out-File -FilePath $script:CsvOutput -Append -Encoding UTF8
        "  [DRY RUN] $Region - $VpcId ($VpcName)" | Out-File -FilePath $script:SummaryFile -Append -Encoding UTF8
        $script:EnabledVpcs++
        return $true
    }

    try {
        $resultJson = aws ec2 create-flow-logs `
            --region $Region `
            --resource-type VPC `
            --resource-ids $VpcId `
            --traffic-type $script:TrafficType `
            --log-destination-type cloud-watch-logs `
            --log-group-name $LogGroup `
            --deliver-logs-permission-arn $script:RoleArn `
            --output json 2>&1

        if ($LASTEXITCODE -eq 0) {
            $result = $resultJson | ConvertFrom-Json
            if ($result.FlowLogIds -and $result.FlowLogIds.Count -gt 0) {
                $flowLogId = $result.FlowLogIds[0]
                Write-Host "✓ Success" -ForegroundColor Green
                "$Region,$VpcId,$VpcName,Enabled,$flowLogId,Successfully enabled" | Out-File -FilePath $script:CsvOutput -Append -Encoding UTF8
                "  [ENABLED] $Region - $VpcId ($VpcName) - $flowLogId" | Out-File -FilePath $script:SummaryFile -Append -Encoding UTF8
                $script:EnabledVpcs++
                return $true
            }
        }

        # If we get here, something went wrong
        $errorMsg = "Unknown error"
        if ($resultJson -match '"message":\s*"([^"]*)"') {
            $errorMsg = $Matches[1]
        }

        Write-Host "✗ Failed" -ForegroundColor Red
        Write-Host "    Error: $errorMsg"
        "$Region,$VpcId,$VpcName,Failed,N/A,$errorMsg" | Out-File -FilePath $script:CsvOutput -Append -Encoding UTF8
        "  [FAILED] $Region - $VpcId ($VpcName) - $errorMsg" | Out-File -FilePath $script:SummaryFile -Append -Encoding UTF8
        $script:FailedVpcs++
        return $false

    } catch {
        Write-Host "✗ Failed" -ForegroundColor Red
        Write-Host "    Error: $($_.Exception.Message)"
        "$Region,$VpcId,$VpcName,Failed,N/A,$($_.Exception.Message)" | Out-File -FilePath $script:CsvOutput -Append -Encoding UTF8
        "  [FAILED] $Region - $VpcId ($VpcName) - $($_.Exception.Message)" | Out-File -FilePath $script:SummaryFile -Append -Encoding UTF8
        $script:FailedVpcs++
        return $false
    }
}

# Get all regions
Write-Host "Fetching AWS regions..." -ForegroundColor White
$regionsJson = aws ec2 describe-regions --query 'Regions[].RegionName' --output json
$regions = $regionsJson | ConvertFrom-Json
$regionCount = $regions.Count
Write-Host "Found $regionCount regions to check" -ForegroundColor White
Write-Host ""

# Process each region
foreach ($region in $regions) {
    Write-Host "Checking region: $region" -ForegroundColor Cyan
    $TotalRegions++

    # Get all VPCs in the region
    try {
        $vpcsJson = aws ec2 describe-vpcs `
            --region $region `
            --query 'Vpcs[].[VpcId,Tags[?Key==`Name`].Value|[0]]' `
            --output json 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Host "  No VPCs found" -ForegroundColor Gray
            Write-Host ""
            continue
        }

        $vpcs = $vpcsJson | ConvertFrom-Json

        if (-not $vpcs -or $vpcs.Count -eq 0) {
            Write-Host "  No VPCs found" -ForegroundColor Gray
            Write-Host ""
            continue
        }

        $vpcCount = $vpcs.Count
        Write-Host "  Found $vpcCount VPC(s)"

        # Process each VPC
        foreach ($vpc in $vpcs) {
            $vpcId = $vpc[0]
            $vpcName = if ($vpc[1]) { $vpc[1] } else { "Unnamed" }

            $TotalVpcs++

            Write-Host "  VPC: $vpcId ($vpcName) - " -NoNewline

            # Check if flow logs already enabled
            $existingFlowLogs = Test-ExistingFlowLogs -Region $region -VpcId $vpcId

            if ($existingFlowLogs) {
                Write-Host "Already enabled" -ForegroundColor Yellow
                Write-Host "    Existing flow log(s): $existingFlowLogs"
                "$region,$vpcId,$vpcName,Already Enabled,$existingFlowLogs,Flow logs already active" | Out-File -FilePath $CsvOutput -Append -Encoding UTF8
                "  [SKIP] $region - $vpcId ($vpcName) - Already enabled: $existingFlowLogs" | Out-File -FilePath $SummaryFile -Append -Encoding UTF8
                $AlreadyEnabledVpcs++
                continue
            }

            Write-Host ""

            # Create log group for this region
            if (-not $DryRun) {
                Write-Host "  Creating/verifying log group... " -NoNewline
                if (New-LogGroupIfNotExists -Region $region -LogGroup $LogGroupPrefix) {
                    Write-Host "✓" -ForegroundColor Green
                } else {
                    Write-Host "✗ Failed" -ForegroundColor Red
                    "$region,$vpcId,$vpcName,Failed,N/A,Failed to create log group" | Out-File -FilePath $CsvOutput -Append -Encoding UTF8
                    $FailedVpcs++
                    continue
                }
            }

            # Enable flow logs
            $null = Enable-VpcFlowLogs -Region $region -VpcId $vpcId -VpcName $vpcName -LogGroup $LogGroupPrefix
        }

    } catch {
        Write-Host "  Error processing region: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ""
}

# Generate summary
@"

SUMMARY
========================================
Total regions checked: $TotalRegions
Total VPCs found: $TotalVpcs
VPCs with flow logs enabled: $EnabledVpcs
VPCs already had flow logs: $AlreadyEnabledVpcs
VPCs failed: $FailedVpcs

"@ | Out-File -FilePath $SummaryFile -Append -Encoding UTF8

# Display summary
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Total regions checked: $TotalRegions"
Write-Host "Total VPCs found: $TotalVpcs"
Write-Host ""
Write-Host "VPCs with flow logs enabled: " -NoNewline
Write-Host "$EnabledVpcs" -ForegroundColor Green
Write-Host "VPCs already had flow logs: " -NoNewline
Write-Host "$AlreadyEnabledVpcs" -ForegroundColor Yellow
if ($FailedVpcs -gt 0) {
    Write-Host "VPCs failed: " -NoNewline
    Write-Host "$FailedVpcs" -ForegroundColor Red
}
Write-Host ""
Write-Host "Output files:"
Write-Host "  Summary: $SummaryFile"
Write-Host "  CSV:     $CsvOutput"
Write-Host ""

if ($DryRun) {
    Write-Host "This was a dry run. No changes were made." -ForegroundColor Blue
    Write-Host "Run without -DryRun to actually enable flow logs."
    Write-Host ""
}

if ($EnabledVpcs -gt 0) {
    Write-Host "✓ VPC Flow Logs enablement complete!" -ForegroundColor Green
} elseif ($AlreadyEnabledVpcs -eq $TotalVpcs -and $TotalVpcs -gt 0) {
    Write-Host "All VPCs already have flow logs enabled." -ForegroundColor Yellow
} elseif ($FailedVpcs -gt 0) {
    Write-Host "Some VPCs failed to enable flow logs. Check the summary for details." -ForegroundColor Red
    exit 1
}

Write-Host "==========================================" -ForegroundColor Cyan
