---
name: github-actions-oidc
description: Configure OIDC/Workload Identity Federation so GitHub Actions can deploy to Azure without long-lived credentials
---

# GitHub Actions OIDC Skill

## Purpose

Set up Azure Workload Identity Federation so GitHub Actions workflows can authenticate to Azure using short-lived OIDC tokens — no service principal secrets stored in GitHub.

## When to Use

Before writing any GitHub Actions workflow that deploys to Azure.

## Process

1. Document the setup steps (to be executed by a human with Azure AD permissions):

```bash
# 1. Create an Azure AD app registration
APP_ID=$(az ad app create --display-name "github-actions-<repo-name>" --query appId -o tsv)

# 2. Create a service principal
SP_OBJECT_ID=$(az ad sp create --id $APP_ID --query id -o tsv)

# 3. Add federated credential for the main branch
az ad app federated-credential create --id $APP_ID --parameters '{
  "name": "main-branch",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:<github-org>/<repo-name>:ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"]
}'

# 4. Assign Contributor on the resource group
az role assignment create \
  --assignee $SP_OBJECT_ID \
  --role "Contributor" \
  --scope /subscriptions/<subscription-id>/resourceGroups/rg-<env>-migration

# 5. Assign User Access Administrator on RG (needed for Bicep role assignments)
az role assignment create \
  --assignee $SP_OBJECT_ID \
  --role "User Access Administrator" \
  --scope /subscriptions/<subscription-id>/resourceGroups/rg-<env>-migration
```

2. Add these GitHub secrets (Settings → Secrets → Actions):
   - `AZURE_CLIENT_ID` — the App Registration client ID (`$APP_ID`)
   - `AZURE_TENANT_ID` — the Azure AD tenant ID
   - `AZURE_SUBSCRIPTION_ID` — the target subscription ID

3. In every workflow YAML that deploys to Azure, add these permissions and login step:

```yaml
permissions:
  id-token: write
  contents: read

steps:
  - name: Azure Login (OIDC)
    uses: azure/login@v2
    with:
      client-id: ${{ secrets.AZURE_CLIENT_ID }}
      tenant-id: ${{ secrets.AZURE_TENANT_ID }}
      subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

## Rules

- **Never use client secrets or certificates** — OIDC federated credentials only.
- **Never assign Owner or User Access Administrator at subscription scope** — scope to the resource group.
- **Always add a separate federated credential per branch/environment** that needs to deploy.
- **Always set `permissions: id-token: write`** in every workflow that uses OIDC — without it, the token is not issued.
- **Never store `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, or `AZURE_SUBSCRIPTION_ID` as environment-level secrets** — these are shared and belong as repo-level secrets.

## Output

- A `setup-oidc.md` document in `outputs/pipeline/` listing the exact `az` commands for a human to run
- GitHub secrets documented in `design-document.md` Section 11.2
- Every workflow file using `azure/login@v2` with OIDC parameters
