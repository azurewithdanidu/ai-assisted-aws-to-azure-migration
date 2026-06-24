#Requires -Version 7.0
<#
.SYNOPSIS
    Post-deployment security verification for a migrated Azure environment.

.DESCRIPTION
    Runs a series of checks based on the azure-security-patterns skill and
    writes a report to outputs/deployment-validation/security-report.md.

    Checks performed:
      1.  Storage Account — publicNetworkAccess Disabled
      2.  Storage Account — allowBlobPublicAccess false
      3.  Storage Account — requireInfrastructureEncryption true
      4.  Storage Account — supportsHttpsTrafficOnly true
      5.  Key Vault      — publicNetworkAccess Disabled
      6.  Key Vault      — softDeleteEnabled true
      7.  Key Vault      — enablePurgeProtection true
      8.  Key Vault      — enableRbacAuthorization true
      9.  Function App   — httpsOnly true
      10. Function App   — minTlsVersion 1.2 or 1.3
      11. Function App   — No outbound public network access (VNet integrated)
      12. NSG rules      — No rule with 'Allow Any Inbound' on port * from *

    Missing or optional resources are skipped with a WARNING, not a FAIL.

.PARAMETER ResourceGroup
    Azure resource group to inspect.

.PARAMETER Subscription
    Azure subscription ID. Defaults to current az account.

.PARAMETER StorageAccountName
    Storage account to check. Defaults to auto-discovery (first in RG).

.PARAMETER KeyVaultName
    Key Vault to check. Defaults to auto-discovery (first in RG).

.PARAMETER FunctionAppName
    Function App to check. Defaults to auto-discovery (first in RG).

.EXAMPLE
    .\verify-security.ps1 -ResourceGroup "rg-prod-migration"

.EXAMPLE
    .\verify-security.ps1 `
        -ResourceGroup "rg-prod-migration" `
        -StorageAccountName "prodmyappstor" `
        -KeyVaultName "prod-myapp-kv" `
        -FunctionAppName "prod-myapp-func"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)] [string]$ResourceGroup,
    [string]$Subscription       = '',
    [string]$StorageAccountName = '',
    [string]$KeyVaultName       = '',
    [string]$FunctionAppName    = ''
)

$ErrorActionPreference = 'Continue'
$passed = 0; $failed = 0; $warnings = 0
$rows   = [System.Collections.Generic.List[hashtable]]::new()
$outDir = 'outputs/deployment-validation'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$subArgs = if ($Subscription) { @('--subscription', $Subscription) } else { @() }

function Add-Row {
    param([string]$Check, [string]$Result, [string]$Details)
    $rows.Add(@{ Check = $Check; Result = $Result; Details = $Details })
    $color = switch ($Result) {
        'PASS' { 'Green' }
        'FAIL' { 'Red' }
        default { 'Yellow' }
    }
    Write-Host "  [$Result] $Check — $Details" -ForegroundColor $color
    switch ($Result) {
        'PASS' { $Script:passed++ }
        'FAIL' { $Script:failed++ }
        default { $Script:warnings++ }
    }
}

Write-Host "`n==> Security Verification: $ResourceGroup`n" -ForegroundColor Cyan

# ── Discover resources if not provided ───────────────────────────────────────
if (-not $StorageAccountName) {
    $StorageAccountName = az storage account list `
        --resource-group $ResourceGroup @subArgs `
        --query "[0].name" -o tsv 2>$null
    if ($StorageAccountName) { Write-Host "    [auto] Storage: $StorageAccountName" }
}

if (-not $KeyVaultName) {
    $KeyVaultName = az keyvault list `
        --resource-group $ResourceGroup @subArgs `
        --query "[0].name" -o tsv 2>$null
    if ($KeyVaultName) { Write-Host "    [auto] Key Vault: $KeyVaultName" }
}

if (-not $FunctionAppName) {
    $FunctionAppName = az functionapp list `
        --resource-group $ResourceGroup @subArgs `
        --query "[0].name" -o tsv 2>$null
    if ($FunctionAppName) { Write-Host "    [auto] Function App: $FunctionAppName" }
}

# ── Storage Account ───────────────────────────────────────────────────────────
if ($StorageAccountName) {
    Write-Host "`nStorage Account: $StorageAccountName"

    $stor = az storage account show `
        --name $StorageAccountName `
        --resource-group $ResourceGroup `
        @subArgs -o json 2>$null | ConvertFrom-Json

    $pna  = $stor.publicNetworkAccess
    if ($pna -eq 'Disabled') {
        Add-Row "Storage publicNetworkAccess" "PASS" "Disabled"
    } else {
        Add-Row "Storage publicNetworkAccess" "FAIL" "Value='$pna' — must be Disabled"
    }

    $bpa  = $stor.allowBlobPublicAccess
    if ($bpa -eq $false) {
        Add-Row "Storage allowBlobPublicAccess" "PASS" "false"
    } else {
        Add-Row "Storage allowBlobPublicAccess" "FAIL" "Value='$bpa' — must be false"
    }

    $rie  = $stor.encryption.requireInfrastructureEncryption
    if ($rie -eq $true) {
        Add-Row "Storage requireInfrastructureEncryption" "PASS" "true"
    } else {
        Add-Row "Storage requireInfrastructureEncryption" "WARN" "false — enable for regulated workloads"
    }

    $https = $stor.supportsHttpsTrafficOnly
    if ($https -eq $true) {
        Add-Row "Storage supportsHttpsTrafficOnly" "PASS" "true"
    } else {
        Add-Row "Storage supportsHttpsTrafficOnly" "FAIL" "false — HTTP traffic allowed"
    }
} else {
    Add-Row "Storage checks" "WARN" "No storage account found in $ResourceGroup — skipped"
}

# ── Key Vault ─────────────────────────────────────────────────────────────────
if ($KeyVaultName) {
    Write-Host "`nKey Vault: $KeyVaultName"

    $kv = az keyvault show `
        --name $KeyVaultName `
        --resource-group $ResourceGroup `
        @subArgs -o json 2>$null | ConvertFrom-Json

    $kvPna = $kv.properties.publicNetworkAccess
    if ($kvPna -eq 'Disabled') {
        Add-Row "Key Vault publicNetworkAccess" "PASS" "Disabled"
    } else {
        Add-Row "Key Vault publicNetworkAccess" "FAIL" "Value='$kvPna' — must be Disabled"
    }

    $sd = $kv.properties.enableSoftDelete
    if ($sd -eq $true) {
        Add-Row "Key Vault softDelete" "PASS" "enabled"
    } else {
        Add-Row "Key Vault softDelete" "FAIL" "disabled"
    }

    $pp = $kv.properties.enablePurgeProtection
    if ($pp -eq $true) {
        Add-Row "Key Vault purgeProtection" "PASS" "enabled"
    } else {
        Add-Row "Key Vault purgeProtection" "FAIL" "disabled"
    }

    $rbac = $kv.properties.enableRbacAuthorization
    if ($rbac -eq $true) {
        Add-Row "Key Vault enableRbacAuthorization" "PASS" "true"
    } else {
        Add-Row "Key Vault enableRbacAuthorization" "WARN" "false — using access policies instead of RBAC"
    }
} else {
    Add-Row "Key Vault checks" "WARN" "No key vault found in $ResourceGroup — skipped"
}

# ── Function App ──────────────────────────────────────────────────────────────
if ($FunctionAppName) {
    Write-Host "`nFunction App: $FunctionAppName"

    $fa = az functionapp show `
        --name $FunctionAppName `
        --resource-group $ResourceGroup `
        @subArgs -o json 2>$null | ConvertFrom-Json

    if ($fa.httpsOnly -eq $true) {
        Add-Row "Function App httpsOnly" "PASS" "true"
    } else {
        Add-Row "Function App httpsOnly" "FAIL" "false — HTTP allowed"
    }

    $tls = az functionapp config show `
        --name $FunctionAppName `
        --resource-group $ResourceGroup `
        @subArgs --query minTlsVersion -o tsv 2>$null

    if ($tls -in '1.2','1.3') {
        Add-Row "Function App minTlsVersion" "PASS" "$tls"
    } else {
        Add-Row "Function App minTlsVersion" "FAIL" "Value='$tls' — must be 1.2 or higher"
    }

    $vnetId = $fa.virtualNetworkSubnetId
    if ($vnetId) {
        Add-Row "Function App VNet integration" "PASS" "Integrated: $vnetId"
    } else {
        Add-Row "Function App VNet integration" "WARN" "Not VNet-integrated — outbound traffic is public"
    }
} else {
    Add-Row "Function App checks" "WARN" "No function app found in $ResourceGroup — skipped"
}

# ── NSG rules ─────────────────────────────────────────────────────────────────
Write-Host "`nNSG Rules"
$nsgs = az network nsg list `
    --resource-group $ResourceGroup @subArgs `
    -o json 2>$null | ConvertFrom-Json

if ($nsgs -and $nsgs.Count -gt 0) {
    foreach ($nsg in $nsgs) {
        $dangerous = $nsg.securityRules | Where-Object {
            $_.access -eq 'Allow' -and
            $_.direction -eq 'Inbound' -and
            ($_.destinationPortRange -eq '*' -or $_.sourceAddressPrefix -eq '*')
        }
        if ($dangerous) {
            Add-Row "NSG $($nsg.name)" "FAIL" "Has Allow-Any-Inbound rule(s)"
        } else {
            Add-Row "NSG $($nsg.name)" "PASS" "No overly-permissive inbound rules"
        }
    }
} else {
    Add-Row "NSG checks" "WARN" "No NSGs found in $ResourceGroup — skipped"
}

# ── Write report ──────────────────────────────────────────────────────────────
$status = if ($failed -gt 0) { 'FAILED' } else { 'PASSED' }
$tableRows = $rows | ForEach-Object { "| $($_.Check) | $($_.Result) | $($_.Details) |" }

$report = @"
# Security Verification Report
## Status: $status

**Date:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
**Resource Group:** $ResourceGroup

| Check | Result | Details |
|---|---|---|
$($tableRows -join "`n")

## Summary
- Passed:   $passed
- Failed:   $failed
- Warnings: $warnings

## References
- https://learn.microsoft.com/en-us/azure/security/fundamentals/best-practices-and-patterns
- https://learn.microsoft.com/en-us/azure/storage/common/storage-network-security
- https://learn.microsoft.com/en-us/azure/key-vault/general/security-features
"@

$reportFile = "$outDir/security-report.md"
$report | Out-File $reportFile -Encoding utf8
Write-Host "`nReport written to $reportFile"

if ($failed -gt 0) {
    Write-Host "`nRESULT: FAILED ($failed check(s) failed)" -ForegroundColor Red
    exit 1
}
Write-Host "`nRESULT: PASSED ($passed passed, $warnings warning(s))" -ForegroundColor Green
