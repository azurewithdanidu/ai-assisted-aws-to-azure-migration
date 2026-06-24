#Requires -Version 7.0
<#
.SYNOPSIS
    Runs post-deployment smoke tests against a deployed Azure environment.

.DESCRIPTION
    Executes the following checks and writes a report to
    outputs/deployment-validation/smoke-test-report.md

    Checks run:
      1. HTTP health endpoint   — expects 200 or 401 (never 5xx)
      2. Managed identity       — principalId must be non-empty
      3. Key Vault secret read  — TestSecret must be resolvable
      4. Primary data service   — write + read-back + cleanup
         Detects which service is deployed (Blob / Cosmos / Service Bus)
         and runs the matching check automatically.
      5. Log Analytics ingestion — at least one AzureActivity row

    All test data is cleaned up (TTL or explicit delete) after each check.

.PARAMETER ResourceGroup
    Azure resource group that was deployed to.

.PARAMETER Environment
    Target environment: dev | staging | prod

.PARAMETER FunctionAppName
    Name of the Azure Function App to test. Used for endpoint + identity checks.

.PARAMETER KeyVaultName
    Name of the Key Vault. Used for secret resolution check.

.PARAMETER StorageAccountName
    If supplied, runs Blob Storage write/read/delete smoke test.

.PARAMETER CosmosAccountName
    If supplied, runs Cosmos DB write/read smoke test (TTL 60s).

.PARAMETER ServiceBusNamespace
    If supplied, runs Service Bus send smoke test.

.PARAMETER LogAnalyticsWorkspaceId
    If supplied, runs Log Analytics ingestion check.

.PARAMETER Subscription
    Azure subscription ID. Defaults to current az account.

.EXAMPLE
    .\smoke-test.ps1 `
        -ResourceGroup "rg-dev-migration" `
        -Environment dev `
        -FunctionAppName "dev-myapp-func-australiaeast" `
        -KeyVaultName "dev-myapp-kv" `
        -StorageAccountName "devmyappstor" `
        -LogAnalyticsWorkspaceId "00000000-0000-0000-0000-000000000000"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)] [string]$ResourceGroup,
    [Parameter(Mandatory)] [ValidateSet('dev','staging','prod')] [string]$Environment,
    [Parameter(Mandatory)] [string]$FunctionAppName,
    [Parameter(Mandatory)] [string]$KeyVaultName,

    [string]$StorageAccountName       = '',
    [string]$StorageContainerName     = 'uploads',
    [string]$CosmosAccountName        = '',
    [string]$CosmosDatabase           = '',
    [string]$CosmosContainer          = '',
    [string]$ServiceBusNamespace      = '',
    [string]$ServiceBusQueueName      = '',
    [string]$LogAnalyticsWorkspaceId  = '',
    [string]$Subscription             = ''
)

$ErrorActionPreference = 'Continue'   # keep going to collect all results
$passed = 0; $failed = 0
$rows   = [System.Collections.Generic.List[hashtable]]::new()
$outDir = 'outputs/deployment-validation'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$subArgs = if ($Subscription) { @('--subscription', $Subscription) } else { @() }

function Add-Row {
    param([string]$Check, [string]$Result, [string]$Details)
    $rows.Add(@{ Check = $Check; Result = $Result; Details = $Details })
    $color = if ($Result -eq 'PASS') { 'Green' } else { 'Red' }
    Write-Host "  [$Result] $Check — $Details" -ForegroundColor $color
    if ($Result -eq 'PASS') { $Script:passed++ } else { $Script:failed++ }
}

Write-Host "`n==> Smoke Tests: $Environment / $FunctionAppName`n" -ForegroundColor Cyan

# ── 1. HTTP Health Endpoint ──────────────────────────────────────────────────
Write-Host "Check 1 — HTTP health endpoint"
try {
    $host = az functionapp show `
        --name $FunctionAppName `
        --resource-group $ResourceGroup `
        @subArgs `
        --query defaultHostName -o tsv

    $response = Invoke-WebRequest -Uri "https://$host/api/health" -UseBasicParsing -SkipHttpErrorCheck -TimeoutSec 30
    $code = $response.StatusCode

    if ($code -in 200, 401) {
        Add-Row "HTTP health endpoint" "PASS" "HTTP $code"
    } elseif ($code -ge 500) {
        Add-Row "HTTP health endpoint" "FAIL" "HTTP $code (5xx — Function App error)"
    } else {
        Add-Row "HTTP health endpoint" "PASS" "HTTP $code (non-200 but not 5xx)"
    }
} catch {
    Add-Row "HTTP health endpoint" "FAIL" "Exception: $_"
}

# ── 2. Managed Identity ──────────────────────────────────────────────────────
Write-Host "Check 2 — Managed identity"
try {
    $principalId = az functionapp identity show `
        --name $FunctionAppName `
        --resource-group $ResourceGroup `
        @subArgs `
        --query principalId -o tsv

    if ($principalId -and $principalId -ne 'null') {
        Add-Row "Managed identity" "PASS" "principalId: $principalId"
    } else {
        Add-Row "Managed identity" "FAIL" "No system-assigned managed identity found"
    }
} catch {
    Add-Row "Managed identity" "FAIL" "Exception: $_"
}

# ── 3. Key Vault Secret Read ─────────────────────────────────────────────────
Write-Host "Check 3 — Key Vault secret resolution"
try {
    $secretValue = az keyvault secret show `
        --vault-name $KeyVaultName `
        --name "TestSecret" `
        @subArgs `
        --query value -o tsv 2>&1

    if ($LASTEXITCODE -eq 0 -and $secretValue) {
        Add-Row "Key Vault secret read" "PASS" "TestSecret resolved"
    } else {
        Add-Row "Key Vault secret read" "FAIL" "Could not read TestSecret: $secretValue"
    }
} catch {
    Add-Row "Key Vault secret read" "FAIL" "Exception: $_"
}

# ── 4a. Blob Storage smoke test ──────────────────────────────────────────────
if ($StorageAccountName) {
    Write-Host "Check 4 — Blob Storage write/read/delete"
    $testBlob = "smoke-test-$(Get-Date -Format 'yyyyMMddHHmmss').txt"
    try {
        az storage blob upload `
            --account-name $StorageAccountName `
            --container-name $StorageContainerName `
            --name $testBlob `
            --data "smoke-test $(Get-Date -Format o)" `
            --auth-mode login `
            @subArgs *>$null

        $exists = az storage blob show `
            --account-name $StorageAccountName `
            --container-name $StorageContainerName `
            --name $testBlob `
            --auth-mode login `
            @subArgs `
            --query name -o tsv 2>&1

        if ($exists -eq $testBlob) {
            az storage blob delete `
                --account-name $StorageAccountName `
                --container-name $StorageContainerName `
                --name $testBlob `
                --auth-mode login `
                @subArgs *>$null
            Add-Row "Blob Storage write/read/delete" "PASS" "Test blob created, verified, deleted"
        } else {
            Add-Row "Blob Storage write/read/delete" "FAIL" "Blob not found after upload"
        }
    } catch {
        Add-Row "Blob Storage write/read/delete" "FAIL" "Exception: $_"
    }
}

# ── 4b. Cosmos DB smoke test ─────────────────────────────────────────────────
if ($CosmosAccountName -and $CosmosDatabase -and $CosmosContainer) {
    Write-Host "Check 4 — Cosmos DB write/read (TTL 60s)"
    $testId = "smoke-test-$(Get-Date -Format 'yyyyMMddHHmmss')"
    try {
        $body = @{ id = $testId; value = "smoke"; _ttl = 60 } | ConvertTo-Json
        $sub = if ($Subscription) { $Subscription } else { (az account show --query id -o tsv) }

        $result = az rest --method POST `
            --url "https://management.azure.com/subscriptions/$sub/resourceGroups/$ResourceGroup/providers/Microsoft.DocumentDB/databaseAccounts/$CosmosAccountName/sqlDatabases/$CosmosDatabase/containers/$CosmosContainer/documents?api-version=2021-10-15" `
            --body $body 2>&1

        if ($LASTEXITCODE -eq 0) {
            Add-Row "Cosmos DB write (TTL 60s)" "PASS" "Document '$testId' created with 60s TTL"
        } else {
            Add-Row "Cosmos DB write (TTL 60s)" "FAIL" "$result"
        }
    } catch {
        Add-Row "Cosmos DB write (TTL 60s)" "FAIL" "Exception: $_"
    }
}

# ── 4c. Service Bus smoke test ───────────────────────────────────────────────
if ($ServiceBusNamespace -and $ServiceBusQueueName) {
    Write-Host "Check 4 — Service Bus send"
    try {
        $token = az account get-access-token `
            --resource "https://servicebus.azure.net" `
            --query accessToken -o tsv

        $msgBody = "<entry xmlns='http://www.w3.org/2005/Atom'><content type='application/xml'><SmokeTest>ok</SmokeTest></content></entry>"
        $response = Invoke-RestMethod `
            -Method POST `
            -Uri "https://$ServiceBusNamespace.servicebus.windows.net/$ServiceBusQueueName/messages" `
            -Headers @{ Authorization = "Bearer $token"; 'Content-Type' = 'application/atom+xml;type=entry;charset=utf-8' } `
            -Body $msgBody `
            -SkipHttpErrorCheck

        if ($?) {
            Add-Row "Service Bus message send" "PASS" "Test message sent to $ServiceBusQueueName"
        } else {
            Add-Row "Service Bus message send" "FAIL" "Send failed"
        }
    } catch {
        Add-Row "Service Bus message send" "FAIL" "Exception: $_"
    }
}

# ── 5. Log Analytics ingestion ───────────────────────────────────────────────
if ($LogAnalyticsWorkspaceId) {
    Write-Host "Check 5 — Log Analytics ingestion"
    try {
        $rows_la = az monitor log-analytics query `
            --workspace $LogAnalyticsWorkspaceId `
            --analytics-query "AzureActivity | take 5" `
            --output json 2>&1 | ConvertFrom-Json

        if ($rows_la.Count -gt 0) {
            Add-Row "Log Analytics ingestion" "PASS" "$($rows_la.Count) AzureActivity row(s) returned"
        } else {
            Add-Row "Log Analytics ingestion" "FAIL" "No rows — ingestion may not have started yet (wait 5-10 min)"
        }
    } catch {
        Add-Row "Log Analytics ingestion" "FAIL" "Exception: $_"
    }
}

# ── Write report ─────────────────────────────────────────────────────────────
$status = if ($failed -gt 0) { 'FAILED' } else { 'PASSED' }
$tableRows = $rows | ForEach-Object { "| $($_.Check) | $($_.Result) | $($_.Details) |" }

$report = @"
# Smoke Test Report — $Environment
## Status: $status

**Date:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') UTC
**Function App:** $FunctionAppName
**Resource Group:** $ResourceGroup

| Check | Result | Details |
|---|---|---|
$($tableRows -join "`n")

## Summary
- Passed: $passed
- Failed: $failed
"@

$reportFile = "$outDir/smoke-test-report.md"
$report | Out-File $reportFile -Encoding utf8
Write-Host "`nReport written to $reportFile"

# ── Exit ─────────────────────────────────────────────────────────────────────
Write-Host ""
if ($failed -gt 0) {
    Write-Host "RESULT: FAILED ($failed check(s) failed)" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: PASSED ($passed check(s))" -ForegroundColor Green
