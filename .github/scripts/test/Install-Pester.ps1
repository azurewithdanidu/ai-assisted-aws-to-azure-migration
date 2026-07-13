# Install Pester 5 and PSScriptAnalyzer for CI use on ubuntu-latest
# Usage: pwsh -File Install-Pester.ps1
#
# Note: Install-PackageProvider NuGet is not needed on PowerShell 7+.
# Trusting PSGallery is sufficient.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Write-Host "Trusting PSGallery..."
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

Write-Host "Installing Pester 5..."
Install-Module -Name Pester -RequiredVersion 5.6.1 -Force -Scope CurrentUser -SkipPublisherCheck

Write-Host "Installing PSScriptAnalyzer..."
Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser -SkipPublisherCheck

Write-Host "Installed versions:"
Get-Module -ListAvailable Pester, PSScriptAnalyzer | Select-Object Name, Version | Format-Table -AutoSize
