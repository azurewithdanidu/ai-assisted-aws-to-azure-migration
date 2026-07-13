# Install Pester 5 and PSScriptAnalyzer for CI use on ubuntu-latest
# Usage: pwsh -File Install-Pester.ps1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "Installing NuGet provider..."
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser | Out-Null

Write-Host "Installing Pester 5..."
Install-Module -Name Pester -RequiredVersion 5.6.1 -Force -Scope CurrentUser -SkipPublisherCheck

Write-Host "Installing PSScriptAnalyzer..."
Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser

Write-Host "Installed versions:"
Get-Module -ListAvailable Pester, PSScriptAnalyzer | Select-Object Name, Version | Format-Table -AutoSize
