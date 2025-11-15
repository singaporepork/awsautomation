#Requires -Version 5.0

<#
.SYNOPSIS
    Identifies all AWS resources with public IP addresses across all VPCs in all regions

.DESCRIPTION
    This script scans your entire AWS account across all regions to find resources that
    have public IP addresses or are publicly accessible. It helps identify potential
    security exposure points in your AWS infrastructure.

.EXAMPLE
    .\find-public-ip-resources.ps1

.EXAMPLE
    .\find-public-ip-resources.ps1 -OutputPath "C:\Reports"

.NOTES
    Requires AWS CLI to be installed and configured
    Compatible with PowerShell 5.0 and later
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$OutputPath = "."
)

# Set strict mode
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Output files
$CsvOutput = Join-Path $OutputPath "public-ip-resources.csv"
$JsonOutput = Join-Path $OutputPath "public-ip-resources.json"
$ReportFile = Join-Path $OutputPath "public-ip-resources-report.txt"

# Counters
$TotalResources = 0
$TotalRegionsChecked = 0

# Resource collection
$Resources = @()

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Public IP Resources Inventory" -ForegroundColor Cyan
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

# Get AWS account ID
$AccountIdJson = aws sts get-caller-identity --query 'Account' --output json 2>&1
$AccountId = $AccountIdJson | ConvertFrom-Json
Write-Host "AWS Account: $AccountId"
Write-Host ""

# Function to get VPC name from tags
function Get-VpcName {
    param(
        [string]$Region,
        [string]$VpcId
    )

    if ([string]::IsNullOrEmpty($VpcId) -or $VpcId -eq "null") {
        return "N/A"
    }

    try {
        $vpcJson = aws ec2 describe-vpcs `
            --region $Region `
            --vpc-ids $VpcId `
            --query 'Vpcs[0].Tags[?Key==`Name`].Value' `
            --output json 2>&1

        if ($LASTEXITCODE -eq 0) {
            $vpcName = $vpcJson | ConvertFrom-Json
            if ($vpcName -and $vpcName.Count -gt 0) {
                return $vpcName[0]
            }
        }
    } catch {
        # Ignore errors
    }

    return "Unnamed"
}

# Function to add resource to collection
function Add-Resource {
    param(
        [string]$Region,
        [string]$VpcId,
        [string]$VpcName,
        [string]$ResourceType,
        [string]$ResourceId,
        [string]$ResourceName,
        [string]$PublicIp,
        [string]$PublicDns,
        [string]$State,
        [string]$AdditionalInfo = ""
    )

    $script:Resources += [PSCustomObject]@{
        Region         = $Region
        VpcId          = $VpcId
        VpcName        = $VpcName
        ResourceType   = $ResourceType
        ResourceId     = $ResourceId
        ResourceName   = $ResourceName
        PublicIp       = $PublicIp
        PublicDns      = $PublicDns
        State          = $State
        AdditionalInfo = $AdditionalInfo
    }

    $script:TotalResources++
}

# Function to check EC2 instances
function Get-Ec2InstancesWithPublicIp {
    param([string]$Region)

    Write-Host "  Checking EC2 instances... " -NoNewline

    try {
        $instancesJson = aws ec2 describe-instances `
            --region $Region `
            --query 'Reservations[].Instances[?PublicIpAddress!=`null`].[InstanceId,VpcId,Tags[?Key==`Name`].Value|[0],PublicIpAddress,PublicDnsName,State.Name,InstanceType,PrivateIpAddress]' `
            --output json 2>&1

        if ($LASTEXITCODE -eq 0) {
            $instances = $instancesJson | ConvertFrom-Json
            $count = 0

            if ($instances) {
                foreach ($instance in $instances) {
                    $instanceId = $instance[0]
                    $vpcId = $instance[1]
                    $name = if ($instance[2]) { $instance[2] } else { "Unnamed" }
                    $publicIp = $instance[3]
                    $publicDns = $instance[4]
                    $state = $instance[5]
                    $instanceType = $instance[6]
                    $privateIp = $instance[7]

                    $vpcName = Get-VpcName -Region $Region -VpcId $vpcId

                    Add-Resource -Region $Region -VpcId $vpcId -VpcName $vpcName `
                        -ResourceType "EC2 Instance" -ResourceId $instanceId -ResourceName $name `
                        -PublicIp $publicIp -PublicDns $publicDns -State $state `
                        -AdditionalInfo "Type: $instanceType, Private IP: $privateIp"

                    $count++
                }
            }

            Write-Host "$count found" -ForegroundColor Green
        } else {
            Write-Host "0 found" -ForegroundColor Green
        }
    } catch {
        Write-Host "Error" -ForegroundColor Red
    }
}

# Function to check NAT Gateways
function Get-NatGatewaysWithPublicIp {
    param([string]$Region)

    Write-Host "  Checking NAT Gateways... " -NoNewline

    try {
        $natGatewaysJson = aws ec2 describe-nat-gateways `
            --region $Region `
            --query 'NatGateways[?State==`available`].[NatGatewayId,VpcId,Tags[?Key==`Name`].Value|[0],NatGatewayAddresses[0].PublicIp,State,SubnetId]' `
            --output json 2>&1

        if ($LASTEXITCODE -eq 0) {
            $natGateways = $natGatewaysJson | ConvertFrom-Json
            $count = 0

            if ($natGateways) {
                foreach ($nat in $natGateways) {
                    $natId = $nat[0]
                    $vpcId = $nat[1]
                    $name = if ($nat[2]) { $nat[2] } else { "Unnamed" }
                    $publicIp = $nat[3]
                    $state = $nat[4]
                    $subnetId = $nat[5]

                    $vpcName = Get-VpcName -Region $Region -VpcId $vpcId

                    Add-Resource -Region $Region -VpcId $vpcId -VpcName $vpcName `
                        -ResourceType "NAT Gateway" -ResourceId $natId -ResourceName $name `
                        -PublicIp $publicIp -PublicDns "N/A" -State $state `
                        -AdditionalInfo "Subnet: $subnetId"

                    $count++
                }
            }

            Write-Host "$count found" -ForegroundColor Green
        } else {
            Write-Host "0 found" -ForegroundColor Green
        }
    } catch {
        Write-Host "Error" -ForegroundColor Red
    }
}

# Function to check Elastic IPs
function Get-ElasticIps {
    param([string]$Region)

    Write-Host "  Checking Elastic IPs... " -NoNewline

    try {
        $eipsJson = aws ec2 describe-addresses `
            --region $Region `
            --query 'Addresses[].[AllocationId,PublicIp,InstanceId,NetworkInterfaceId,AssociationId,Domain,Tags[?Key==`Name`].Value|[0],PrivateIpAddress]' `
            --output json 2>&1

        if ($LASTEXITCODE -eq 0) {
            $eips = $eipsJson | ConvertFrom-Json
            $count = 0

            if ($eips) {
                foreach ($eip in $eips) {
                    $allocationId = $eip[0]
                    $publicIp = $eip[1]
                    $instanceId = if ($eip[2]) { $eip[2] } else { "Unassociated" }
                    $eniId = if ($eip[3]) { $eip[3] } else { "N/A" }
                    $associationId = if ($eip[4]) { $eip[4] } else { "N/A" }
                    $domain = $eip[5]
                    $name = if ($eip[6]) { $eip[6] } else { "Unnamed" }
                    $privateIp = if ($eip[7]) { $eip[7] } else { "N/A" }

                    # Try to get VPC from instance or ENI
                    $vpcId = "N/A"
                    if ($instanceId -ne "Unassociated") {
                        try {
                            $vpcIdJson = aws ec2 describe-instances `
                                --region $Region `
                                --instance-ids $instanceId `
                                --query 'Reservations[0].Instances[0].VpcId' `
                                --output json 2>&1

                            if ($LASTEXITCODE -eq 0) {
                                $vpcId = $vpcIdJson | ConvertFrom-Json
                            }
                        } catch {
                            # Ignore errors
                        }
                    } elseif ($eniId -ne "N/A") {
                        try {
                            $vpcIdJson = aws ec2 describe-network-interfaces `
                                --region $Region `
                                --network-interface-ids $eniId `
                                --query 'NetworkInterfaces[0].VpcId' `
                                --output json 2>&1

                            if ($LASTEXITCODE -eq 0) {
                                $vpcId = $vpcIdJson | ConvertFrom-Json
                            }
                        } catch {
                            # Ignore errors
                        }
                    }

                    $vpcName = Get-VpcName -Region $Region -VpcId $vpcId

                    $state = if ($instanceId -eq "Unassociated") { "Unassociated" } else { "Associated" }

                    Add-Resource -Region $Region -VpcId $vpcId -VpcName $vpcName `
                        -ResourceType "Elastic IP" -ResourceId $allocationId -ResourceName $name `
                        -PublicIp $publicIp -PublicDns "N/A" -State $state `
                        -AdditionalInfo "Instance: $instanceId, ENI: $eniId, Private IP: $privateIp"

                    $count++
                }
            }

            Write-Host "$count found" -ForegroundColor Green
        } else {
            Write-Host "0 found" -ForegroundColor Green
        }
    } catch {
        Write-Host "Error" -ForegroundColor Red
    }
}

# Function to check Classic Load Balancers
function Get-ClassicLoadBalancers {
    param([string]$Region)

    Write-Host "  Checking Classic Load Balancers... " -NoNewline

    try {
        $elbsJson = aws elb describe-load-balancers `
            --region $Region `
            --query 'LoadBalancerDescriptions[?Scheme==`internet-facing`].[LoadBalancerName,DNSName,VPCId,Scheme,Instances[].InstanceId|join(`,`,@)]' `
            --output json 2>&1

        if ($LASTEXITCODE -eq 0) {
            $elbs = $elbsJson | ConvertFrom-Json
            $count = 0

            if ($elbs) {
                foreach ($elb in $elbs) {
                    $lbName = $elb[0]
                    $dnsName = $elb[1]
                    $vpcId = if ($elb[2]) { $elb[2] } else { "EC2-Classic" }
                    $scheme = $elb[3]
                    $instances = if ($elb[4]) { $elb[4] } else { "None" }

                    $vpcName = Get-VpcName -Region $Region -VpcId $vpcId

                    Add-Resource -Region $Region -VpcId $vpcId -VpcName $vpcName `
                        -ResourceType "Classic Load Balancer" -ResourceId $lbName -ResourceName $lbName `
                        -PublicIp "N/A (DNS-based)" -PublicDns $dnsName -State "Active" `
                        -AdditionalInfo "Scheme: $scheme, Instances: $instances"

                    $count++
                }
            }

            Write-Host "$count found" -ForegroundColor Green
        } else {
            Write-Host "0 found" -ForegroundColor Green
        }
    } catch {
        Write-Host "Error" -ForegroundColor Red
    }
}

# Function to check Application/Network Load Balancers
function Get-AlbNlb {
    param([string]$Region)

    Write-Host "  Checking ALB/NLB Load Balancers... " -NoNewline

    try {
        $lbsJson = aws elbv2 describe-load-balancers `
            --region $Region `
            --query 'LoadBalancers[?Scheme==`internet-facing`].[LoadBalancerArn,LoadBalancerName,DNSName,VpcId,Type,State.Code]' `
            --output json 2>&1

        if ($LASTEXITCODE -eq 0) {
            $lbs = $lbsJson | ConvertFrom-Json
            $count = 0

            if ($lbs) {
                foreach ($lb in $lbs) {
                    $lbArn = $lb[0]
                    $lbName = $lb[1]
                    $dnsName = $lb[2]
                    $vpcId = $lb[3]
                    $lbType = $lb[4]
                    $state = $lb[5]

                    $vpcName = Get-VpcName -Region $Region -VpcId $vpcId

                    $resourceType = "Application Load Balancer"
                    if ($lbType -eq "network") {
                        $resourceType = "Network Load Balancer"
                    } elseif ($lbType -eq "gateway") {
                        $resourceType = "Gateway Load Balancer"
                    }

                    Add-Resource -Region $Region -VpcId $vpcId -VpcName $vpcName `
                        -ResourceType $resourceType -ResourceId $lbName -ResourceName $lbName `
                        -PublicIp "N/A (DNS-based)" -PublicDns $dnsName -State $state `
                        -AdditionalInfo "Type: $lbType"

                    $count++
                }
            }

            Write-Host "$count found" -ForegroundColor Green
        } else {
            Write-Host "0 found" -ForegroundColor Green
        }
    } catch {
        Write-Host "Error" -ForegroundColor Red
    }
}

# Function to check RDS instances
function Get-RdsInstances {
    param([string]$Region)

    Write-Host "  Checking RDS instances... " -NoNewline

    try {
        $rdsInstancesJson = aws rds describe-db-instances `
            --region $Region `
            --query 'DBInstances[?PubliclyAccessible==`true`].[DBInstanceIdentifier,Endpoint.Address,DBSubnetGroup.VpcId,DBInstanceStatus,Engine,DBInstanceClass]' `
            --output json 2>&1

        if ($LASTEXITCODE -eq 0) {
            $rdsInstances = $rdsInstancesJson | ConvertFrom-Json
            $count = 0

            if ($rdsInstances) {
                foreach ($rds in $rdsInstances) {
                    $dbId = $rds[0]
                    $endpoint = if ($rds[1]) { $rds[1] } else { "N/A" }
                    $vpcId = if ($rds[2]) { $rds[2] } else { "N/A" }
                    $status = $rds[3]
                    $engine = $rds[4]
                    $instanceClass = $rds[5]

                    $vpcName = Get-VpcName -Region $Region -VpcId $vpcId

                    Add-Resource -Region $Region -VpcId $vpcId -VpcName $vpcName `
                        -ResourceType "RDS Instance" -ResourceId $dbId -ResourceName $dbId `
                        -PublicIp "N/A (Endpoint-based)" -PublicDns $endpoint -State $status `
                        -AdditionalInfo "Engine: $engine, Class: $instanceClass"

                    $count++
                }
            }

            Write-Host "$count found" -ForegroundColor Green
        } else {
            Write-Host "0 found" -ForegroundColor Green
        }
    } catch {
        Write-Host "Error" -ForegroundColor Red
    }
}

# Function to check Network Interfaces with public IPs
function Get-NetworkInterfaces {
    param([string]$Region)

    Write-Host "  Checking Network Interfaces... " -NoNewline

    try {
        $enisJson = aws ec2 describe-network-interfaces `
            --region $Region `
            --query 'NetworkInterfaces[?Association.PublicIp!=`null`].[NetworkInterfaceId,VpcId,Association.PublicIp,Association.PublicDnsName,Status,Description,InterfaceType,Attachment.InstanceId]' `
            --output json 2>&1

        if ($LASTEXITCODE -eq 0) {
            $enis = $enisJson | ConvertFrom-Json
            $count = 0

            if ($enis) {
                foreach ($eni in $enis) {
                    $eniId = $eni[0]
                    $vpcId = $eni[1]
                    $publicIp = $eni[2]
                    $publicDns = if ($eni[3]) { $eni[3] } else { "N/A" }
                    $status = $eni[4]
                    $description = $eni[5]
                    $interfaceType = $eni[6]
                    $instanceId = if ($eni[7]) { $eni[7] } else { "Not attached" }

                    # Skip if already counted as NAT gateway
                    if ($description -match "NAT Gateway") {
                        continue
                    }

                    $vpcName = Get-VpcName -Region $Region -VpcId $vpcId

                    Add-Resource -Region $Region -VpcId $vpcId -VpcName $vpcName `
                        -ResourceType "Network Interface" -ResourceId $eniId -ResourceName $description `
                        -PublicIp $publicIp -PublicDns $publicDns -State $status `
                        -AdditionalInfo "Type: $interfaceType, Instance: $instanceId"

                    $count++
                }
            }

            Write-Host "$count found" -ForegroundColor Green
        } else {
            Write-Host "0 found" -ForegroundColor Green
        }
    } catch {
        Write-Host "Error" -ForegroundColor Red
    }
}

# Get all regions
Write-Host "Fetching AWS regions..." -ForegroundColor White
$regionsJson = aws ec2 describe-regions --query 'Regions[].RegionName' --output json 2>&1
$regions = $regionsJson | ConvertFrom-Json
$regionCount = $regions.Count
Write-Host "Found $regionCount regions to check" -ForegroundColor White
Write-Host ""

# Process each region
foreach ($region in $regions) {
    Write-Host "Checking region: $region" -ForegroundColor Cyan
    $TotalRegionsChecked++

    Get-Ec2InstancesWithPublicIp -Region $region
    Get-NatGatewaysWithPublicIp -Region $region
    Get-ElasticIps -Region $region
    Get-ClassicLoadBalancers -Region $region
    Get-AlbNlb -Region $region
    Get-RdsInstances -Region $region
    Get-NetworkInterfaces -Region $region

    Write-Host ""
}

# Export to CSV
Write-Host "Generating CSV output..." -ForegroundColor White
$Resources | Export-Csv -Path $CsvOutput -NoTypeInformation -Encoding UTF8

# Export to JSON
Write-Host "Generating JSON output..." -ForegroundColor White
$jsonData = @{
    resources = $Resources
    metadata  = @{
        generated_at    = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
        account_id      = $AccountId
        total_resources = $TotalResources
        regions_checked = $TotalRegionsChecked
    }
} | ConvertTo-Json -Depth 10

$jsonData | Out-File -FilePath $JsonOutput -Encoding UTF8

# Generate summary report
$reportContent = @"
Public IP Resources Inventory Report
Generated: $(Get-Date)
AWS Account: $AccountId
========================================

SUMMARY
========================================
Total regions checked: $TotalRegionsChecked
Total resources with public IPs: $TotalResources

Resources by type:
"@

$resourcesByType = $Resources | Group-Object -Property ResourceType |
    Select-Object @{Name='Count';Expression={$_.Count}}, @{Name='Type';Expression={$_.Name}} |
    Sort-Object -Property Count -Descending

foreach ($item in $resourcesByType) {
    $reportContent += "`n  $($item.Count) - $($item.Type)"
}

$reportContent += "`n`nResources by region:"

$resourcesByRegion = $Resources | Group-Object -Property Region |
    Select-Object @{Name='Count';Expression={$_.Count}}, @{Name='Region';Expression={$_.Name}} |
    Sort-Object -Property Count -Descending

foreach ($item in $resourcesByRegion) {
    $reportContent += "`n  $($item.Count) - $($item.Region)"
}

$reportContent += "`n`nResources by VPC:"

$resourcesByVpc = $Resources | Group-Object -Property @{Expression={$_.VpcId + "," + $_.VpcName}} |
    Select-Object @{Name='Count';Expression={$_.Count}}, @{Name='VPC';Expression={$_.Name}} |
    Sort-Object -Property Count -Descending

foreach ($item in $resourcesByVpc) {
    $reportContent += "`n  $($item.Count) - $($item.VPC)"
}

$reportContent | Out-File -FilePath $ReportFile -Encoding UTF8

# Display summary
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Total regions checked: $TotalRegionsChecked"
Write-Host "Total resources with public IPs: " -NoNewline
Write-Host "$TotalResources" -ForegroundColor Yellow
Write-Host ""
Write-Host "Output files generated:"
Write-Host "  ✓ CSV:    $CsvOutput" -ForegroundColor Green
Write-Host "  ✓ JSON:   $JsonOutput" -ForegroundColor Green
Write-Host "  ✓ Report: $ReportFile" -ForegroundColor Green
Write-Host ""

if ($TotalResources -gt 0) {
    Write-Host "⚠ Warning: Found resources with public IP addresses" -ForegroundColor Yellow
    Write-Host "Review the output files to assess security exposure"
    Write-Host ""
    Write-Host "Top resource types found:"
    $resourcesByType | Select-Object -First 5 | ForEach-Object {
        Write-Host "     $($_.Count) $($_.Type)"
    }
} else {
    Write-Host "✓ No resources with public IPs found" -ForegroundColor Green
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
