#Requires -Version 7.0
<#
.SYNOPSIS
    Assigns an Azure built-in RBAC role to a managed identity or principal.

.DESCRIPTION
    Thin wrapper around 'az role assignment create' that pre-populates the
    correct built-in role GUIDs for the most common migration-factory roles.
    Accepts either a friendly role name (from the ValidateSet) or any GUID.

.PARAMETER PrincipalId
    Object ID of the managed identity or service principal.

.PARAMETER Scope
    Full resource ID or management-group path to assign the role at.
    Example: "/subscriptions/.../resourceGroups/rg-prod-migration"
             "/subscriptions/.../resourceGroups/rg-prod-migration/providers/Microsoft.Storage/storageAccounts/myacct"

.PARAMETER Role
    Built-in role name or GUID.
    Pre-defined shortcuts:
      StorageBlobDataContributor   — ba92f5b4-2d11-453d-a403-e96b0029c9fe
      StorageBlobDataReader        — 2a2b9908-6ea1-4ae2-8e65-a410df84e7d1
      KeyVaultSecretsUser          — 4633458b-17de-408a-b874-0445c86b69e6
      KeyVaultSecretsOfficer       — b86a8fe4-44ce-4948-aee5-eccb2c155cd7
      ServiceBusDataSender         — 69a216fc-b8fb-44d8-bc22-1f3c2cd27a39
      ServiceBusDataReceiver       — 4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0
      CosmosDBDataContributor      — 00000000-0000-0000-0000-000000000002
      Contributor                  — b24988ac-6180-42a0-ab88-20f7382dd24c
      Reader                       — acdd72a7-3385-48ef-bd42-f606fba81ae7

.PARAMETER Subscription
    Azure subscription ID. Defaults to current az account.

.EXAMPLE
    .\assign-rbac.ps1 `
        -PrincipalId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
        -Scope "/subscriptions/sub-id/resourceGroups/rg-dev-migration" `
        -Role "StorageBlobDataContributor"

.EXAMPLE
    # Custom GUID:
    .\assign-rbac.ps1 `
        -PrincipalId "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" `
        -Scope "/subscriptions/sub-id/resourceGroups/rg-dev-migration/providers/Microsoft.Storage/storageAccounts/myacct" `
        -Role "ba92f5b4-2d11-453d-a403-e96b0029c9fe"
#>

[CmdletBinding(SupportsShouldProcess)]
param (
    [Parameter(Mandatory)] [string]$PrincipalId,
    [Parameter(Mandatory)] [string]$Scope,
    [Parameter(Mandatory)] [string]$Role,
    [string]$Subscription = ''
)

$ErrorActionPreference = 'Stop'

# Map friendly names → built-in role GUIDs
$roleMap = @{
    'StorageBlobDataContributor' = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
    'StorageBlobDataReader'      = '2a2b9908-6ea1-4ae2-8e65-a410df84e7d1'
    'KeyVaultSecretsUser'        = '4633458b-17de-408a-b874-0445c86b69e6'
    'KeyVaultSecretsOfficer'     = 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7'
    'ServiceBusDataSender'       = '69a216fc-b8fb-44d8-bc22-1f3c2cd27a39'
    'ServiceBusDataReceiver'     = '4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0'
    'CosmosDBDataContributor'    = '00000000-0000-0000-0000-000000000002'
    'Contributor'                = 'b24988ac-6180-42a0-ab88-20f7382dd24c'
    'Reader'                     = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
}

$resolvedRole = if ($roleMap.ContainsKey($Role)) { $roleMap[$Role] } else { $Role }

$subArgs = if ($Subscription) { @('--subscription', $Subscription) } else { @() }

Write-Host "==> Assigning role" -ForegroundColor Cyan
Write-Host "    Role        : $Role ($resolvedRole)"
Write-Host "    Principal   : $PrincipalId"
Write-Host "    Scope       : $Scope"

# Check if assignment already exists
$existing = az role assignment list `
    --assignee $PrincipalId `
    --role $resolvedRole `
    --scope $Scope `
    @subArgs `
    --query "[0].id" -o tsv 2>$null

if ($existing) {
    Write-Host "    Already assigned — skipping (idempotent)" -ForegroundColor Yellow
    exit 0
}

az role assignment create `
    --assignee $PrincipalId `
    --role $resolvedRole `
    --scope $Scope `
    @subArgs | Out-Null

Write-Host "    Done" -ForegroundColor Green
