# Pester test runner for CI
# Usage: pwsh -File Run-PesterTests.ps1 [-OutputFormat Detailed] [-CIOutputPath results/pester.xml]

param(
    [string]$OutputFormat = 'Detailed',
    [string]$CIOutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module Pester -MinimumVersion 5.0

$config = New-PesterConfiguration
$config.Run.Path      = "$PSScriptRoot"
$config.Run.PassThru  = $true          # required so Invoke-Pester returns a result object
$config.Output.Verbosity = $OutputFormat
$config.TestResult.Enabled = $true

if ($CIOutputPath) {
    $config.TestResult.OutputPath = $CIOutputPath
    $config.TestResult.OutputFormat = 'JUnitXml'
    New-Item -ItemType Directory -Force -Path (Split-Path $CIOutputPath) | Out-Null
}

$result = Invoke-Pester -Configuration $config

if ($result.FailedCount -gt 0) {
    Write-Error "❌ $($result.FailedCount) Pester test(s) failed"
    exit 1
}

Write-Host "✅ All $($result.PassedCount) Pester test(s) passed"
