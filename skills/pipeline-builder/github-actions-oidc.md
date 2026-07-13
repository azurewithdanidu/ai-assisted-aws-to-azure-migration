---
name: github-actions-oidc
description: Configure OIDC/Workload Identity Federation, workflow structure patterns, concurrency, SWA deployment, rollback strategy, and quality gates for GitHub Actions → Azure pipelines
---

# GitHub Actions OIDC Skill

## Purpose

Set up Azure Workload Identity Federation and produce production-ready GitHub Actions workflows that deploy to Azure using short-lived OIDC tokens — no service principal secrets stored in GitHub.

## When to Use

Before writing any GitHub Actions workflow that deploys to Azure.

---

## OIDC Authentication Setup (One-Time Per Environment)

Document these steps in `outputs/pipeline/setup-oidc.md` for a human with Azure AD permissions to execute:

```bash
# 1. Create app registration
APP_ID=$(az ad app create --display-name "gh-<repo>-<env>" --query appId -o tsv)

# 2. Create service principal
SP_ID=$(az ad sp create --id $APP_ID --query id -o tsv)

# 3. Assign Contributor on the resource group (for app deploys)
az role assignment create \
  --assignee $SP_ID \
  --role "Contributor" \
  --scope /subscriptions/<subscription-id>/resourceGroups/rg-<env>-migration

# 4. Assign User Access Administrator on RG (needed if Bicep creates role assignments)
az role assignment create \
  --assignee $SP_ID \
  --role "User Access Administrator" \
  --scope /subscriptions/<subscription-id>/resourceGroups/rg-<env>-migration

# 5. Create federated credential (repeat for each branch/environment)
az ad app federated-credential create --id $APP_ID --parameters - <<EOF
{
  "name": "gh-actions-<env>",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:<org>/<repo>:environment:<env>",
  "audiences": ["api://AzureADTokenExchange"]
}
EOF

# 6. Note these values for GitHub Secrets:
echo "AZURE_CLIENT_ID = $APP_ID"
echo "AZURE_TENANT_ID = $(az account show --query tenantId -o tsv)"
echo "AZURE_SUBSCRIPTION_ID = $(az account show --query id -o tsv)"
```

### Subject Filter Patterns

| Trigger | Subject string |
|---|---|
| Push to branch `main` | `repo:<org>/<repo>:ref:refs/heads/main` |
| GitHub Environment `prod` | `repo:<org>/<repo>:environment:prod` |
| Pull Request | `repo:<org>/<repo>:pull_request` |

### Required GitHub Secrets

Add these to GitHub Settings → Secrets and Variables → Actions:

| Secret | Scope | Value |
|---|---|---|
| `AZURE_CLIENT_ID` | Repo | App Registration client ID |
| `AZURE_TENANT_ID` | Repo | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Repo | Target subscription ID |
| `STATIC_WEB_APP_TOKEN` | Repo or Environment | SWA deployment token from Bicep output |

### Workflow Permissions Block (Always Include)

```yaml
permissions:
  id-token: write   # Required for OIDC token request
  contents: read
```

### Login Step

```yaml
- name: Azure Login (OIDC)
  uses: azure/login@v2
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

---

## Workflow Structure Patterns

### File Naming Convention

```
.github/workflows/
  deploy-infra.yml         # Bicep IaC
  deploy-functions.yml     # Azure Functions
  deploy-staticweb.yml     # Static Web Apps
  deploy-containers.yml    # Container Apps / AKS (if applicable)
  validate-pr.yml          # PR validation (lint + what-if, no deploy)
```

### Multi-Environment Trigger Pattern

```yaml
on:
  push:
    branches:
      - main        # → deploy to staging
    paths:
      - 'outputs/azure-functions/**'
      - '.github/workflows/deploy-functions.yml'
  pull_request:
    branches: [main]   # → validate only (no deploy)
  workflow_dispatch:
    inputs:
      environment:
        description: 'Target environment'
        required: true
        type: choice
        options: [dev, staging, prod]
```

### Concurrency Control (Prevents Overlapping Deploys)

```yaml
concurrency:
  group: deploy-${{ github.ref }}-${{ inputs.environment || 'auto' }}
  cancel-in-progress: false   # Do NOT cancel in-progress deploys — let them finish
```

### Resource Tagging on Every Deploy

```yaml
- name: Tag deployment
  run: |
    az tag create \
      --resource-id "/subscriptions/${{ secrets.AZURE_SUBSCRIPTION_ID }}/resourceGroups/${{ vars.RESOURCE_GROUP_NAME }}" \
      --tags environment=${{ vars.ENV }} deployedBy=github-actions repo=${{ github.repository }} runId=${{ github.run_id }}
```

---

## Azure Static Web Apps Deployment

```yaml
jobs:
  deploy-static-web:
    runs-on: ubuntu-latest
    environment: ${{ vars.ENV }}
    permissions:
      id-token: write
      contents: read
    steps:
      - uses: actions/checkout@v4

      # SWA requires index.html as default document — verify before deploy
      - name: Verify index.html exists
        run: |
          if [ ! -f "source-app/app-code/build/index.html" ]; then
            echo "ERROR: index.html not found. SWA requires index.html as the default document."
            exit 1
          fi

      - name: Deploy to Azure Static Web Apps
        uses: Azure/static-web-apps-deploy@v1
        with:
          azure_static_web_apps_api_token: ${{ secrets.STATIC_WEB_APP_TOKEN }}
          action: upload
          app_location: source-app/app-code/build   # Folder containing index.html
          skip_app_build: true                        # Pre-built; do not re-build
```

**Critical SWA rules:**
- `index.html` MUST exist as the default document — `app.html` alone is rejected
- Use `skip_app_build: true` for pre-built apps
- The SWA deployment token comes from the Bicep `outputs.staticWebAppDeploymentToken`; store in `STATIC_WEB_APP_TOKEN` GitHub Secret
- Wrong args to avoid: `--skipBuild`, `--branch`, `--deploymentToken` (use `--apiToken`)

---

## Rollback Strategy

### Azure Functions — Slot Swap Rollback

```yaml
- name: Rollback Function App
  if: failure()
  run: |
    az functionapp deployment slot swap \
      --resource-group ${{ vars.RESOURCE_GROUP_NAME }} \
      --name ${{ vars.FUNCTION_APP_NAME }} \
      --slot staging \
      --target-slot production
    echo "Rollback complete — production reverted to previous deployment"
```

### Bicep — Redeploy Previous Template

```yaml
- name: Rollback IaC to previous commit
  if: failure()
  run: |
    PREV_SHA=$(git rev-parse HEAD~1)
    git show $PREV_SHA:outputs/bicep-templates/main.bicep > /tmp/main-prev.bicep
    az deployment group create \
      --resource-group ${{ vars.RESOURCE_GROUP_NAME }} \
      --template-file /tmp/main-prev.bicep \
      --parameters outputs/bicep-templates/parameters/${{ vars.ENV }}.bicepparam \
      --name "rollback-${{ github.run_id }}"
```

General rollback rules:
- Every deployment job must have an `if: failure()` rollback step
- Tag the rollback deployment: `--name "rollback-${{ github.run_id }}"`
- Never use `--no-wait` on deployment commands — wait for completion to detect failures

---

## Quality Gates — PR Validation Workflow

```yaml
# .github/workflows/validate-pr.yml
on:
  pull_request:
    branches: [main]

jobs:
  lint-and-validate:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
      pull-requests: write
    steps:
      - uses: actions/checkout@v4

      - name: Azure Login (OIDC)
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Lint Bicep
        run: az bicep build --file outputs/bicep-templates/main.bicep

      - name: Bicep What-If (PR comment)
        run: |
          az deployment group what-if \
            --resource-group ${{ vars.RESOURCE_GROUP_NAME }} \
            --template-file outputs/bicep-templates/main.bicep \
            --parameters outputs/bicep-templates/parameters/dev.bicepparam \
            2>&1 | tee what-if-output.txt

      - name: Post What-If to PR
        uses: actions/github-script@v7
        with:
          script: |
            const fs = require('fs');
            const output = fs.readFileSync('what-if-output.txt', 'utf8');
            github.rest.issues.createComment({
              issue_number: context.issue.number,
              owner: context.repo.owner,
              repo: context.repo.repo,
              body: '## Bicep What-If\n```\n' + output.slice(0, 60000) + '\n```'
            });
```

---

## Action Version Pinning

Always pin action versions to a specific tag or SHA for production workflows:

```yaml
# Pinned versions — update deliberately, not automatically
uses: actions/checkout@v4
uses: actions/setup-python@v5
uses: azure/login@v2
uses: Azure/functions-action@v1
uses: Azure/static-web-apps-deploy@v1
uses: actions/github-script@v7
uses: actions/upload-artifact@v4
```

For highest security, pin to full commit SHA:
```yaml
uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
uses: azure/login@6c251865b4e6290e7b78be643ea2d005bc51f69a       # v2.1.1
```

---

## Rules

- **Never use client secrets or certificates** — OIDC federated credentials only.
- **Never assign Owner or User Access Administrator at subscription scope** — scope to the resource group.
- **Always add a separate federated credential per branch/environment** that needs to deploy.
- **Always set `permissions: id-token: write`** — without it, the OIDC token is not issued.
- **Never store `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, or `AZURE_SUBSCRIPTION_ID` as environment-level secrets** — these are shared and belong as repo-level secrets.
- **Never auto-deploy to prod on push** — require manual `workflow_dispatch` with approval gate.
- **Never hardcode resource group names or resource names in workflow YAML** — always use `${{ vars.RESOURCE_GROUP_NAME }}` or equivalent.
- **Always pin action versions** — never use `@latest` or a moving tag.

## Output

- `outputs/pipeline/setup-oidc.md` — exact `az` commands for human to run
- `outputs/pipeline/setup-environments.md` — GitHub Environment protection rules to configure
- Every workflow file uses `azure/login@v2` with OIDC parameters
- GitHub secrets documented in `design-document.md` Section 11.2

---

## Companion Scripts

| Script | Purpose |
|---|---|
| `scripts/setup-oidc.ps1` | Creates App Registration, Service Principal, federated credential, and RBAC assignments |
| `scripts/setup-oidc.sh` | Bash equivalent of the above |

Run once per environment before creating GitHub workflows:

```powershell
./.github/skills/agents/pipeline-builder/scripts/setup-oidc.ps1 \
    -GitHubOrg "azurewithdanidu" \
    -GitHubRepo "ai-assisted-aws-to-azure-migration" \
    -Environment prod \
    -Subscription "<subscription-id>" \
    -ResourceGroup "rg-prod-migration"
```

The script prints the three GitHub Secrets values (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`) and writes `outputs/pipeline/setup-oidc.md`.

---

## References

### GitHub Documentation

| Topic | Link |
|---|---|
| About OIDC security hardening | https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/about-security-hardening-with-openid-connect |
| Configuring OIDC in Azure | https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-azure |
| GitHub Actions permissions | https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions#permissions |
| GitHub Actions concurrency | https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions#concurrency |
| Encrypted secrets in GitHub Actions | https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions |
| GitHub Actions OIDC subject claims | https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/about-security-hardening-with-openid-connect#understanding-the-oidc-token |

### Microsoft / Azure Documentation

| Topic | Link |
|---|---|
| Azure Workload Identity Federation | https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation |
| Configure federated identity credential | https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation-create-trust |
| `azure/login` GitHub Action | https://github.com/Azure/login |
| `Azure/functions-action` | https://github.com/Azure/functions-action |
| `Azure/static-web-apps-deploy` | https://github.com/Azure/static-web-apps-deploy |
| Least-privilege OIDC setup | https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure-openid-connect |
| `az ad app federated-credential` CLI | https://learn.microsoft.com/en-us/cli/azure/ad/app/federated-credential |
| GitHub Actions OIDC with Azure tutorial | https://learn.microsoft.com/en-us/azure/developer/github/connect-from-azure |

### Best Practices

- **One federated credential per branch/environment** — never use a wildcard subject like `repo:*:*`. Scope to `environment:prod` or `ref:refs/heads/main` to limit blast radius.
- **Scope role assignments to resource group, not subscription** — `Contributor` at subscription scope grants access to all resources in the subscription. Scope to `rg-<env>-migration` only.
- **`User Access Administrator` is required when Bicep creates role assignments** — this allows the pipeline to assign RBAC roles to managed identities as part of IaC deployment.
- **Pin action versions to full SHA for highest security** — tag-based pinning (`@v2`) is vulnerable to tag mutation attacks. Use commit SHA pinning in production pipelines.
