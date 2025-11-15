<#
.SYNOPSIS
    Identify RDS instances with pending actions across all AWS regions

.DESCRIPTION
    This script scans all AWS regions for RDS database instances and identifies
    those with pending maintenance actions or pending modifications. It provides
    detailed reporting in console output, CSV, and summary text formats.

.EXAMPLE
    .\list-rds-pending-actions.ps1
    Scan all regions for RDS instances with pending actions

.NOTES
    Author: AWS Automation
    Requires: AWS CLI, PowerShell 5.0+
    License: MIT
#>

[CmdletBinding()]
param()

# Color output functions
function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Color = "White"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Write-Success {
    param([string]$Message)
    Write-ColorOutput "  ✓ $Message" "Green"
}

function Write-Warning {
    param([string]$Message)
    Write-ColorOutput $Message "Yellow"
}

function Write-Info {
    param([string]$Message)
    Write-ColorOutput $Message "Cyan"
}

function Write-Header {
    param([string]$Message)
    Write-ColorOutput "`n==========================================" "Cyan"
    Write-ColorOutput $Message "Cyan"
    Write-ColorOutput "==========================================" "Cyan"
}

# Configuration
$OutputCsv = "rds-pending-actions.csv"
$SummaryFile = "rds-pending-actions-summary.txt"

# Counters
$TotalRegions = 0
$TotalInstances = 0
$InstancesWithPendingActions = 0
$InstancesWithPendingMaintenance = 0
$InstancesWithPendingModifications = 0

Write-Header "RDS Pending Actions Report"
Write-Host ""

# Check if AWS CLI is installed
try {
    $null = aws --version 2>&1
} catch {
    Write-ColorOutput "Error: AWS CLI is not installed" "Red"
    Write-Host "Please install AWS CLI from: https://aws.amazon.com/cli/"
    exit 1
}

# Check AWS credentials
try {
    $null = aws sts get-caller-identity 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Invalid credentials"
    }
} catch {
    Write-ColorOutput "Error: AWS credentials not configured or invalid" "Red"
    Write-Host "Please run 'aws configure' to set up your credentials"
    exit 1
}

# Get Account ID
$AccountId = (aws sts get-caller-identity --query 'Account' --output text)
Write-Host "AWS Account ID: $AccountId"
Write-Host "Report Date: $(Get-Date)"
Write-Host ""

# Initialize CSV output
$CsvHeader = "Region,DB Instance,DB Engine,DB Version,Instance Class,Status,Pending Maintenance,Pending Modifications"
$CsvHeader | Out-File -FilePath $OutputCsv -Encoding UTF8

# Initialize summary file
$SummaryHeader = @"
RDS Pending Actions Summary
Generated: $(Get-Date)
Account: $AccountId
========================================

"@
$SummaryHeader | Out-File -FilePath $SummaryFile -Encoding UTF8

# Get all regions
Write-Host "Fetching AWS regions..."
try {
    $regionsJson = aws ec2 describe-regions --query 'Regions[].RegionName' --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to retrieve regions"
    }
    $regions = $regionsJson | ConvertFrom-Json
    Write-Host "Found $($regions.Count) regions to check"
    Write-Host ""
} catch {
    Write-ColorOutput "Error fetching regions: $_" "Red"
    exit 1
}

# Process each region
foreach ($region in $regions) {
    Write-Info "Checking region: $region"
    $TotalRegions++

    # Get all RDS instances in the region
    try {
        $instancesJson = aws rds describe-db-instances `
            --region $region `
            --query 'DBInstances[*].[DBInstanceIdentifier,Engine,EngineVersion,DBInstanceClass,DBInstanceStatus]' `
            --output json 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Host "  No RDS instances found or error accessing region"
            Write-Host ""
            continue
        }

        $instances = $instancesJson | ConvertFrom-Json
        $instanceCount = $instances.Count

        if ($instanceCount -eq 0) {
            Write-Host "  No RDS instances found"
            Write-Host ""
            continue
        }

        Write-Host "  Found $instanceCount RDS instance(s)"
        $TotalInstances += $instanceCount

        # Get pending maintenance actions for this region
        $pendingMaintenanceJson = aws rds describe-pending-maintenance-actions `
            --region $region `
            --output json 2>&1

        if ($LASTEXITCODE -eq 0) {
            $pendingMaintenance = $pendingMaintenanceJson | ConvertFrom-Json
        } else {
            $pendingMaintenance = @{ PendingMaintenanceActions = @() }
        }

        # Process each instance
        foreach ($instance in $instances) {
            $dbInstance = $instance[0]
            $dbEngine = $instance[1]
            $dbVersion = $instance[2]
            $dbClass = $instance[3]
            $dbStatus = $instance[4]

            # Get detailed instance info for pending modifications
            try {
                $instanceDetailJson = aws rds describe-db-instances `
                    --region $region `
                    --db-instance-identifier $dbInstance `
                    --output json 2>&1

                if ($LASTEXITCODE -eq 0) {
                    $instanceDetail = $instanceDetailJson | ConvertFrom-Json
                    $pendingModifiedValues = $instanceDetail.DBInstances[0].PendingModifiedValues

                    # Build pending modifications string
                    $pendingMods = @()
                    if ($pendingModifiedValues) {
                        $pendingModifiedValues.PSObject.Properties | ForEach-Object {
                            if ($_.Value) {
                                $pendingMods += "$($_.Name)=$($_.Value)"
                            }
                        }
                    }
                    $pendingModsText = if ($pendingMods.Count -gt 0) { $pendingMods -join "; " } else { "" }
                } else {
                    $pendingModsText = ""
                }
            } catch {
                $pendingModsText = ""
            }

            # Check for pending maintenance for this instance
            $pendingMaintText = ""
            $instanceMaintenance = $pendingMaintenance.PendingMaintenanceActions | Where-Object {
                $_.ResourceIdentifier -match $dbInstance
            }

            if ($instanceMaintenance) {
                $maintActions = @()
                foreach ($action in $instanceMaintenance.PendingMaintenanceActionDetails) {
                    $autoApply = if ($action.AutoAppliedAfterDate) { $action.AutoAppliedAfterDate } else { "N/A" }
                    $optIn = if ($action.OptInStatus) { $action.OptInStatus } else { "N/A" }
                    $maintActions += "$($action.Action) (auto-apply: $autoApply, opt-in: $optIn)"
                }
                $pendingMaintText = $maintActions -join "; "
            }

            # Display results
            if ($pendingMaintText -or $pendingModsText) {
                Write-Host ""
                Write-Warning "  DB Instance: $dbInstance"
                Write-Host "    Engine: $dbEngine $dbVersion"
                Write-Host "    Class: $dbClass"
                Write-Host "    Status: $dbStatus"

                if ($pendingMaintText) {
                    Write-ColorOutput "    Pending Maintenance:" "Red"
                    Write-Host "      $pendingMaintText"
                    $InstancesWithPendingMaintenance++
                }

                if ($pendingModsText) {
                    Write-ColorOutput "    Pending Modifications:" "Yellow"
                    Write-Host "      $pendingModsText"
                    $InstancesWithPendingModifications++
                }

                $InstancesWithPendingActions++

                # Write to summary
                $summaryLine = "  [$region] $dbInstance - Maintenance: $(if($pendingMaintText){$pendingMaintText}else{'None'}) | Modifications: $(if($pendingModsText){$pendingModsText}else{'None'})"
                $summaryLine | Out-File -FilePath $SummaryFile -Append -Encoding UTF8
            } else {
                Write-Success "$dbInstance - No pending actions"
            }

            # Write to CSV
            $csvLine = "$region,`"$dbInstance`",`"$dbEngine`",`"$dbVersion`",`"$dbClass`",`"$dbStatus`",`"$(if($pendingMaintText){$pendingMaintText}else{'None'})`",`"$(if($pendingModsText){$pendingModsText}else{'None'})`""
            $csvLine | Out-File -FilePath $OutputCsv -Append -Encoding UTF8
        }

    } catch {
        Write-Host "  Error processing region: $_"
    }

    Write-Host ""
}

# Generate summary
$summaryText = @"

SUMMARY
========================================
Total regions checked: $TotalRegions
Total RDS instances: $TotalInstances

Instances with pending actions: $InstancesWithPendingActions
Instances with pending maintenance: $InstancesWithPendingMaintenance
Instances with pending modifications: $InstancesWithPendingModifications

"@
$summaryText | Out-File -FilePath $SummaryFile -Append -Encoding UTF8

# Display summary
Write-Header "SUMMARY"
Write-Host "Total regions checked: $TotalRegions"
Write-Host "Total RDS instances: $TotalInstances"
Write-Host ""

if ($InstancesWithPendingActions -gt 0) {
    Write-Warning "Instances with pending actions: $InstancesWithPendingActions"
    Write-Host "  Pending maintenance: $InstancesWithPendingMaintenance"
    Write-Host "  Pending modifications: $InstancesWithPendingModifications"
} else {
    Write-ColorOutput "No instances with pending actions found!" "Green"
}

Write-Host ""
Write-Host "Output files:"
Write-Host "  Summary: $SummaryFile"
Write-Host "  CSV:     $OutputCsv"
Write-Host ""

Write-Info "=========================================="
