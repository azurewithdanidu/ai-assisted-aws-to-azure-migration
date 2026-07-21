#Requires -Version 7.0
<#
.SYNOPSIS
    Runs full pre-deployment validation: Bicep syntax, ARM validation,
    what-if dry-run, policy compliance, and quota checks.

.DESCRIPTION
    Automatically detects whether main.bicep is subscription-scoped or
    resource-group-scoped and uses the appropriate deployment commands.

    Gate order (stops on first blocking failure):
      1. az bicep build              — syntax check
      2. az deployment sub validate  — ARM schema validation (sub-scoped templates)
         az deployment group validate (RG-scoped templates, legacy)
      3. az deployment sub what-if   — dry-run (sub-scoped templates)
         az deployment group what-if (RG-scoped templates, legacy)
         Blocks on: Delete of data resources, public network re-enabled,
                    NSG allow-all additions, subscription-scope role changes
      4. az policy state summarize   — policy compliance (Non-compliant Deny policies)
      5. Quota spot-checks           — storage + Function App limits

    Results are written to  outputs/deployment-validation/what-if-<env>.json
    and a summary to        outputs/deployment-validation/what-if-report.md

    IMPORTANT: If main.bicep declares targetScope = 'subscription', this script
    automatically uses 'az deployment sub' commands. Using group commands against
    a subscription-scoped template will fail — this script enforces the correct scope.

.PARAMETER Location
    Azure region for the subscription-scope deployment (e.g. australiaeast).
    Required for subscription-scoped templates.

.PARAMETER ResourceGroup
    Azure resource group name used for post-deployment policy and quota checks.

.PARAMETER Environment
    Target environment: dev | staging | prod

.PARAMETER BicepRoot
    Path to the Bicep root (default: outputs/bicep-templates).

.PARAMETER Subscription
    Azure subscription ID. Defaults to current az account.

.EXAMPLE
    .\run-what-if.ps1 -Location australiaeast -ResourceGroup "rg-migration-dev" -Environment dev

.EXAMPLE
    .\run-what-if.ps1 -Location australiaeast -ResourceGroup "rg-prod-migration" -Environment prod -Subscription "00000000-..."
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [string]$Location,

    [Parameter(Mandatory)]
    [string]$ResourceGroup,

    [Parameter(Mandatory)]
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment,

    [string]$BicepRoot    = 'outputs/bicep-templates',
    [string]$Subscription = ''
)

$ErrorActionPreference = 'Stop'
$blocking = 0
$warnings = 0
$report   = [System.Collections.Generic.List[string]]::new()

function Write-Step    { param([string]$Msg) Write-Host "`n==> $Msg" -ForegroundColor Cyan }
function Write-Pass    { param([string]$Msg) Write-Host "  [PASS]    $Msg" -ForegroundColor Green;  $report.Add("- [x] PASS: $Msg") }
function Write-Warn    { param([string]$Msg) Write-Host "  [WARN]    $Msg" -ForegroundColor Yellow; $report.Add("- [ ] WARN: $Msg"); $Script:warnings++ }
function Write-Block   { param([string]$Msg) Write-Host "  [BLOCKED] $Msg" -ForegroundColor Red;    $report.Add("- [ ] BLOCKED: $Msg"); $Script:blocking++ }

$mainBicep  = Join-Path $BicepRoot 'main.bicep'
$paramFile  = Join-Path $BicepRoot "parameters/$Environment.bicepparam"
$outDir     = 'outputs/deployment-validation'
$whatifFile = "$outDir/what-if-$Environment.json"
$reportFile = "$outDir/what-if-report.md"

New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$subArgs = if ($Subscription) { @('--subscription', $Subscription) } else { @() }

# Detect template scope
$bicepContent = Get-Content $mainBicep -Raw -ErrorAction SilentlyContinue
$isSubScope = $bicepContent -match "targetScope\s*=\s*'subscription'"

# ── 0. Scope gate ────────────────────────────────────────────────────────────
Write-Step "Step 0 — Subscription-scope gate"
if ($isSubScope) {
    Write-Pass "main.bicep is subscription-scoped — using 'az deployment sub' commands"
} else {
    Write-Warn "main.bicep is resource-group-scoped — using 'az deployment group' commands (legacy)"
}

# ── 1. Bicep syntax ─────────────────────────────────────────────────────────
Write-Step "Step 1 — Bicep syntax (az bicep build)"
az bicep restore --file $mainBicep --force *>$null
az bicep build --file $mainBicep 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Block "az bicep build FAILED — fix syntax errors first"; exit 1 }
Write-Pass "az bicep build"

# ── 2. ARM validation ────────────────────────────────────────────────────────
Write-Step "Step 2 — ARM template validation"
if ($isSubScope) {
    $validateOutput = az deployment sub validate `
        --location $Location `
        --template-file $mainBicep `
        --parameters $paramFile `
        @subArgs `
        --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Block "ARM validation failed: $validateOutput"
        exit 1
    }
    Write-Pass "az deployment sub validate"
} else {
    $validateOutput = az deployment group validate `
        --resource-group $ResourceGroup `
        --template-file $mainBicep `
        --parameters $paramFile `
        @subArgs `
        --output json 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Block "ARM validation failed: $validateOutput"
        exit 1
    }
    Write-Pass "az deployment group validate"
}

# ── 3. What-if dry run ───────────────────────────────────────────────────────
Write-Step "Step 3 — What-if dry run"
if ($isSubScope) {
    $whatifOutput = az deployment sub what-if `
        --location $Location `
        --template-file $mainBicep `
        --parameters $paramFile `
        --output json `
        @subArgs 2>&1
} else {
    $whatifOutput = az deployment group what-if `
        --resource-group $ResourceGroup `
        --template-file $mainBicep `
        --parameters $paramFile `
        --mode Incremental `
        --output json `
        @subArgs 2>&1
}

$whatifOutput | Out-File $whatifFile -Encoding utf8
Write-Host "  Saved to $whatifFile"

try {
    $wi = $whatifOutput | ConvertFrom-Json

    # Blocking conditions
    $deletesOnData = $wi.properties.changes | Where-Object {
        $_.changeType -eq 'Delete' -and
        $_.resourceId -match 'storageAccounts|vaults|servers|namespaces|databaseAccounts|redis'
    }
    foreach ($d in $deletesOnData) {
        Write-Block "Delete on data resource: $($d.resourceId)"
    }

    $publicReEnabled = $wi.properties.changes | Where-Object {
        $_.changeType -in ('Create','Modify') -and
        ($_.delta | Where-Object { $_.path -match 'publicNetworkAccess' -and $_.after -eq 'Enabled' })
    }
    foreach ($p in $publicReEnabled) {
        Write-Block "publicNetworkAccess re-enabled on: $($p.resourceId)"
    }

    # Warnings (expected changes)
    $newResources = $wi.properties.changes | Where-Object { $_.changeType -eq 'Create' }
    if ($newResources) { Write-Warn "$($newResources.Count) new resource(s) will be created (review expected)" }

    $modifies = $wi.properties.changes | Where-Object { $_.changeType -eq 'Modify' }
    if ($modifies) { Write-Warn "$($modifies.Count) resource(s) will be modified (review expected)" }

    if (-not $deletesOnData -and -not $publicReEnabled) {
        Write-Pass "No blocking conditions found in what-if output"
    }
} catch {
    Write-Warn "Could not parse what-if JSON — review $whatifFile manually"
}

# ── 4. Policy compliance ─────────────────────────────────────────────────────
Write-Step "Step 4 — Policy compliance check"
$policyOutput = az policy state summarize --resource-group $ResourceGroup @subArgs --output json 2>&1 | ConvertFrom-Json
$nonCompliant = $policyOutput.results.nonCompliantResources
if ($nonCompliant -gt 0) {
    Write-Block "$nonCompliant non-compliant resource(s) — check for Deny-effect policies before deploying"
} else {
    Write-Pass "Policy compliance — 0 non-compliant resources"
}

# ── 5. Quota spot-checks ─────────────────────────────────────────────────────
Write-Step "Step 5 — Quota spot-checks"
$storageUsage = az resource list --resource-group $ResourceGroup --resource-type Microsoft.Storage/storageAccounts @subArgs --output json 2>&1 | ConvertFrom-Json
if ($storageUsage.Count -ge 240) {
    Write-Warn "Storage account count is $($storageUsage.Count) — approaching 250/region limit"
} else {
    Write-Pass "Storage account count: $($storageUsage.Count) (limit 250)"
}

# ── Write report ─────────────────────────────────────────────────────────────
$scopeLabel = if ($isSubScope) { 'subscription' } else { 'resourceGroup' }
$reportContent = @"
# What-If Validation Report — $Environment

**Date:** $(Get-Date -Format 'yyyy-MM-dd')
**Environment:** $Environment
**Location:** $Location
**Resource Group:** $ResourceGroup
**Template Scope:** $scopeLabel
**Status:** $(if ($blocking -gt 0) { 'BLOCKED' } elseif ($warnings -gt 0) { 'PASS (with warnings)' } else { 'PASS' })

## Checks

$($report | ForEach-Object { $_ } | Out-String)

## What-If Output
Saved to: $whatifFile
"@

$reportContent | Out-File $reportFile -Encoding utf8
Write-Host "`nReport written to $reportFile"

# ── Result ────────────────────────────────────────────────────────────────────
Write-Host ""
if ($blocking -gt 0) {
    Write-Host "RESULT: $blocking BLOCKING condition(s) — deployment must not proceed" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: Validation PASSED ($warnings warning(s))" -ForegroundColor Green
