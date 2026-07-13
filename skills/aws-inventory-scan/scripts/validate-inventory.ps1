#Requires -Version 7.0
<#
.SYNOPSIS
    Validates aws-inventory.json before downstream agents consume it.

.DESCRIPTION
    Checks that the inventory file exists, is non-empty, parses as JSON, has the
    required top-level schema, contains at least one service, and that each
    service/resource entry contains the required fields.

.PARAMETER InventoryPath
    Path to the inventory JSON file.
    Defaults to outputs/aws-migration-artifacts/aws-inventory.json.

.EXAMPLE
    .\validate-inventory.ps1

.EXAMPLE
    .\validate-inventory.ps1 -InventoryPath "outputs/aws-migration-artifacts/aws-inventory.json"
#>

[CmdletBinding()]
param(
    [string]$InventoryPath = 'outputs/aws-migration-artifacts/aws-inventory.json',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

function Show-Usage {
    @"
Usage: ./validate-inventory.ps1 [-InventoryPath <path>]

Validate an AWS inventory JSON file before downstream agents consume it.

Checks:
  - File exists and is non-empty
  - JSON parses successfully
  - Top-level keys exist: discovery_timestamp, aws_account_id, aws_region, services
  - services object contains at least one service
  - Each service has service_type, count, and resources[]
  - Each resource has name (or id), arn (or equivalent), and region
"@ | Write-Host
}

function Stop-Validation {
    param([string]$Message)

    Write-Error $Message
    exit 1
}

function Test-PropertyValue {
    param(
        [object]$Object,
        [string]$Name
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $false
    }

    if ($property.Value -is [string]) {
        return -not [string]::IsNullOrWhiteSpace($property.Value)
    }

    return $null -ne $property.Value
}

function Get-FirstPropertyValue {
    param(
        [object]$Object,
        [string[]]$Names
    )

    foreach ($name in $Names) {
        $property = $Object.PSObject.Properties[$name]
        if ($null -ne $property -and -not [string]::IsNullOrWhiteSpace([string]$property.Value)) {
            return [string]$property.Value
        }
    }

    return $null
}

if ($Help) {
    Show-Usage
    exit 0
}

Write-Host "==> Validating inventory file: $InventoryPath" -ForegroundColor Cyan

if (-not (Test-Path $InventoryPath -PathType Leaf)) {
    Stop-Validation "Inventory file not found: $InventoryPath"
}

$fileInfo = Get-Item $InventoryPath
if ($fileInfo.Length -le 0) {
    Stop-Validation "Inventory file is empty: $InventoryPath"
}

Write-Host '==> Checking JSON syntax' -ForegroundColor Cyan
try {
    $rawInventory = Get-Content $InventoryPath -Raw
    $inventory = $rawInventory | ConvertFrom-Json
} catch {
    Stop-Validation "Inventory file is not valid JSON: $InventoryPath"
}

Write-Host '==> Checking top-level schema' -ForegroundColor Cyan
foreach ($requiredKey in @('discovery_timestamp', 'aws_account_id', 'aws_region', 'services')) {
    if (-not (Test-PropertyValue -Object $inventory -Name $requiredKey)) {
        Stop-Validation "Missing required top-level key: $requiredKey"
    }
}

$serviceEntries = @($inventory.services.PSObject.Properties)
if ($serviceEntries.Count -eq 0) {
    Stop-Validation "The services object must contain at least one service entry."
}

Write-Host '==> Checking service entries' -ForegroundColor Cyan
$totalResources = 0
foreach ($serviceEntry in $serviceEntries) {
    $serviceName = $serviceEntry.Name
    $service = $serviceEntry.Value

    if (-not (Test-PropertyValue -Object $service -Name 'service_type')) {
        Stop-Validation "Service '$serviceName' is missing required field: service_type"
    }

    $parsedCount = 0
    $countProperty = $service.PSObject.Properties['count']
    if ($null -eq $countProperty -or -not [int]::TryParse([string]$countProperty.Value, [ref]$parsedCount) -or $parsedCount -lt 0) {
        Stop-Validation "Service '$serviceName' is missing a valid numeric count field."
    }

    if (-not ($service.PSObject.Properties.Name -contains 'resources') -or $service.resources -isnot [System.Array]) {
        Stop-Validation "Service '$serviceName' must include a resources array."
    }

    $resources = @($service.resources)
    $totalResources += $resources.Count

    for ($index = 0; $index -lt $resources.Count; $index++) {
        $resource = $resources[$index]
        if ($resource -isnot [pscustomobject]) {
            Stop-Validation "Service '$serviceName' resource[$index] must be a JSON object."
        }

        $nameOrId = Get-FirstPropertyValue -Object $resource -Names @('name', 'id', 'identifier')
        if (-not $nameOrId) {
            Stop-Validation "Service '$serviceName' resource[$index] is missing name or id"
        }

        $arnEquivalent = Get-FirstPropertyValue -Object $resource -Names @('arn', 'resource_arn', 'resource_id', 'identifier', 'url')
        if (-not $arnEquivalent) {
            Stop-Validation "Service '$serviceName' resource[$index] is missing arn or equivalent identifier"
        }

        $region = Get-FirstPropertyValue -Object $resource -Names @('region')
        if (-not $region) {
            Stop-Validation "Service '$serviceName' resource[$index] is missing region"
        }
    }
}

Write-Host "✅ Inventory valid: $($serviceEntries.Count) services, $totalResources total resources" -ForegroundColor Green
exit 0
