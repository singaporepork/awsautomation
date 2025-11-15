#Requires -Version 5.0

<#
.SYNOPSIS
    Creates VPC Gateway Endpoints in all VPCs across all AWS regions

.DESCRIPTION
    This script automatically creates VPC Gateway Endpoints (S3 or DynamoDB) in all VPCs
    across all AWS regions. It configures route tables to use the gateway endpoints with
    proper prefix list IDs instead of CIDR blocks.

.PARAMETER ServiceName
    AWS service for the gateway endpoint: s3 or dynamodb (default: s3)

.PARAMETER DryRun
    Preview changes without actually creating endpoints or routes

.EXAMPLE
    .\create-gateway-endpoints.ps1

.EXAMPLE
    .\create-gateway-endpoints.ps1 -ServiceName dynamodb

.EXAMPLE
    .\create-gateway-endpoints.ps1 -ServiceName s3 -DryRun

.NOTES
    Requires AWS CLI to be installed and configured
    Compatible with PowerShell 5.0 and later
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet("s3", "dynamodb")]
    [string]$ServiceName = "s3",

    [Parameter()]
    [switch]$DryRun
)

# Set strict mode
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Output files
$CsvOutput = "gateway-endpoints-setup.csv"
$SummaryFile = "gateway-endpoints-setup-summary.txt"

# Counters
$TotalVpcs = 0
$EndpointsCreated = 0
$EndpointsExisting = 0
$EndpointsFailed = 0
$RoutesAdded = 0
$RoutesExisting = 0
$RoutesFailed = 0
$TotalRegions = 0

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "VPC Gateway Endpoints Setup" -ForegroundColor Cyan
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
Write-Host "Service: $ServiceName"

if ($DryRun) {
    Write-Host "DRY RUN MODE: No changes will be made" -ForegroundColor Yellow
}

Write-Host ""

# Initialize CSV output
"Region,VPC ID,VPC Name,Endpoint ID,Endpoint Status,Route Tables,Routes Added,Message" | Out-File -FilePath $CsvOutput -Encoding UTF8

# Initialize summary file
@"
VPC Gateway Endpoints Setup Summary
Generated: $(Get-Date)
Account: $accountId
Service: $ServiceName
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

# Function to check if gateway endpoint already exists
function Test-ExistingEndpoint {
    param(
        [string]$Region,
        [string]$VpcId,
        [string]$Service
    )

    $serviceName = "com.amazonaws.$Region.$Service"

    try {
        $endpointIdJson = aws ec2 describe-vpc-endpoints `
            --region $Region `
            --filters "Name=vpc-id,Values=$VpcId" "Name=service-name,Values=$serviceName" "Name=vpc-endpoint-type,Values=Gateway" `
            --query 'VpcEndpoints[0].VpcEndpointId' `
            --output json 2>&1

        if ($LASTEXITCODE -eq 0) {
            $endpointId = $endpointIdJson | ConvertFrom-Json
            if ($endpointId -and $endpointId -ne "null") {
                return $endpointId
            }
        }
    } catch {
        # Ignore errors
    }

    return $null
}

# Function to get all route tables for a VPC
function Get-VpcRouteTables {
    param(
        [string]$Region,
        [string]$VpcId
    )

    try {
        $routeTablesJson = aws ec2 describe-route-tables `
            --region $Region `
            --filters "Name=vpc-id,Values=$VpcId" `
            --query 'RouteTables[].RouteTableId' `
            --output json 2>&1

        if ($LASTEXITCODE -eq 0) {
            $routeTables = $routeTablesJson | ConvertFrom-Json
            if ($routeTables -and $routeTables.Count -gt 0) {
                return $routeTables
            }
        }
    } catch {
        # Ignore errors
    }

    return @()
}

# Function to get prefix list ID for a service
function Get-PrefixListId {
    param(
        [string]$Region,
        [string]$Service
    )

    $serviceName = "com.amazonaws.$Region.$Service"

    try {
        $prefixListIdJson = aws ec2 describe-prefix-lists `
            --region $Region `
            --filters "Name=prefix-list-name,Values=$serviceName" `
            --query 'PrefixLists[0].PrefixListId' `
            --output json 2>&1

        if ($LASTEXITCODE -eq 0) {
            $prefixListId = $prefixListIdJson | ConvertFrom-Json
            if ($prefixListId -and $prefixListId -ne "null") {
                return $prefixListId
            }
        }
    } catch {
        # Ignore errors
    }

    return $null
}

# Function to check if route already exists
function Test-RouteExists {
    param(
        [string]$Region,
        [string]$RouteTableId,
        [string]$PrefixListId
    )

    try {
        $routeJson = aws ec2 describe-route-tables `
            --region $Region `
            --route-table-ids $RouteTableId `
            --query "RouteTables[0].Routes[?DestinationPrefixListId=='$PrefixListId'].DestinationPrefixListId" `
            --output json 2>&1

        if ($LASTEXITCODE -eq 0) {
            $route = $routeJson | ConvertFrom-Json
            if ($route -and $route.Count -gt 0) {
                return $true
            }
        }
    } catch {
        # Ignore errors
    }

    return $false
}

# Function to create gateway endpoint
function New-GatewayEndpoint {
    param(
        [string]$Region,
        [string]$VpcId,
        [string]$VpcName,
        [string]$Service
    )

    $serviceName = "com.amazonaws.$Region.$Service"

    Write-Host "  Creating gateway endpoint for $Service..." -ForegroundColor Blue

    if ($script:DryRun) {
        Write-Host "  [DRY RUN] Would create endpoint" -ForegroundColor Yellow
        "$Region,$VpcId,$VpcName,DRY-RUN,Would Create,N/A,0,Dry run mode" | Out-File -FilePath $script:CsvOutput -Append -Encoding UTF8
        "  [DRY RUN] $Region - $VpcId ($VpcName)" | Out-File -FilePath $script:SummaryFile -Append -Encoding UTF8
        $script:EndpointsCreated++
        return $true
    }

    # Get all route tables for the VPC
    $routeTables = Get-VpcRouteTables -Region $Region -VpcId $VpcId

    if ($routeTables.Count -eq 0) {
        Write-Host "  ✗ No route tables found" -ForegroundColor Red
        "$Region,$VpcId,$VpcName,FAILED,No Route Tables,0,0,No route tables found" | Out-File -FilePath $script:CsvOutput -Append -Encoding UTF8
        "  [FAILED] $Region - $VpcId ($VpcName) - No route tables" | Out-File -FilePath $script:SummaryFile -Append -Encoding UTF8
        $script:EndpointsFailed++
        return $false
    }

    # Create endpoint with route table associations
    $routeTableIds = $routeTables -join " "

    try {
        $endpointResultJson = aws ec2 create-vpc-endpoint `
            --region $Region `
            --vpc-id $VpcId `
            --service-name $serviceName `
            --vpc-endpoint-type Gateway `
            --route-table-ids $routeTableIds `
            --query 'VpcEndpoint.VpcEndpointId' `
            --output json 2>&1

        if ($LASTEXITCODE -eq 0) {
            $endpointId = $endpointResultJson | ConvertFrom-Json

            if ($endpointId -and $endpointId -ne "null") {
                Write-Host "  ✓ Endpoint created: $endpointId" -ForegroundColor Green

                $rtCount = $routeTables.Count

                "$Region,$VpcId,$VpcName,$endpointId,Created,$rtCount,$rtCount,Successfully created" | Out-File -FilePath $script:CsvOutput -Append -Encoding UTF8
                "  [CREATED] $Region - $VpcId ($VpcName) - $endpointId ($rtCount route tables)" | Out-File -FilePath $script:SummaryFile -Append -Encoding UTF8
                $script:EndpointsCreated++
                $script:RoutesAdded += $rtCount
                return $true
            }
        }

        # If we get here, something went wrong
        $errorMsg = $endpointResultJson -join " "
        Write-Host "  ✗ Failed to create endpoint" -ForegroundColor Red
        Write-Host "  Error: $errorMsg"
        "$Region,$VpcId,$VpcName,FAILED,Creation Failed,0,0,$errorMsg" | Out-File -FilePath $script:CsvOutput -Append -Encoding UTF8
        "  [FAILED] $Region - $VpcId ($VpcName) - $errorMsg" | Out-File -FilePath $script:SummaryFile -Append -Encoding UTF8
        $script:EndpointsFailed++
        return $false

    } catch {
        Write-Host "  ✗ Failed to create endpoint" -ForegroundColor Red
        Write-Host "  Error: $($_.Exception.Message)"
        "$Region,$VpcId,$VpcName,FAILED,Creation Failed,0,0,$($_.Exception.Message)" | Out-File -FilePath $script:CsvOutput -Append -Encoding UTF8
        "  [FAILED] $Region - $VpcId ($VpcName) - $($_.Exception.Message)" | Out-File -FilePath $script:SummaryFile -Append -Encoding UTF8
        $script:EndpointsFailed++
        return $false
    }
}

# Function to add route to route table using prefix list
function Add-RouteToTable {
    param(
        [string]$Region,
        [string]$RouteTableId,
        [string]$GatewayEndpointId,
        [string]$PrefixListId
    )

    # Check if route already exists
    if (Test-RouteExists -Region $Region -RouteTableId $RouteTableId -PrefixListId $PrefixListId) {
        Write-Host "    Route already exists in $RouteTableId" -ForegroundColor Yellow
        $script:RoutesExisting++
        return $true
    }

    if ($script:DryRun) {
        Write-Host "    [DRY RUN] Would add route to $RouteTableId" -ForegroundColor Yellow
        $script:RoutesAdded++
        return $true
    }

    try {
        $null = aws ec2 create-route `
            --region $Region `
            --route-table-id $RouteTableId `
            --destination-prefix-list-id $PrefixListId `
            --gateway-id $GatewayEndpointId 2>&1

        if ($LASTEXITCODE -eq 0) {
            Write-Host "    ✓ Route added to $RouteTableId" -ForegroundColor Green
            $script:RoutesAdded++
            return $true
        } else {
            throw "Failed to add route"
        }
    } catch {
        Write-Host "    ✗ Failed to add route to $RouteTableId" -ForegroundColor Red
        Write-Host "    Error: $($_.Exception.Message)"
        $script:RoutesFailed++
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
            --query 'Vpcs[].VpcId' `
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

        # Get prefix list ID for the service in this region
        $prefixListId = Get-PrefixListId -Region $region -Service $ServiceName

        if (-not $prefixListId) {
            Write-Host "  ⚠ Service $ServiceName not available in $region" -ForegroundColor Yellow
            Write-Host ""
            continue
        }

        Write-Host "  Prefix List ID: $prefixListId"

        # Process each VPC
        foreach ($vpcId in $vpcs) {
            $TotalVpcs++
            $vpcName = Get-VpcName -Region $region -VpcId $vpcId

            Write-Host ""
            Write-Host "  VPC: $vpcId ($vpcName)" -ForegroundColor Blue

            # Check if endpoint already exists
            $existingEndpoint = Test-ExistingEndpoint -Region $region -VpcId $vpcId -Service $ServiceName

            if ($existingEndpoint) {
                Write-Host "  Gateway endpoint already exists: $existingEndpoint" -ForegroundColor Yellow

                # Get route tables
                $routeTables = Get-VpcRouteTables -Region $region -VpcId $vpcId
                $rtCount = $routeTables.Count

                "$region,$vpcId,$vpcName,$existingEndpoint,Already Exists,$rtCount,0,Endpoint already exists" | Out-File -FilePath $CsvOutput -Append -Encoding UTF8
                "  [SKIP] $region - $vpcId ($vpcName) - Already exists: $existingEndpoint" | Out-File -FilePath $SummaryFile -Append -Encoding UTF8
                $EndpointsExisting++

                # Check routes
                Write-Host "  Checking routes in $rtCount route table(s)..."
                foreach ($rtId in $routeTables) {
                    if (-not (Test-RouteExists -Region $region -RouteTableId $rtId -PrefixListId $prefixListId)) {
                        Write-Host "    Adding missing route to $rtId..." -ForegroundColor Blue
                        Add-RouteToTable -Region $region -RouteTableId $rtId -GatewayEndpointId $existingEndpoint -PrefixListId $prefixListId
                    } else {
                        Write-Host "    ✓ Route exists in $rtId" -ForegroundColor Green
                        $RoutesExisting++
                    }
                }

                continue
            }

            # Create gateway endpoint
            $null = New-GatewayEndpoint -Region $region -VpcId $vpcId -VpcName $vpcName -Service $ServiceName
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
Service: $ServiceName

Endpoints created: $EndpointsCreated
Endpoints already existed: $EndpointsExisting
Endpoints failed: $EndpointsFailed

Routes added: $RoutesAdded
Routes already existed: $RoutesExisting
Routes failed: $RoutesFailed

"@ | Out-File -FilePath $SummaryFile -Append -Encoding UTF8

# Display summary
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Total regions checked: $TotalRegions"
Write-Host "Total VPCs found: $TotalVpcs"
Write-Host "Service: $ServiceName"
Write-Host ""
Write-Host "Endpoints created: " -NoNewline
Write-Host "$EndpointsCreated" -ForegroundColor Green
Write-Host "Endpoints already existed: " -NoNewline
Write-Host "$EndpointsExisting" -ForegroundColor Yellow
if ($EndpointsFailed -gt 0) {
    Write-Host "Endpoints failed: " -NoNewline
    Write-Host "$EndpointsFailed" -ForegroundColor Red
}
Write-Host ""
Write-Host "Routes added: " -NoNewline
Write-Host "$RoutesAdded" -ForegroundColor Green
Write-Host "Routes already existed: " -NoNewline
Write-Host "$RoutesExisting" -ForegroundColor Yellow
if ($RoutesFailed -gt 0) {
    Write-Host "Routes failed: " -NoNewline
    Write-Host "$RoutesFailed" -ForegroundColor Red
}
Write-Host ""
Write-Host "Output files:"
Write-Host "  Summary: $SummaryFile"
Write-Host "  CSV:     $CsvOutput"
Write-Host ""

if ($DryRun) {
    Write-Host "This was a dry run. No changes were made." -ForegroundColor Blue
    Write-Host "Run without -DryRun to actually create endpoints."
    Write-Host ""
}

if ($EndpointsCreated -gt 0 -or $RoutesAdded -gt 0) {
    Write-Host "✓ Gateway endpoints setup complete!" -ForegroundColor Green
} elseif ($EndpointsExisting -eq $TotalVpcs -and $TotalVpcs -gt 0) {
    Write-Host "All VPCs already have gateway endpoints configured." -ForegroundColor Yellow
} elseif ($EndpointsFailed -gt 0 -or $RoutesFailed -gt 0) {
    Write-Host "Some operations failed. Check the summary for details." -ForegroundColor Red
    exit 1
}

Write-Host "==========================================" -ForegroundColor Cyan
