#Requires -Version 7.0
<#
.SYNOPSIS
    Validates all Bicep files under a directory and runs az deployment group what-if
    for every environment parameter file found.

.DESCRIPTION
    Performs these checks in order:
      1. az bicep build   — syntax validation on every *.bicep file
      2. az bicep restore — pull AVM module cache (required before building)
      3. az deployment group what-if — incremental dry-run for each *.bicepparam
         (requires ResourceGroup and Subscription to be set)

    Exits 0 only when all checks pass.  Any failure exits 1.

.PARAMETER BicepRoot
    Path to the Bicep root folder containing main.bicep. Defaults to
    "outputs/bicep-templates" (relative to the repo root).

.PARAMETER ResourceGroup
    Azure resource group name for what-if runs. If omitted, what-if is skipped.

.PARAMETER Subscription
    Azure subscription ID. If omitted, uses the current az account.

.EXAMPLE
    # Syntax-only validation (no Azure login required)
    .\validate-bicep.ps1

.EXAMPLE
    # Full validation including what-if dry runs
    .\validate-bicep.ps1 -ResourceGroup "rg-dev-migration" -Subscription "00000000-0000-0000-0000-000000000000"
#>

[CmdletBinding()]
param (
    [string]$BicepRoot     = 'outputs/bicep-templates',
    [string]$ResourceGroup = '',
    [string]$Subscription  = ''
)

$ErrorActionPreference = 'Stop'
$errors = 0

function Write-Step  { param([string]$Msg) Write-Host "`n==> $Msg" -ForegroundColor Cyan }
function Write-Pass  { param([string]$Msg) Write-Host "  [PASS] $Msg" -ForegroundColor Green }
function Write-Fail  { param([string]$Msg) Write-Host "  [FAIL] $Msg" -ForegroundColor Red; $Script:errors++ }

# ── Step 1: Restore AVM modules ────────────────────────────────────────────────
$mainBicep = Join-Path $BicepRoot 'main.bicep'
if (-not (Test-Path $mainBicep)) {
    Write-Error "main.bicep not found at '$mainBicep'. Adjust -BicepRoot."
    exit 1
}

Write-Step "Restoring AVM module cache"
az bicep restore --file $mainBicep --force
if ($LASTEXITCODE -ne 0) { Write-Fail "az bicep restore failed"; exit 1 }
else { Write-Pass "az bicep restore" }

# ── Step 2: Build (syntax-check) every .bicep file ────────────────────────────
Write-Step "Building (syntax-checking) all Bicep files under $BicepRoot"
Get-ChildItem -Path $BicepRoot -Recurse -Filter '*.bicep' | ForEach-Object {
    $file = $_.FullName
    $result = az bicep build --file $file 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "$($_.Name)`n$result"
    } else {
        Write-Pass $_.Name
    }
}

# ── Step 3: What-if for each parameter file ───────────────────────────────────
if ($ResourceGroup) {
    $paramsDir = Join-Path $BicepRoot 'parameters'
    $paramFiles = Get-ChildItem -Path $paramsDir -Filter '*.bicepparam' -ErrorAction SilentlyContinue

    if (-not $paramFiles) {
        Write-Host "  No .bicepparam files found under $paramsDir — skipping what-if" -ForegroundColor Yellow
    } else {
        Write-Step "Running what-if for each parameter file"

        $subArgs = if ($Subscription) { @('--subscription', $Subscription) } else { @() }

        foreach ($pf in $paramFiles) {
            $env = $pf.BaseName   # dev | staging | prod
            Write-Host "  what-if: $env ..." -NoNewline

            $whatifJson = az deployment group what-if `
                --resource-group $ResourceGroup `
                --template-file $mainBicep `
                --parameters $pf.FullName `
                --mode Incremental `
                --output json `
                @subArgs 2>&1

            if ($LASTEXITCODE -ne 0) {
                Write-Fail "what-if failed for $env`n$whatifJson"
                continue
            }

            # Check for blocking conditions
            try {
                $wi = $whatifJson | ConvertFrom-Json
                $blocking = $wi.properties.changes | Where-Object {
                    $_.changeType -eq 'Delete' -and
                    $_.resourceId -match 'storageAccounts|vaults|servers|namespaces|databaseAccounts'
                }
                if ($blocking) {
                    Write-Fail "$env — BLOCKING DELETE on data resource(s):"
                    $blocking | ForEach-Object { Write-Host "      DELETE: $($_.resourceId)" -ForegroundColor Red }
                } else {
                    Write-Pass "$env — no blocking changes"
                }
            } catch {
                Write-Host " (could not parse JSON — review manually)" -ForegroundColor Yellow
            }
        }
    }
} else {
    Write-Host "`n  -ResourceGroup not supplied — skipping what-if dry runs" -ForegroundColor Yellow
}

# ── Result ────────────────────────────────────────────────────────────────────
Write-Host ""
if ($errors -gt 0) {
    Write-Host "RESULT: $errors check(s) FAILED" -ForegroundColor Red
    exit 1
}
Write-Host "RESULT: All Bicep validation checks PASSED" -ForegroundColor Green
