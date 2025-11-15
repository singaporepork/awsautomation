<#
.SYNOPSIS
    Cleanup AMIs older than specified days and their associated snapshots

.DESCRIPTION
    This script identifies Amazon Machine Images (AMIs) older than a specified age threshold
    and their associated EBS snapshots. It can deregister old AMIs and delete associated
    snapshots to reduce storage costs.

.PARAMETER Region
    AWS region to scan for AMIs (default: us-east-1)

.PARAMETER AgeDays
    Age threshold in days for AMI cleanup (default: 180)

.PARAMETER DryRun
    If specified, only reports what would be cleaned up without making changes

.EXAMPLE
    .\cleanup-old-amis-snapshots.ps1 -DryRun
    Preview old AMIs without making changes

.EXAMPLE
    .\cleanup-old-amis-snapshots.ps1 -Region us-west-2 -AgeDays 90
    Cleanup AMIs older than 90 days in us-west-2

.EXAMPLE
    .\cleanup-old-amis-snapshots.ps1 -Region eu-west-1 -DryRun
    Preview old AMIs in eu-west-1 region

.NOTES
    Author: AWS Automation
    Requires: AWS CLI, PowerShell 5.0+
    License: MIT
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$Region = "us-east-1",

    [Parameter(Mandatory=$false)]
    [int]$AgeDays = 180,

    [Parameter(Mandatory=$false)]
    [switch]$DryRun = $false
)

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

function Write-Error {
    param([string]$Message)
    Write-ColorOutput "  ✗ $Message" "Red"
}

function Write-Warning {
    param([string]$Message)
    Write-ColorOutput "  → $Message" "Yellow"
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
$OutputCsv = "old-amis-cleanup.csv"
$SummaryFile = "old-amis-cleanup-summary.txt"

# Counters
$TotalAmis = 0
$OldAmis = 0
$RecentAmis = 0
$AmisDeregistered = 0
$AmisFailed = 0
$SnapshotsDeleted = 0
$SnapshotsFailed = 0

Write-Header "AMI and Snapshot Cleanup"
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
Write-Host "Region: $Region"
Write-Host "Age threshold: $AgeDays days"

if ($DryRun) {
    Write-ColorOutput "DRY RUN MODE: No changes will be made" "Yellow"
}

Write-Host ""

# Calculate cutoff date
$CutoffDate = (Get-Date).AddDays(-$AgeDays).ToUniversalTime()
$CutoffDateString = $CutoffDate.ToString("yyyy-MM-ddTHH:mm:ss.000Z")

Write-Host "Cutoff date: $CutoffDateString"
Write-Host "AMIs created before this date will be targeted for cleanup"
Write-Host ""

# Initialize CSV output
$CsvHeader = "AMI ID,AMI Name,Creation Date,Age (Days),State,Snapshot IDs,Action,Status"
$CsvHeader | Out-File -FilePath $OutputCsv -Encoding UTF8

# Initialize summary file
$SummaryHeader = @"
AMI and Snapshot Cleanup Summary
Generated: $(Get-Date)
Account: $AccountId
Region: $Region
Age threshold: $AgeDays days
Cutoff date: $CutoffDateString
Dry Run: $DryRun
========================================

"@
$SummaryHeader | Out-File -FilePath $SummaryFile -Encoding UTF8

# Function to calculate age in days
function Get-AgeInDays {
    param([string]$CreationDate)

    try {
        $createdDateTime = [DateTime]::Parse($CreationDate)
        $now = Get-Date
        $age = ($now - $createdDateTime).Days
        return $age
    } catch {
        return 0
    }
}

# Function to get snapshot IDs from AMI
function Get-AmiSnapshots {
    param([string]$AmiId)

    try {
        $result = aws ec2 describe-images `
            --region $Region `
            --image-ids $AmiId `
            --query 'Images[0].BlockDeviceMappings[?Ebs.SnapshotId!=`null`].Ebs.SnapshotId' `
            --output text 2>&1

        if ($LASTEXITCODE -eq 0 -and $result) {
            return $result -split '\s+'
        }
        return @()
    } catch {
        return @()
    }
}

# Function to deregister AMI
function Remove-Ami {
    param(
        [string]$AmiId,
        [string]$AmiName
    )

    if ($DryRun) {
        Write-ColorOutput "    [DRY RUN] Would deregister AMI: $AmiId" "Yellow"
        return $true
    }

    try {
        $result = aws ec2 deregister-image `
            --region $Region `
            --image-id $AmiId 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Success "Deregistered AMI: $AmiId"
            return $true
        } else {
            Write-Error "Failed to deregister AMI: $AmiId"
            Write-Host "    Error: $result"
            return $false
        }
    } catch {
        Write-Error "Failed to deregister AMI: $AmiId"
        Write-Host "    Error: $_"
        return $false
    }
}

# Function to delete snapshot
function Remove-EbsSnapshot {
    param([string]$SnapshotId)

    if ($DryRun) {
        Write-ColorOutput "      [DRY RUN] Would delete snapshot: $SnapshotId" "Yellow"
        return $true
    }

    try {
        $result = aws ec2 delete-snapshot `
            --region $Region `
            --snapshot-id $SnapshotId 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Success "Deleted snapshot: $SnapshotId"
            return $true
        } else {
            Write-Error "Failed to delete snapshot: $SnapshotId"
            Write-Host "      Error: $result"
            return $false
        }
    } catch {
        Write-Error "Failed to delete snapshot: $SnapshotId"
        Write-Host "      Error: $_"
        return $false
    }
}

# Get all AMIs owned by this account
Write-Host "Fetching AMIs owned by account $AccountId in region $Region..."

try {
    $amisJson = aws ec2 describe-images `
        --region $Region `
        --owners $AccountId `
        --query 'Images[*].[ImageId,Name,CreationDate,State]' `
        --output json 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to retrieve AMIs"
    }

    $amis = $amisJson | ConvertFrom-Json
    $TotalAmis = $amis.Count

    if ($TotalAmis -eq 0) {
        Write-Host "No AMIs found owned by this account in $Region"
        exit 0
    }

    Write-Host "Found $TotalAmis AMI(s) owned by this account"
    Write-Host ""

} catch {
    Write-ColorOutput "Error fetching AMIs: $_" "Red"
    exit 1
}

# Process each AMI
Write-Host "Analyzing AMIs..."
Write-Host ""

foreach ($ami in $amis) {
    $amiId = $ami[0]
    $amiName = $ami[1]
    $creationDate = $ami[2]
    $amiState = $ami[3]

    # Handle null AMI name
    if ([string]::IsNullOrEmpty($amiName) -or $amiName -eq "null") {
        $amiName = "<unnamed>"
    }

    # Calculate age
    $age = Get-AgeInDays -CreationDate $creationDate

    Write-ColorOutput "AMI: $amiId" "Blue"
    Write-Host "  Name: $amiName"
    Write-Host "  Created: $creationDate ($age days ago)"
    Write-Host "  State: $amiState"

    # Check if AMI is older than threshold
    if ($age -ge $AgeDays) {
        $OldAmis++
        Write-Warning "AMI is older than $AgeDays days"

        # Get associated snapshots
        $snapshotIds = Get-AmiSnapshots -AmiId $amiId
        $snapshotCount = $snapshotIds.Count
        $snapshotIdsString = $snapshotIds -join ' '

        Write-Host "  Associated snapshots ($snapshotCount): $snapshotIdsString"

        # Deregister AMI
        Write-ColorOutput "  Deregistering AMI..." "Blue"
        $success = Remove-Ami -AmiId $amiId -AmiName $amiName

        if ($success) {
            $AmisDeregistered++
            $amiAction = "Deregister"
            $amiStatus = "Success"

            # Delete associated snapshots
            if ($snapshotCount -gt 0) {
                Write-Host "  Deleting associated snapshots..."
                foreach ($snapshotId in $snapshotIds) {
                    if (Remove-EbsSnapshot -SnapshotId $snapshotId) {
                        $SnapshotsDeleted++
                    } else {
                        $SnapshotsFailed++
                    }
                }
            }
        } else {
            $AmisFailed++
            $amiAction = "Deregister"
            $amiStatus = "Failed"
        }

        # Write to CSV
        $snapshotIdsCsv = $snapshotIds -join ';'
        $csvLine = "$amiId,`"$amiName`",$creationDate,$age,$amiState,`"$snapshotIdsCsv`",$amiAction,$amiStatus"
        $csvLine | Out-File -FilePath $OutputCsv -Append -Encoding UTF8

        # Write to summary
        "  [OLD] $amiId - $amiName ($age days) - $amiStatus" | Out-File -FilePath $SummaryFile -Append -Encoding UTF8

    } else {
        $RecentAmis++
        Write-Success "AMI is recent (< $AgeDays days)"

        # Write to CSV
        $csvLine = "$amiId,`"$amiName`",$creationDate,$age,$amiState,,Skip,Recent"
        $csvLine | Out-File -FilePath $OutputCsv -Append -Encoding UTF8
    }

    Write-Host ""
}

# Generate summary
$summaryText = @"

SUMMARY
========================================
Total AMIs found: $TotalAmis
AMIs older than $AgeDays days: $OldAmis
Recent AMIs (< $AgeDays days): $RecentAmis

AMIs deregistered: $AmisDeregistered
AMIs failed: $AmisFailed

Snapshots deleted: $SnapshotsDeleted
Snapshots failed: $SnapshotsFailed

"@
$summaryText | Out-File -FilePath $SummaryFile -Append -Encoding UTF8

# Display summary
Write-Header "SUMMARY"
Write-Host "Total AMIs found: $TotalAmis"
Write-ColorOutput "AMIs older than $AgeDays days: $OldAmis" "Yellow"
Write-ColorOutput "Recent AMIs (< $AgeDays days): $RecentAmis" "Green"
Write-Host ""
Write-ColorOutput "AMIs deregistered: $AmisDeregistered" "Green"
if ($AmisFailed -gt 0) {
    Write-ColorOutput "AMIs failed: $AmisFailed" "Red"
}
Write-Host ""
Write-ColorOutput "Snapshots deleted: $SnapshotsDeleted" "Green"
if ($SnapshotsFailed -gt 0) {
    Write-ColorOutput "Snapshots failed: $SnapshotsFailed" "Red"
}
Write-Host ""
Write-Host "Output files:"
Write-Host "  Summary: $SummaryFile"
Write-Host "  CSV:     $OutputCsv"
Write-Host ""

if ($DryRun) {
    Write-ColorOutput "This was a dry run. No changes were made." "Blue"
    Write-Host "Run without -DryRun to actually deregister AMIs and delete snapshots."
    Write-Host ""
}

if ($AmisDeregistered -gt 0 -or $SnapshotsDeleted -gt 0) {
    Write-Success "Cleanup complete!"
} elseif ($OldAmis -eq 0) {
    Write-Success "No old AMIs found. Nothing to clean up."
} elseif ($AmisFailed -gt 0 -or $SnapshotsFailed -gt 0) {
    Write-ColorOutput "Some operations failed. Check the summary for details." "Red"
    exit 1
}

Write-Info "=========================================="
