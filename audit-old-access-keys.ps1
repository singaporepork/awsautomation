#Requires -Version 5.0

<#
.SYNOPSIS
    Identifies IAM users with access keys older than 365 days

.DESCRIPTION
    This script audits all IAM users in your AWS account and identifies access keys
    that are older than 365 days. Helps maintain security by identifying potentially
    stale credentials that should be rotated.

.PARAMETER MaxAgeDays
    Maximum age in days for access keys (default: 365)

.EXAMPLE
    .\audit-old-access-keys.ps1

.EXAMPLE
    .\audit-old-access-keys.ps1 -MaxAgeDays 90

.NOTES
    Requires AWS CLI to be installed and configured
    Compatible with PowerShell 5.0 and later
#>

[CmdletBinding()]
param(
    [Parameter()]
    [int]$MaxAgeDays = 365
)

# Set strict mode
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Output files
$OutputFile = "old_access_keys_report.txt"
$CsvFile = "old_access_keys.csv"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "IAM Access Keys Age Audit" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Checking for access keys older than $MaxAgeDays days" -ForegroundColor White
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

Write-Host "Fetching IAM users..." -ForegroundColor White

# Get all IAM users
try {
    $usersJson = aws iam list-users --query 'Users[*].UserName' --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to list IAM users"
    }
    $users = $usersJson | ConvertFrom-Json
} catch {
    Write-Host "Error: Failed to retrieve IAM users" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}

if ($users.Count -eq 0) {
    Write-Host "No IAM users found" -ForegroundColor Yellow
    exit 0
}

$userCount = $users.Count
Write-Host "Found $userCount IAM users" -ForegroundColor White
Write-Host ""

# Initialize output files
"IAM Access Keys Age Audit Report" | Out-File -FilePath $OutputFile -Encoding UTF8
"Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File -FilePath $OutputFile -Append -Encoding UTF8
"Checking for access keys older than $MaxAgeDays days" | Out-File -FilePath $OutputFile -Append -Encoding UTF8
"==========================================" | Out-File -FilePath $OutputFile -Append -Encoding UTF8
"" | Out-File -FilePath $OutputFile -Append -Encoding UTF8

# Initialize CSV file
"UserName,AccessKeyId,Status,Age (Days),Created Date" | Out-File -FilePath $CsvFile -Encoding UTF8

# Counters
$oldKeysCount = 0
$totalKeysCount = 0
$usersWithOldKeys = 0
$currentDate = Get-Date

# Process each user
foreach ($username in $users) {
    "Checking user: $username" | Out-File -FilePath $OutputFile -Append -Encoding UTF8

    # Get access keys for the user
    try {
        $accessKeysJson = aws iam list-access-keys --user-name $username --query 'AccessKeyMetadata[*].[AccessKeyId,Status,CreateDate]' --output json 2>&1
        if ($LASTEXITCODE -ne 0) {
            "  No access keys" | Out-File -FilePath $OutputFile -Append -Encoding UTF8
            Write-Host "○ " -ForegroundColor Blue -NoNewline
            Write-Host "$username - No access keys"
            "" | Out-File -FilePath $OutputFile -Append -Encoding UTF8
            continue
        }

        $accessKeys = $accessKeysJson | ConvertFrom-Json

        if ($accessKeys.Count -eq 0) {
            "  No access keys" | Out-File -FilePath $OutputFile -Append -Encoding UTF8
            Write-Host "○ " -ForegroundColor Blue -NoNewline
            Write-Host "$username - No access keys"
            "" | Out-File -FilePath $OutputFile -Append -Encoding UTF8
            continue
        }
    } catch {
        "  Error retrieving access keys" | Out-File -FilePath $OutputFile -Append -Encoding UTF8
        Write-Host "○ " -ForegroundColor Blue -NoNewline
        Write-Host "$username - Error retrieving access keys"
        "" | Out-File -FilePath $OutputFile -Append -Encoding UTF8
        continue
    }

    $userHasOldKey = $false

    foreach ($key in $accessKeys) {
        $keyId = $key[0]
        $status = $key[1]
        $createDate = $key[2]

        if (-not $keyId) {
            continue
        }

        $totalKeysCount++

        # Parse create date and calculate age
        try {
            $createDateTime = [DateTime]::Parse($createDate)
            $ageTimeSpan = $currentDate - $createDateTime
            $ageDays = [int]$ageTimeSpan.TotalDays
            $createDateFormatted = $createDateTime.ToString("yyyy-MM-dd")
        } catch {
            Write-Warning "Could not parse date for key $keyId"
            continue
        }

        if ($ageDays -gt $MaxAgeDays) {
            $oldKeysCount++
            $userHasOldKey = $true

            "  ✗ Access Key: $keyId" | Out-File -FilePath $OutputFile -Append -Encoding UTF8
            "    Status: $status" | Out-File -FilePath $OutputFile -Append -Encoding UTF8
            "    Age: $ageDays days" | Out-File -FilePath $OutputFile -Append -Encoding UTF8
            "    Created: $createDateFormatted" | Out-File -FilePath $OutputFile -Append -Encoding UTF8

            # Add to CSV
            "$username,$keyId,$status,$ageDays,$createDateFormatted" | Out-File -FilePath $CsvFile -Append -Encoding UTF8
        } else {
            "  ✓ Access Key: $keyId (Age: $ageDays days)" | Out-File -FilePath $OutputFile -Append -Encoding UTF8
        }
    }

    if ($userHasOldKey) {
        $usersWithOldKeys++
        Write-Host "✗ " -ForegroundColor Red -NoNewline
        Write-Host "$username - Has access key(s) older than $MaxAgeDays days"
    } else {
        Write-Host "✓ " -ForegroundColor Green -NoNewline
        Write-Host "$username - All access keys are within acceptable age"
    }

    "" | Out-File -FilePath $OutputFile -Append -Encoding UTF8
}

# Summary
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Total users checked: $userCount"
Write-Host "Total access keys found: $totalKeysCount"
Write-Host ""
Write-Host "Access keys within $MaxAgeDays days: " -NoNewline
Write-Host "$($totalKeysCount - $oldKeysCount)" -ForegroundColor Green
Write-Host "Access keys older than $MaxAgeDays days: " -NoNewline
Write-Host "$oldKeysCount" -ForegroundColor Red
Write-Host "Users with old access keys: " -NoNewline
Write-Host "$usersWithOldKeys" -ForegroundColor Red
Write-Host ""

if ($oldKeysCount -gt 0) {
    Write-Host "WARNING: Found $oldKeysCount access key(s) older than $MaxAgeDays days" -ForegroundColor Yellow
    Write-Host "These keys should be rotated as part of security best practices" -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "Detailed report saved to: $OutputFile" -ForegroundColor Cyan
Write-Host "CSV export saved to: $CsvFile" -ForegroundColor Cyan
Write-Host ""
Write-Host "Recommendation: " -ForegroundColor Blue -NoNewline
Write-Host "Rotate access keys at least every 90 days"
Write-Host "To rotate: " -ForegroundColor Blue -NoNewline
Write-Host "Create new key, update applications, then delete old key"
