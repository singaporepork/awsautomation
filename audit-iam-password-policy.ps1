#Requires -Version 5.0

<#
.SYNOPSIS
    Identifies IAM users without the IAMUserChangePassword policy

.DESCRIPTION
    This script audits all IAM users in your AWS account and identifies those who lack
    the ability to change their own password. It checks for the iam:ChangePassword
    permission through direct policy attachments and group memberships.

.EXAMPLE
    .\audit-iam-password-policy.ps1

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
$UsersWithoutPolicyFile = "users_without_change_password_policy.txt"
$DetailedReportFile = "iam_password_policy_audit_report.txt"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "IAM Password Policy Audit" -ForegroundColor Cyan
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
"IAM Password Policy Audit Report" | Out-File -FilePath $DetailedReportFile -Encoding UTF8
"Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File -FilePath $DetailedReportFile -Append -Encoding UTF8
"==========================================" | Out-File -FilePath $DetailedReportFile -Append -Encoding UTF8
"" | Out-File -FilePath $DetailedReportFile -Append -Encoding UTF8

# Clear the users without policy file
"" | Out-File -FilePath $UsersWithoutPolicyFile -Encoding UTF8 -NoNewline
Clear-Content -Path $UsersWithoutPolicyFile

$usersWithoutPolicyCount = 0

# Function to check if a policy grants iam:ChangePassword permission
function Test-PolicyForChangePassword {
    param(
        [string]$PolicyArn
    )

    try {
        # Get the default policy version
        $policyJson = aws iam get-policy --policy-arn $PolicyArn --query 'Policy.DefaultVersionId' --output json 2>&1
        if ($LASTEXITCODE -ne 0) {
            return $false
        }
        $defaultVersion = $policyJson | ConvertFrom-Json

        if (-not $defaultVersion) {
            return $false
        }

        # Get the policy document
        $policyDocJson = aws iam get-policy-version --policy-arn $PolicyArn --version-id $defaultVersion --query 'PolicyVersion.Document' --output json 2>&1
        if ($LASTEXITCODE -ne 0) {
            return $false
        }
        $policyDoc = $policyDocJson | ConvertFrom-Json

        # Check if the policy contains iam:ChangePassword or iam:*
        foreach ($statement in $policyDoc.Statement) {
            if ($statement.Effect -eq "Allow") {
                $actions = @()
                if ($statement.Action -is [array]) {
                    $actions = $statement.Action
                } else {
                    $actions = @($statement.Action)
                }

                foreach ($action in $actions) {
                    if ($action -match '^(iam:ChangePassword|iam:\*|\*)$') {
                        return $true
                    }
                }
            }
        }
    } catch {
        return $false
    }

    return $false
}

# Function to check inline policy for change password permission
function Test-InlinePolicyForChangePassword {
    param(
        [object]$PolicyDoc
    )

    try {
        # Check if the policy contains iam:ChangePassword or iam:*
        foreach ($statement in $PolicyDoc.Statement) {
            if ($statement.Effect -eq "Allow") {
                $actions = @()
                if ($statement.Action -is [array]) {
                    $actions = $statement.Action
                } else {
                    $actions = @($statement.Action)
                }

                foreach ($action in $actions) {
                    if ($action -match '^(iam:ChangePassword|iam:\*|\*)$') {
                        return $true
                    }
                }
            }
        }
    } catch {
        return $false
    }

    return $false
}

# Function to check if user has change password permission
function Test-UserHasChangePasswordPermission {
    param(
        [string]$Username
    )

    $hasPermission = $false

    # Check directly attached managed policies
    try {
        $attachedPoliciesJson = aws iam list-attached-user-policies --user-name $Username --query 'AttachedPolicies[*].PolicyArn' --output json 2>&1
        if ($LASTEXITCODE -eq 0) {
            $attachedPolicies = $attachedPoliciesJson | ConvertFrom-Json

            foreach ($policyArn in $attachedPolicies) {
                if ($policyArn -eq "arn:aws:iam::aws:policy/IAMUserChangePassword") {
                    "  ✓ Has IAMUserChangePassword policy attached directly" | Out-File -FilePath $script:DetailedReportFile -Append -Encoding UTF8
                    $hasPermission = $true
                    break
                }

                if (Test-PolicyForChangePassword -PolicyArn $policyArn) {
                    "  ✓ Has iam:ChangePassword permission via policy: $policyArn" | Out-File -FilePath $script:DetailedReportFile -Append -Encoding UTF8
                    $hasPermission = $true
                    break
                }
            }
        }
    } catch {
        # Continue checking other sources
    }

    # Check inline policies
    if (-not $hasPermission) {
        try {
            $inlinePoliciesJson = aws iam list-user-policies --user-name $Username --query 'PolicyNames[*]' --output json 2>&1
            if ($LASTEXITCODE -eq 0) {
                $inlinePolicies = $inlinePoliciesJson | ConvertFrom-Json

                foreach ($policyName in $inlinePolicies) {
                    $policyDocJson = aws iam get-user-policy --user-name $Username --policy-name $policyName --query 'PolicyDocument' --output json 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        $policyDoc = $policyDocJson | ConvertFrom-Json

                        if (Test-InlinePolicyForChangePassword -PolicyDoc $policyDoc) {
                            "  ✓ Has iam:ChangePassword permission via inline policy: $policyName" | Out-File -FilePath $script:DetailedReportFile -Append -Encoding UTF8
                            $hasPermission = $true
                            break
                        }
                    }
                }
            }
        } catch {
            # Continue checking other sources
        }
    }

    # Check group memberships
    if (-not $hasPermission) {
        try {
            $groupsJson = aws iam list-groups-for-user --user-name $Username --query 'Groups[*].GroupName' --output json 2>&1
            if ($LASTEXITCODE -eq 0) {
                $groups = $groupsJson | ConvertFrom-Json

                :groupLoop foreach ($group in $groups) {
                    # Check group's attached managed policies
                    $groupAttachedPoliciesJson = aws iam list-attached-group-policies --group-name $group --query 'AttachedPolicies[*].PolicyArn' --output json 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        $groupAttachedPolicies = $groupAttachedPoliciesJson | ConvertFrom-Json

                        foreach ($policyArn in $groupAttachedPolicies) {
                            if ($policyArn -eq "arn:aws:iam::aws:policy/IAMUserChangePassword") {
                                "  ✓ Has IAMUserChangePassword policy via group: $group" | Out-File -FilePath $script:DetailedReportFile -Append -Encoding UTF8
                                $hasPermission = $true
                                break groupLoop
                            }

                            if (Test-PolicyForChangePassword -PolicyArn $policyArn) {
                                "  ✓ Has iam:ChangePassword permission via group '$group' policy: $policyArn" | Out-File -FilePath $script:DetailedReportFile -Append -Encoding UTF8
                                $hasPermission = $true
                                break groupLoop
                            }
                        }
                    }

                    # Check group's inline policies
                    if (-not $hasPermission) {
                        $groupInlinePoliciesJson = aws iam list-group-policies --group-name $group --query 'PolicyNames[*]' --output json 2>&1
                        if ($LASTEXITCODE -eq 0) {
                            $groupInlinePolicies = $groupInlinePoliciesJson | ConvertFrom-Json

                            foreach ($policyName in $groupInlinePolicies) {
                                $policyDocJson = aws iam get-group-policy --group-name $group --policy-name $policyName --query 'PolicyDocument' --output json 2>&1
                                if ($LASTEXITCODE -eq 0) {
                                    $policyDoc = $policyDocJson | ConvertFrom-Json

                                    if (Test-InlinePolicyForChangePassword -PolicyDoc $policyDoc) {
                                        "  ✓ Has iam:ChangePassword permission via group '$group' inline policy: $policyName" | Out-File -FilePath $script:DetailedReportFile -Append -Encoding UTF8
                                        $hasPermission = $true
                                        break groupLoop
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } catch {
            # Continue
        }
    }

    return $hasPermission
}

# Process each user
foreach ($username in $users) {
    "Checking user: $username" | Out-File -FilePath $DetailedReportFile -Append -Encoding UTF8

    if (Test-UserHasChangePasswordPermission -Username $username) {
        Write-Host "✓ " -ForegroundColor Green -NoNewline
        Write-Host "$username - Has change password permission"
    } else {
        Write-Host "✗ " -ForegroundColor Red -NoNewline
        Write-Host "$username - Missing change password permission"
        "  ✗ Does NOT have iam:ChangePassword permission" | Out-File -FilePath $DetailedReportFile -Append -Encoding UTF8
        $username | Out-File -FilePath $UsersWithoutPolicyFile -Append -Encoding UTF8
        $usersWithoutPolicyCount++
    }

    "" | Out-File -FilePath $DetailedReportFile -Append -Encoding UTF8
}

# Summary
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Total users: $userCount"
Write-Host "Users with change password permission: " -NoNewline
Write-Host "$($userCount - $usersWithoutPolicyCount)" -ForegroundColor Green
Write-Host "Users without change password permission: " -NoNewline
Write-Host "$usersWithoutPolicyCount" -ForegroundColor Red
Write-Host ""

if ($usersWithoutPolicyCount -gt 0) {
    Write-Host "Users without IAMUserChangePassword policy:" -ForegroundColor Yellow
    Get-Content -Path $UsersWithoutPolicyFile | Where-Object { $_.Trim() -ne "" } | ForEach-Object {
        Write-Host "  $_" -ForegroundColor Yellow
    }
    Write-Host ""
}

Write-Host "Detailed report saved to: $DetailedReportFile" -ForegroundColor Cyan
Write-Host "Users without policy saved to: $UsersWithoutPolicyFile" -ForegroundColor Cyan
