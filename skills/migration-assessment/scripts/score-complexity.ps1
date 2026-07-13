#Requires -Version 7.0
<#
.SYNOPSIS
    Prints a quick migration complexity summary from aws-inventory.json.

.DESCRIPTION
    Reads aws-inventory.json and, when available, parses the Service Complexity
    Matrix from migration-assessment.md. If the assessment file is missing, the
    script applies default complexity rules based on AWS service types.

.PARAMETER InventoryPath
    Path to the inventory JSON file.
    Defaults to outputs/aws-migration-artifacts/aws-inventory.json.

.EXAMPLE
    .\score-complexity.ps1

.EXAMPLE
    .\score-complexity.ps1 -InventoryPath "outputs/aws-migration-artifacts/aws-inventory.json"
#>

[CmdletBinding()]
param(
    [string]$InventoryPath = 'outputs/aws-migration-artifacts/aws-inventory.json',
    [switch]$Help
)

$ErrorActionPreference = 'Stop'

function Show-Usage {
    @"
Usage: ./score-complexity.ps1 [-InventoryPath <path>]

Read aws-inventory.json and print a quick migration complexity summary.
If migration-assessment.md exists beside the inventory file, the script parses the
Service Complexity Matrix. Otherwise it applies default complexity rules.
"@ | Write-Host
}

function Get-TierRank {
    param([string]$Tier)

    switch ((ConvertTo-NormalizedTier $Tier)) {
        'Low'      { return 1 }
        'Medium'   { return 2 }
        'High'     { return 3 }
        'Critical' { return 4 }
        default    { return 0 }
    }
}

function ConvertTo-NormalizedTier {
    param([string]$Tier)

    switch (($Tier ?? '').ToLowerInvariant()) {
        'low'      { return 'Low' }
        'medium'   { return 'Medium' }
        'high'     { return 'High' }
        'critical' { return 'Critical' }
        default    { return $Tier }
    }
}

function Get-MaxTier {
    param(
        [string]$Current,
        [string]$Candidate
    )

    if ((Get-TierRank $Candidate) -gt (Get-TierRank $Current)) {
        return $Candidate
    }

    return $Current
}

function Get-NormalizedServiceKey {
    param([string]$Value)

    return (($Value ?? '') -replace '[^a-zA-Z0-9]', '').ToLowerInvariant()
}

function Get-ServiceDisplayName {
    param(
        [string]$ServiceKey,
        [string]$ServiceType
    )

    switch (Get-NormalizedServiceKey $ServiceKey) {
        'lambda'      { return 'Lambda' }
        's3'          { return 'S3' }
        'rds'         { return 'RDS' }
        'dynamodb'    { return 'DynamoDB' }
        'cognito'     { return 'Cognito' }
        'ecs'         { return 'ECS' }
        'eks'         { return 'EKS' }
        'elasticache' { return 'ElastiCache' }
        'sqs'         { return 'SQS' }
        'sns'         { return 'SNS' }
        'eventbridge' { return 'EventBridge' }
        'apigateway'  { return 'API Gateway' }
        'cloudfront'  { return 'CloudFront' }
        'route53'     { return 'Route53' }
        'vpc'         { return 'VPC' }
        'iam'         { return 'IAM' }
        default {
            if (-not [string]::IsNullOrWhiteSpace($ServiceType) -and $ServiceType -ne $ServiceKey) {
                return $ServiceType
            }
            return $ServiceKey
        }
    }
}

function Get-DefaultTierForService {
    param(
        [string]$ServiceKey,
        [string]$ServiceType
    )

    foreach ($candidate in @($ServiceKey, $ServiceType)) {
        switch (Get-NormalizedServiceKey $candidate) {
            'lambda' {
                return 'Low'
            }
            'awslambda' {
                return 'Low'
            }
            'lambdafunction' {
                return 'Low'
            }
            's3' {
                return 'Low'
            }
            'amazons3' {
                return 'Low'
            }
            'rds' {
                return 'Medium'
            }
            'amazonrds' {
                return 'Medium'
            }
            'dynamodb' {
                return 'Medium'
            }
            'amazondynamodb' {
                return 'Medium'
            }
            'cognito' {
                return 'High'
            }
            'amazoncognito' {
                return 'High'
            }
            'ecs' {
                return 'High'
            }
            'amazonecs' {
                return 'High'
            }
            'eks' {
                return 'Critical'
            }
            'amazoneks' {
                return 'Critical'
            }
            'elasticache' {
                return 'Medium'
            }
            'amazonelasticache' {
                return 'Medium'
            }
            'sqs' {
                return 'Low'
            }
            'amazonsqs' {
                return 'Low'
            }
            'sns' {
                return 'Low'
            }
            'amazonsns' {
                return 'Low'
            }
            'eventbridge' {
                return 'Medium'
            }
            'amazoneventbridge' {
                return 'Medium'
            }
            'cloudwatchevents' {
                return 'Medium'
            }
            'apigateway' {
                return 'Medium'
            }
            'amazonapigateway' {
                return 'Medium'
            }
            'restapi' {
                return 'Medium'
            }
            'httpapi' {
                return 'Medium'
            }
            'websocketapi' {
                return 'Medium'
            }
            'cloudfront' {
                return 'Low'
            }
            'amazoncloudfront' {
                return 'Low'
            }
            'route53' {
                return 'Low'
            }
            'amazonroute53' {
                return 'Low'
            }
            'vpc' {
                return 'Medium'
            }
            'amazonvpc' {
                return 'Medium'
            }
            'iam' {
                return 'High'
            }
            'awsiam' {
                return 'High'
            }
        }
    }

    return 'Medium'
}

function Get-EffortForTier {
    param([string]$Tier)

    switch ($Tier) {
        'Low'      { return 2.0 }
        'Medium'   { return 5.0 }
        'High'     { return 10.0 }
        'Critical' { return 15.0 }
        default    { return 5.0 }
    }
}

function Get-EffortFromCell {
    param([string]$Cell)

    $cellMatches = [regex]::Matches((($Cell ?? '') -replace '[–—]', '-'), '[0-9]+(\.[0-9]+)?')
    if ($cellMatches.Count -eq 0) {
        return 0.0
    }

    if ($cellMatches.Count -eq 1) {
        return [double]$cellMatches[0].Value
    }

    return (([double]$cellMatches[0].Value) + ([double]$cellMatches[1].Value)) / 2
}

function Format-Number {
    param([double]$Value)

    if ($Value -eq [math]::Truncate($Value)) {
        return [string][int]$Value
    }

    return ('{0:N1}' -f $Value)
}

function Add-ServiceSummary {
    param(
        [hashtable]$Rows,
        [string]$Service,
        [int]$Count,
        [string]$Complexity,
        [double]$Effort
    )

    $Complexity = ConvertTo-NormalizedTier $Complexity

    if ($Rows.ContainsKey($Service)) {
        $Rows[$Service].Count += $Count
        $Rows[$Service].Complexity = Get-MaxTier $Rows[$Service].Complexity $Complexity
        $Rows[$Service].Effort += $Effort
        return
    }

    $Rows[$Service] = [pscustomobject]@{
        Service    = $Service
        Count      = $Count
        Complexity = $Complexity
        Effort     = $Effort
    }
}

function Invoke-ComplexitySummary {
    param(
        [string]$Path
    )

    Write-Host "==> Reading AWS inventory: $Path" -ForegroundColor Cyan
    if (-not (Test-Path $Path -PathType Leaf)) {
        throw "Inventory file not found: $Path"
    }

    $inventory = (Get-Content $Path -Raw) | ConvertFrom-Json
    $serviceEntries = @($inventory.services.PSObject.Properties)
    if ($serviceEntries.Count -eq 0) {
        throw 'Inventory file must contain a non-empty services object.'
    }

    $assessmentPath = Join-Path (Split-Path $Path -Parent) 'migration-assessment.md'
    $rows = @{}
    $parsedRows = 0

    if ((Test-Path $assessmentPath -PathType Leaf) -and ((Get-Item $assessmentPath).Length -gt 0)) {
        $assessmentLines = Get-Content $assessmentPath
        if ($assessmentLines -match '^## Service Complexity Matrix') {
            Write-Host "==> Parsing Service Complexity Matrix: $assessmentPath" -ForegroundColor Cyan
            $inMatrix = $false
            foreach ($line in $assessmentLines) {
                if ($line -match '^## Service Complexity Matrix') {
                    $inMatrix = $true
                    continue
                }

                if ($inMatrix -and $line -match '^##\s+') {
                    break
                }

                if (-not $inMatrix -or -not $line.StartsWith('|')) {
                    continue
                }

                if ($line -match '^\|\s*Service\s*\|' -or $line -match '^\|\s*-') {
                    continue
                }

                $parts = $line.Split('|')
                if ($parts.Count -lt 6) {
                    continue
                }

                $service = $parts[1].Trim()
                $countText = $parts[3].Trim()
                $complexity = $parts[4].Trim()
                $effortText = $parts[5].Trim()

                $countValue = 0
                if ([string]::IsNullOrWhiteSpace($service) -or -not [int]::TryParse($countText, [ref]$countValue) -or [string]::IsNullOrWhiteSpace($complexity)) {
                    continue
                }

                Add-ServiceSummary -Rows $rows -Service $service -Count $countValue -Complexity $complexity -Effort (Get-EffortFromCell $effortText)
                $parsedRows++
            }
        }
    }

    if ($parsedRows -eq 0) {
        Write-Host '==> No usable Service Complexity Matrix found; applying default complexity rules' -ForegroundColor Yellow
        foreach ($serviceEntry in $serviceEntries) {
            $serviceKey = $serviceEntry.Name
            $service = $serviceEntry.Value
            $countValue = 0

            if ($service.PSObject.Properties.Name -contains 'count' -and [int]::TryParse([string]$service.count, [ref]$countValue)) {
                $null = $countValue
            } else {
                $countValue = @($service.resources).Count
            }

            $serviceType = if ($service.PSObject.Properties.Name -contains 'service_type') { [string]$service.service_type } else { $serviceKey }
            $complexity = Get-DefaultTierForService -ServiceKey $serviceKey -ServiceType $serviceType
            $serviceName = Get-ServiceDisplayName -ServiceKey $serviceKey -ServiceType $serviceType
            $effort = (Get-EffortForTier $complexity) * $countValue

            Add-ServiceSummary -Rows $rows -Service $serviceName -Count $countValue -Complexity $complexity -Effort $effort
            $parsedRows++
        }
    }

    if ($parsedRows -eq 0) {
        throw 'No service entries were found to score.'
    }

    $sortedRows = $rows.Values | Sort-Object Service
    $tierCounts = @{ Low = 0; Medium = 0; High = 0; Critical = 0 }
    $totalEffort = 0.0
    $overallRisk = 'Low'

    Write-Host ''
    Write-Host '| Service | Count | Complexity | Estimated Effort (days) |'
    Write-Host '|---|---:|---|---:|'
    foreach ($row in $sortedRows) {
        Write-Host "| $($row.Service) | $($row.Count) | $($row.Complexity) | $(Format-Number $row.Effort) |"
        $tierCounts[$row.Complexity]++
        $totalEffort += $row.Effort
        $overallRisk = Get-MaxTier $overallRisk $row.Complexity
    }

    Write-Host ''
    Write-Host "Complexity tiers: Low=$($tierCounts.Low), Medium=$($tierCounts.Medium), High=$($tierCounts.High), Critical=$($tierCounts.Critical)"
    Write-Host "Total services: $($sortedRows.Count)"
    Write-Host "Total effort estimate: $(Format-Number $totalEffort) days"
    Write-Host "Overall risk level: $overallRisk"
}

if ($Help) {
    Show-Usage
    exit 0
}

try {
    Invoke-ComplexitySummary -Path $InventoryPath
} catch {
    Write-Host "❌ $($_.Exception.Message)" -ForegroundColor Yellow
}

exit 0
