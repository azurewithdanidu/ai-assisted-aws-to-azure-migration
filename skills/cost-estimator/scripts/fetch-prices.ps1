#Requires -Version 7.0
<#
.SYNOPSIS
    Queries the Azure Retail Prices API for a service, region, and optional SKU.

.DESCRIPTION
    Builds an OData filter and calls the Azure Retail Prices API with no
    authentication. Results are sorted by retailPrice ascending and printed as a
    table for quick review.

.PARAMETER ServiceName
    Azure service name to query.

.PARAMETER ArmRegion
    Azure ARM region name. Defaults to australiaeast.

.PARAMETER SkuName
    Optional SKU substring filter.

.EXAMPLE
    .\fetch-prices.ps1 -ServiceName "Azure Functions" -ArmRegion australiaeast

.EXAMPLE
    .\fetch-prices.ps1 -ServiceName "Azure Database for PostgreSQL" -ArmRegion australiaeast -SkuName "Flexible Server"
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$ServiceName = '',

    [Parameter(Position = 1)]
    [ValidateNotNullOrEmpty()]
    [string]$ArmRegion = 'australiaeast',

    [Parameter(Position = 2)]
    [string]$SkuName = '',

    [switch]$Help
)

$ErrorActionPreference = 'Stop'
$apiBaseUrl = 'https://prices.azure.com/api/retail/prices'
$apiVersion = '2023-01-01-preview'

function Show-Usage {
    @"
Usage: ./fetch-prices.ps1 <SERVICE_NAME> [ARM_REGION] [SKU_NAME]

Query the Azure Retail Prices API for a service, region, and optional SKU filter.

Examples:
  ./fetch-prices.ps1 "Azure Functions" australiaeast
  ./fetch-prices.ps1 "Azure Database for PostgreSQL" australiaeast "Flexible Server"
"@ | Write-Host
}

function Build-Filter {
    param(
        [string]$RequestedServiceName,
        [string]$RequestedArmRegion,
        [string]$RequestedSkuName
    )

    $escapedService = $RequestedServiceName.Replace("'", "''")
    $escapedRegion = $RequestedArmRegion.Replace("'", "''")
    $filter = "serviceName eq '$escapedService' and armRegionName eq '$escapedRegion'"

    if (-not [string]::IsNullOrWhiteSpace($RequestedSkuName)) {
        $escapedSku = $RequestedSkuName.Replace("'", "''")
        $filter += " and contains(skuName,'$escapedSku')"
    }

    return $filter
}

function Invoke-PriceQuery {
    param([string]$Filter)

    $encodedFilter = [System.Uri]::EscapeDataString($Filter)
    $requestUrl = "${apiBaseUrl}?api-version=$apiVersion&`$filter=$encodedFilter"
    $items = [System.Collections.Generic.List[object]]::new()
    $page = 1

    Write-Host "==> Filter: $Filter" -ForegroundColor Cyan
    while (-not [string]::IsNullOrWhiteSpace($requestUrl)) {
        Write-Host "==> Fetching page $page" -ForegroundColor Cyan
        $response = Invoke-RestMethod -Method Get -Uri $requestUrl
        foreach ($item in @($response.Items)) {
            [void]$items.Add($item)
        }

        $requestUrl = $response.NextPageLink
        $page++
    }

    return ,$items
}

if ($Help) {
    Show-Usage
    exit 0
}

if ([string]::IsNullOrWhiteSpace($ServiceName)) {
    Show-Usage
    Write-Error 'SERVICE_NAME is required.'
    exit 1
}

Write-Host '==> Querying Azure Retail Prices API' -ForegroundColor Cyan

try {
    $filter = Build-Filter -RequestedServiceName $ServiceName -RequestedArmRegion $ArmRegion -RequestedSkuName $SkuName
    $allItems = Invoke-PriceQuery -Filter $filter
} catch {
    Write-Error 'Azure Retail Prices API request failed.'
    exit 1
}

if ($allItems.Count -eq 0) {
    if ($ServiceName.StartsWith('Azure ')) {
        $fallbackServiceName = $ServiceName.Substring(6)
        Write-Host "==> No results for '$ServiceName'. Retrying with '$fallbackServiceName'." -ForegroundColor Yellow
        try {
            $filter = Build-Filter -RequestedServiceName $fallbackServiceName -RequestedArmRegion $ArmRegion -RequestedSkuName $SkuName
            $allItems = Invoke-PriceQuery -Filter $filter
        } catch {
            Write-Error 'Azure Retail Prices API request failed during fallback lookup.'
            exit 1
        }
    }
}

if ($allItems.Count -eq 0) {
    Write-Error "No pricing results returned for service '$ServiceName' in region '$ArmRegion'."
    exit 1
}

Write-Host ''
$table = $allItems |
    Sort-Object retailPrice |
    Select-Object @{
        Name = 'SKU'; Expression = { $_.skuName }
    }, @{
        Name = 'Meter'; Expression = { $_.meterName }
    }, @{
        Name = 'Retail Price (USD)'; Expression = { $_.retailPrice }
    }, @{
        Name = 'Unit'; Expression = { $_.unitOfMeasure }
    } |
    Format-Table -AutoSize |
    Out-String

Write-Host $table
Write-Host "✅ Retrieved $($allItems.Count) price meter(s)." -ForegroundColor Green
exit 0
