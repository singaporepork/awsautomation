# Script to identify custom parameters in an RDS parameter group
# Takes region and parameter group name as arguments
# Filters out system parameters and shows custom parameter values with defaults

param(
    [Parameter(Mandatory=$true)]
    [string]$Region,

    [Parameter(Mandatory=$true)]
    [string]$ParameterGroupName
)

# Function to display error and exit
function Write-Error-Exit {
    param([string]$Message)
    Write-Host "Error: $Message" -ForegroundColor Red
    exit 1
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "RDS Custom Parameters Report" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Check if AWS CLI is installed
try {
    $null = Get-Command aws -ErrorAction Stop
} catch {
    Write-Error-Exit "AWS CLI is not installed. Please install AWS CLI from: https://aws.amazon.com/cli/"
}

# Check AWS credentials
try {
    $null = aws sts get-caller-identity 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error-Exit "AWS credentials not configured or invalid. Please run 'aws configure' to set up your credentials"
    }
} catch {
    Write-Error-Exit "AWS credentials not configured or invalid"
}

# Get Account ID
$AccountId = (aws sts get-caller-identity --query 'Account' --output text)
Write-Host "AWS Account ID: $AccountId"
Write-Host "Region: $Region"
Write-Host "Parameter Group: $ParameterGroupName"
Write-Host "Report Date: $(Get-Date)"
Write-Host ""

# Verify the parameter group exists
Write-Host "Verifying parameter group..."
try {
    $null = aws rds describe-db-parameter-groups `
        --region $Region `
        --db-parameter-group-name $ParameterGroupName `
        --output json 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Error-Exit "Parameter group '$ParameterGroupName' not found in region '$Region'"
    }
} catch {
    Write-Error-Exit "Parameter group '$ParameterGroupName' not found in region '$Region'"
}

# Get parameter group details
$ParamGroupDetails = aws rds describe-db-parameter-groups `
    --region $Region `
    --db-parameter-group-name $ParameterGroupName `
    --output json | ConvertFrom-Json

$ParamFamily = $ParamGroupDetails.DBParameterGroups[0].DBParameterGroupFamily
$Description = $ParamGroupDetails.DBParameterGroups[0].Description

Write-Host "✓ Parameter group found" -ForegroundColor Green
Write-Host "  Family: $ParamFamily"
Write-Host "  Description: $Description"
Write-Host ""

# Get all parameters from the parameter group
Write-Host "Fetching parameters..."
$ParamsJson = aws rds describe-db-parameters `
    --region $Region `
    --db-parameter-group-name $ParameterGroupName `
    --output json | ConvertFrom-Json

$TotalParams = $ParamsJson.Parameters.Count
Write-Host "✓ Retrieved $TotalParams total parameters" -ForegroundColor Green
Write-Host ""

# Filter for custom parameters (excluding source=system)
$CustomParams = $ParamsJson.Parameters | Where-Object { $_.Source -ne "system" }
$CustomCount = ($CustomParams | Measure-Object).Count

if ($CustomCount -eq 0) {
    Write-Host "No custom parameters found (all parameters are using system/default values)" -ForegroundColor Yellow
    exit 0
}

Write-Host "Found $CustomCount custom parameter(s):" -ForegroundColor Cyan
Write-Host ""

# Get the default parameter group for comparison
$DefaultParamGroup = "default.$ParamFamily"
Write-Host "Attempting to fetch default values from '$DefaultParamGroup'..."

$DefaultParamsJson = $null
try {
    $null = aws rds describe-db-parameters `
        --region $Region `
        --db-parameter-group-name $DefaultParamGroup `
        --output json 2>&1

    if ($LASTEXITCODE -eq 0) {
        $DefaultParamsJson = aws rds describe-db-parameters `
            --region $Region `
            --db-parameter-group-name $DefaultParamGroup `
            --output json | ConvertFrom-Json
        Write-Host "✓ Default parameter group values retrieved" -ForegroundColor Green
    } else {
        Write-Host "⚠ Could not retrieve default parameter group (will show allowed values instead)" -ForegroundColor Yellow
    }
} catch {
    Write-Host "⚠ Could not retrieve default parameter group (will show allowed values instead)" -ForegroundColor Yellow
}
Write-Host ""

# Display custom parameters
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "CUSTOM PARAMETERS" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

$i = 0
foreach ($Param in $CustomParams) {
    $i++
    $ParamName = $Param.ParameterName
    $ParamValue = if ($Param.ParameterValue) { $Param.ParameterValue } else { "N/A" }
    $ParamSource = $Param.Source
    $ParamType = $Param.DataType
    $ParamDesc = if ($Param.Description) { $Param.Description } else { "No description" }
    $ParamModifiable = $Param.IsModifiable
    $ParamApplyType = if ($Param.ApplyType) { $Param.ApplyType } else { "N/A" }
    $AllowedValues = if ($Param.AllowedValues) { $Param.AllowedValues } else { "N/A" }

    Write-Host "[$i/$CustomCount] $ParamName" -ForegroundColor Yellow
    Write-Host "  Current Value: " -NoNewline
    Write-Host "$ParamValue" -ForegroundColor Green
    Write-Host "  Source: $ParamSource"
    Write-Host "  Data Type: $ParamType"
    Write-Host "  Modifiable: $ParamModifiable"
    Write-Host "  Apply Type: $ParamApplyType"

    # Try to get default value
    if ($DefaultParamsJson) {
        $DefaultParam = $DefaultParamsJson.Parameters | Where-Object { $_.ParameterName -eq $ParamName }

        if ($DefaultParam -and $DefaultParam.ParameterValue) {
            $DefaultValue = $DefaultParam.ParameterValue

            if ($DefaultValue -eq $ParamValue) {
                Write-Host "  Default Value: $DefaultValue " -NoNewline
                Write-Host "(matches current)" -ForegroundColor Cyan
            } else {
                Write-Host "  Default Value: " -NoNewline
                Write-Host "$DefaultValue" -ForegroundColor Blue
            }
        } else {
            Write-Host "  Default Value: Not available"
        }
    }

    # Show allowed values if available
    if ($AllowedValues -ne "N/A" -and $AllowedValues.Length -lt 200) {
        Write-Host "  Allowed Values: $AllowedValues"
    }

    # Show description
    Write-Host "  Description: $ParamDesc"
    Write-Host ""
}

# Summary
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Total parameters: $TotalParams"
Write-Host "Custom parameters: $CustomCount"
Write-Host "System parameters: $($TotalParams - $CustomCount)"
Write-Host ""

# Create CSV output
$OutputCsv = "rds-custom-params-$ParameterGroupName-$Region.csv"
Write-Host "Generating CSV report: $OutputCsv"

$CsvContent = @()
$CsvContent += "Parameter Name,Current Value,Default Value,Source,Data Type,Modifiable,Apply Type,Description"

foreach ($Param in $CustomParams) {
    $ParamName = $Param.ParameterName
    $ParamValue = if ($Param.ParameterValue) { $Param.ParameterValue } else { "N/A" }
    $ParamSource = $Param.Source
    $ParamType = $Param.DataType
    $ParamDesc = if ($Param.Description) { $Param.Description.Replace('"', '""') } else { "No description" }
    $ParamModifiable = $Param.IsModifiable
    $ParamApplyType = if ($Param.ApplyType) { $Param.ApplyType } else { "N/A" }

    # Get default value
    $DefaultValue = "N/A"
    if ($DefaultParamsJson) {
        $DefaultParam = $DefaultParamsJson.Parameters | Where-Object { $_.ParameterName -eq $ParamName }
        if ($DefaultParam -and $DefaultParam.ParameterValue) {
            $DefaultValue = $DefaultParam.ParameterValue
        }
    }

    $CsvContent += "`"$ParamName`",`"$ParamValue`",`"$DefaultValue`",`"$ParamSource`",`"$ParamType`",`"$ParamModifiable`",`"$ParamApplyType`",`"$ParamDesc`""
}

$CsvContent | Out-File -FilePath $OutputCsv -Encoding UTF8

Write-Host "✓ CSV report saved to: $OutputCsv" -ForegroundColor Green
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
