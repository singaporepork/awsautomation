#Requires -Version 5.0

<#
.SYNOPSIS
    Identifies IAM users without MFA (Multi-Factor Authentication) enabled

.DESCRIPTION
    This script audits all IAM users in your AWS account and identifies those who
    do not have MFA enabled. MFA adds an extra layer of security by requiring users
    to provide additional authentication beyond just a password.

.EXAMPLE
    .\audit-mfa-enabled.ps1

.NOTES
    Requires AWS CLI to be installed and configured
    Compatible with PowerShell 5.0 and later
#>

[CmdletBinding()]
param()

# Set strict mode
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Output files
$OutputFile = "users_without_mfa_report.txt"
$CsvFile = "users_without_mfa.csv"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "IAM MFA Audit" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Identifying users without MFA enabled" -ForegroundColor White
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
"IAM MFA Audit Report" | Out-File -FilePath $OutputFile -Encoding UTF8
"Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File -FilePath $OutputFile -Append -Encoding UTF8
"Identifying users without MFA enabled" | Out-File -FilePath $OutputFile -Append -Encoding UTF8
"==========================================" | Out-File -FilePath $OutputFile -Append -Encoding UTF8
"" | Out-File -FilePath $OutputFile -Append -Encoding UTF8

# Initialize CSV file
"UserName,MFA Enabled,MFA Device Count,Device ARNs" | Out-File -FilePath $CsvFile -Encoding UTF8

# Counters
$usersWithoutMfa = 0
$usersWithMfa = 0

# Process each user
foreach ($username in $users) {
    "Checking user: $username" | Out-File -FilePath $OutputFile -Append -Encoding UTF8

    # Get MFA devices for the user
    try {
        $mfaDevicesJson = aws iam list-mfa-devices --user-name $username --query 'MFADevices[*].SerialNumber' --output json 2>&1
        if ($LASTEXITCODE -ne 0) {
            # Error getting MFA devices, treat as no MFA
            $mfaDevices = @()
        } else {
            $mfaDevices = $mfaDevicesJson | ConvertFrom-Json
            if ($null -eq $mfaDevices) {
                $mfaDevices = @()
            }
        }
    } catch {
        # Error getting MFA devices, treat as no MFA
        $mfaDevices = @()
    }

    if ($mfaDevices.Count -eq 0) {
        # No MFA devices found
        $usersWithoutMfa++
        "  ✗ MFA: Not enabled" | Out-File -FilePath $OutputFile -Append -Encoding UTF8
        Write-Host "✗ " -ForegroundColor Red -NoNewline
        Write-Host "$username - MFA not enabled"

        # Add to CSV
        "$username,No,0,None" | Out-File -FilePath $CsvFile -Append -Encoding UTF8
    } else {
        # MFA devices found
        $usersWithMfa++
        $deviceCount = $mfaDevices.Count

        "  ✓ MFA: Enabled ($deviceCount device(s))" | Out-File -FilePath $OutputFile -Append -Encoding UTF8

        # List each device
        foreach ($device in $mfaDevices) {
            "    - Device: $device" | Out-File -FilePath $OutputFile -Append -Encoding UTF8
        }

        Write-Host "✓ " -ForegroundColor Green -NoNewline
        Write-Host "$username - MFA enabled ($deviceCount device(s))"

        # Add to CSV (join multiple devices with semicolons)
        $deviceList = $mfaDevices -join ";"
        "$username,Yes,$deviceCount,$deviceList" | Out-File -FilePath $CsvFile -Append -Encoding UTF8
    }

    "" | Out-File -FilePath $OutputFile -Append -Encoding UTF8
}

# Summary
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Total users checked: $userCount"
Write-Host ""
Write-Host "Users with MFA enabled: " -NoNewline
Write-Host "$usersWithMfa" -ForegroundColor Green
Write-Host "Users without MFA enabled: " -NoNewline
Write-Host "$usersWithoutMfa" -ForegroundColor Red
Write-Host ""

if ($usersWithoutMfa -gt 0) {
    Write-Host "WARNING: Found $usersWithoutMfa user(s) without MFA enabled" -ForegroundColor Yellow
    Write-Host "These users should enable MFA to enhance account security" -ForegroundColor Yellow
    Write-Host ""

    Write-Host "Users without MFA:" -ForegroundColor Yellow
    Get-Content -Path $CsvFile | Where-Object { $_ -match ",No," -and $_ -notmatch "^UserName," } | ForEach-Object {
        $user = ($_ -split ',')[0]
        Write-Host "  ✗ $user" -ForegroundColor Red
    }
    Write-Host ""
}

Write-Host "Detailed report saved to: $OutputFile" -ForegroundColor Cyan
Write-Host "CSV export saved to: $CsvFile" -ForegroundColor Cyan
Write-Host ""
Write-Host "Recommendation: " -ForegroundColor Blue -NoNewline
Write-Host "Enable MFA for all users, especially those with console access"
Write-Host "MFA adds an extra layer of security: " -ForegroundColor Blue -NoNewline
Write-Host "Even if passwords are compromised, accounts remain protected"
