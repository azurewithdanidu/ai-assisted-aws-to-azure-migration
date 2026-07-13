#Requires -Version 7.0
<#
.SYNOPSIS
    Creates an Azure App Registration with Workload Identity Federation
    for GitHub Actions OIDC deployments.  No service principal secrets stored.

.DESCRIPTION
    Steps performed:
      1. Create App Registration
      2. Create Service Principal
      3. Assign Contributor on the target resource group
      4. Assign User Access Administrator on the target resource group
         (required when Bicep creates RBAC role assignments)
      5. Create federated credential for the specified GitHub Environment

    Outputs the GitHub Secrets values to copy into your repository settings.
    Writes a setup summary to outputs/pipeline/setup-oidc.md.

.PARAMETER GitHubOrg
    GitHub organisation or username (e.g. "azurewithdanidu").

.PARAMETER GitHubRepo
    GitHub repository name (e.g. "ai-assisted-aws-to-azure-migration").

.PARAMETER Environment
    GitHub Environment name: dev | staging | prod

.PARAMETER Subscription
    Azure subscription ID to deploy into.

.PARAMETER ResourceGroup
    Azure resource group name for this environment.

.PARAMETER AdditionalSubjectFilter
    Optional extra federated credential subject (e.g. for branch push triggers).
    Default: environment subject only.

.EXAMPLE
    .\setup-oidc.ps1 `
        -GitHubOrg "azurewithdanidu" `
        -GitHubRepo "ai-assisted-aws-to-azure-migration" `
        -Environment "prod" `
        -Subscription "00000000-0000-0000-0000-000000000000" `
        -ResourceGroup "rg-prod-migration"
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)] [string]$GitHubOrg,
    [Parameter(Mandatory)] [string]$GitHubRepo,
    [Parameter(Mandatory)] [ValidateSet('dev','staging','prod')] [string]$Environment,
    [Parameter(Mandatory)] [string]$Subscription,
    [Parameter(Mandatory)] [string]$ResourceGroup,
    [string]$AdditionalSubjectFilter = ''
)

$ErrorActionPreference = 'Stop'

$appName = "gh-$GitHubRepo-$Environment"
$scope   = "/subscriptions/$Subscription/resourceGroups/$ResourceGroup"

Write-Host "`n==> Creating app registration: $appName" -ForegroundColor Cyan
$appId = az ad app create --display-name $appName --query appId -o tsv
Write-Host "    App ID (client ID): $appId"

Write-Host "`n==> Creating service principal"
$spId = az ad sp create --id $appId --query id -o tsv
Write-Host "    SP Object ID: $spId"

Write-Host "`n==> Assigning Contributor on $ResourceGroup"
az role assignment create `
    --assignee $spId `
    --role "Contributor" `
    --scope $scope | Out-Null
Write-Host "    Done"

Write-Host "`n==> Assigning User Access Administrator on $ResourceGroup"
Write-Host "    (required for Bicep to assign RBAC roles to managed identities)"
az role assignment create `
    --assignee $spId `
    --role "User Access Administrator" `
    --scope $scope | Out-Null
Write-Host "    Done"

# ── Federated credential — GitHub Environment ─────────────────────────────
Write-Host "`n==> Creating federated credential: environment=$Environment"
$credBody = @{
    name      = "gh-actions-$Environment"
    issuer    = "https://token.actions.githubusercontent.com"
    subject   = "repo:$GitHubOrg/${GitHubRepo}:environment:$Environment"
    audiences = @("api://AzureADTokenExchange")
} | ConvertTo-Json

$credBody | az ad app federated-credential create --id $appId --parameters - | Out-Null
Write-Host "    Created: repo:$GitHubOrg/${GitHubRepo}:environment:$Environment"

# ── Optional: branch push federated credential ────────────────────────────
if ($AdditionalSubjectFilter) {
    Write-Host "`n==> Creating additional federated credential: $AdditionalSubjectFilter"
    $cred2Body = @{
        name      = "gh-actions-$Environment-branch"
        issuer    = "https://token.actions.githubusercontent.com"
        subject   = $AdditionalSubjectFilter
        audiences = @("api://AzureADTokenExchange")
    } | ConvertTo-Json

    $cred2Body | az ad app federated-credential create --id $appId --parameters - | Out-Null
    Write-Host "    Created: $AdditionalSubjectFilter"
}

$tenantId = az account show --query tenantId -o tsv

# ── Output ────────────────────────────────────────────────────────────────────
$summary = @"
# OIDC Setup — $Environment

**Date:** $(Get-Date -Format 'yyyy-MM-dd')

## GitHub Repository Secrets (repo-level)

| Secret | Value |
|---|---|
| ``AZURE_CLIENT_ID`` | ``$appId`` |
| ``AZURE_TENANT_ID`` | ``$tenantId`` |
| ``AZURE_SUBSCRIPTION_ID`` | ``$Subscription`` |

## GitHub Environment Variables ($Environment)

| Variable | Value |
|---|---|
| ``RESOURCE_GROUP_NAME`` | ``$ResourceGroup`` |

## Federated Credential Subjects

- ``repo:$GitHubOrg/${GitHubRepo}:environment:$Environment``
$(if ($AdditionalSubjectFilter) { "- ``$AdditionalSubjectFilter``" })

## RBAC Assignments

| Role | Scope |
|---|---|
| Contributor | $scope |
| User Access Administrator | $scope |

## Next Steps

1. Copy the secrets above into GitHub → Settings → Secrets and Variables → Actions.
2. Set the environment variable ``RESOURCE_GROUP_NAME`` under the ``$Environment`` environment.
3. Enable environment protection rules in GitHub → Settings → Environments.
   - dev: None
   - staging: 1 required reviewer
   - prod: 2 required reviewers + 10-minute wait timer

## Reference

- https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure-openid-connect
- https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-azure
"@

New-Item -ItemType Directory -Force -Path 'outputs/pipeline' | Out-Null
$summary | Out-File 'outputs/pipeline/setup-oidc.md' -Encoding utf8

Write-Host "`n==> Summary written to outputs/pipeline/setup-oidc.md"
Write-Host ""
Write-Host "==> GitHub Secrets to add:" -ForegroundColor Yellow
Write-Host "    AZURE_CLIENT_ID       = $appId"
Write-Host "    AZURE_TENANT_ID       = $tenantId"
Write-Host "    AZURE_SUBSCRIPTION_ID = $Subscription"
Write-Host ""
Write-Host "==> GitHub Environment variable ($Environment):" -ForegroundColor Yellow
Write-Host "    RESOURCE_GROUP_NAME   = $ResourceGroup"
Write-Host ""
Write-Host "DONE" -ForegroundColor Green
