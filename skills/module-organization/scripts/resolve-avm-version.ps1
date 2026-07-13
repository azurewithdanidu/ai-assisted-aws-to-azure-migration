#Requires -Version 7.0
<#
.SYNOPSIS
    Fetches the latest published version for an AVM Bicep module.

.DESCRIPTION
    Queries the official AVM CHANGELOG on GitHub for the specified module path
    and returns the most-recent version tag.  No authentication required.

.PARAMETER ModulePath
    The AVM module path below avm/res/  e.g. "storage/storage-account"

.EXAMPLE
    .\resolve-avm-version.ps1 -ModulePath "storage/storage-account"
    # Output: 0.32.0

.EXAMPLE
    .\resolve-avm-version.ps1 web/site
    # Output: 0.22.0
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory, Position = 0)]
    [ValidateNotNullOrEmpty()]
    [string]$ModulePath
)

$ErrorActionPreference = 'Stop'

$changelogUrl = "https://raw.githubusercontent.com/Azure/bicep-registry-modules/main/avm/res/$ModulePath/CHANGELOG.md"
Write-Verbose "Fetching $changelogUrl"

try {
    $content = Invoke-RestMethod -Uri $changelogUrl -UseBasicParsing
} catch {
    Write-Error "Could not fetch CHANGELOG for 'avm/res/$ModulePath'.`n  URL: $changelogUrl`n  Error: $_`n  Check the module path at: https://github.com/Azure/bicep-registry-modules/tree/main/avm/res"
    exit 1
}

# First ## X.Y.Z heading is the latest release
$versionLine = ($content -split "`n") | Where-Object { $_ -match '^## \d+\.\d+\.\d+' } | Select-Object -First 1

if (-not $versionLine) {
    Write-Error "No version heading found in CHANGELOG for '$ModulePath'."
    exit 1
}

$version = $versionLine -replace '^## ', '' -replace '\s.*', ''
Write-Output $version
