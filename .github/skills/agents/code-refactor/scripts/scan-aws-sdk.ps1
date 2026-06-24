#Requires -Version 7.0
<#
.SYNOPSIS
    Scans output application code for residual AWS SDK imports.

.DESCRIPTION
    Greps the specified directory for patterns matching common AWS SDK packages
    and identifiers across Python, JavaScript/TypeScript, Java, Go and C#.

    Detected patterns:
      Python  — boto3, botocore
      JS/TS   — @aws-sdk, aws-sdk
      Java    — software.amazon.awssdk
      Go      — github.com/aws/aws-sdk-go
      Generic — AmazonS3Client, AmazonDynamoDB, KinesisClient, SQSClient,
                SNSClient, LambdaClient, SecretsManagerClient

    Exits 0 when no residue found.  Exits 1 when residue is found so that
    CI/CD pipeline gates can block deployment.

.PARAMETER ScanPath
    Root directory to scan. Defaults to 'outputs/azure-functions'.

.PARAMETER FileExtensions
    Array of file extensions to include.
    Defaults to: .py .js .ts .java .go .cs

.EXAMPLE
    .\scan-aws-sdk.ps1

.EXAMPLE
    .\scan-aws-sdk.ps1 -ScanPath "outputs/azure-functions"

.EXAMPLE
    # In a GitHub Actions step:
    #   - run: pwsh .github/skills/agents/code-refactor/scripts/scan-aws-sdk.ps1
#>

[CmdletBinding()]
param (
    [string]   $ScanPath       = 'outputs/azure-functions',
    [string[]] $FileExtensions = @('.py', '.js', '.ts', '.java', '.go', '.cs')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ScanPath)) {
    Write-Error "Path not found: $ScanPath"
    exit 2
}

$patterns = @(
    'boto3',
    'botocore',
    '@aws-sdk',
    'aws-sdk',
    'software\.amazon\.awssdk',
    'github\.com/aws/aws-sdk-go',
    'AmazonS3Client',
    'AmazonDynamoDB',
    'KinesisClient',
    'SQSClient',
    'SNSClient',
    'LambdaClient',
    'SecretsManagerClient'
)

$combinedPattern = $patterns -join '|'

Write-Host "==> Scanning '$ScanPath' for AWS SDK references..." -ForegroundColor Cyan
Write-Host "    Pattern: $combinedPattern"
Write-Host ""

$files = Get-ChildItem -Recurse -File -Path $ScanPath |
         Where-Object { $FileExtensions -contains $_.Extension }

$hits = [System.Collections.Generic.List[pscustomobject]]::new()

foreach ($file in $files) {
    $lineNum = 0
    foreach ($line in Get-Content $file.FullName -ErrorAction SilentlyContinue) {
        $lineNum++
        if ($line -match $combinedPattern) {
            $hits.Add([pscustomobject]@{
                File    = $file.FullName
                Line    = $lineNum
                Content = $line.Trim()
            })
        }
    }
}

if ($hits.Count -eq 0) {
    Write-Host "No AWS SDK residue found. Safe to deploy." -ForegroundColor Green
    exit 0
}

Write-Host "FOUND $($hits.Count) AWS SDK reference(s) — fix before deploying:" -ForegroundColor Red
Write-Host "--------------------------------------------------------------------"
foreach ($hit in $hits) {
    Write-Host "$($hit.File):$($hit.Line)  $($hit.Content)" -ForegroundColor Yellow
}
Write-Host "--------------------------------------------------------------------"
exit 1
