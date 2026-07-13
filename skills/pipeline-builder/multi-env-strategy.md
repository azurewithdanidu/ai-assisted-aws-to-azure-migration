---
name: multi-env-strategy
description: Define branch-to-environment mapping, GitHub Environment protection rules, approval gates, and secret separation for dev/staging/prod
---

# Multi-Environment Strategy Skill

## Purpose

Define a consistent, auditable promotion path from dev → staging → prod using GitHub Environments so no accidental production deployments can occur.

## When to Use

When structuring GitHub Actions workflows that target multiple environments.

## Process

1. **Branch-to-environment mapping:**

   | Branch / Trigger | Environment | Auto-deploy? |
   |---|---|---|
   | Any PR | dev | Yes (on PR open/update) |
   | Push to `main` | staging | Yes |
   | Manual `workflow_dispatch` | prod | No — approval required |

2. **GitHub Environment configuration** (document for human setup in repo Settings → Environments):

   | Environment | Protection Rules |
   |---|---|
   | `dev` | None — auto-approve |
   | `staging` | 1 required reviewer |
   | `prod` | 2 required reviewers + 10-minute wait timer |

3. **Secret separation** — never use repo-level secrets for environment-specific values:

   | Secret | Scope | Reason |
   |---|---|---|
   | `AZURE_CLIENT_ID` | Repo | Shared OIDC app registration |
   | `AZURE_TENANT_ID` | Repo | Same for all environments |
   | `AZURE_SUBSCRIPTION_ID` | Repo | Same subscription, different RGs |
   | `RESOURCE_GROUP_NAME` | Environment | `rg-dev-migration` / `rg-staging-migration` / `rg-prod-migration` |
   | `FUNCTION_APP_NAME` | Environment | Different per environment |

4. **In workflow YAML**, set the environment per job:

   ```yaml
   jobs:
     deploy-staging:
       runs-on: ubuntu-latest
       environment: staging
       steps:
         - uses: actions/checkout@v4
         - name: Azure Login
           uses: azure/login@v2
           with:
             client-id: ${{ secrets.AZURE_CLIENT_ID }}
             tenant-id: ${{ secrets.AZURE_TENANT_ID }}
             subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
         - name: Deploy
           run: |
             az deployment group create \
               --resource-group ${{ vars.RESOURCE_GROUP_NAME }} \
               --template-file outputs/bicep-templates/main.bicep \
               --parameters outputs/bicep-templates/parameters/staging.bicepparam
   ```

## Rules

- **Never auto-deploy to prod on push** — always require manual `workflow_dispatch` with approval gate.
- **Never use repo-level secrets for environment-specific values** — always use GitHub Environment secrets or variables.
- **Never hardcode resource group names or resource names in workflow YAML** — always use `${{ vars.RESOURCE_GROUP_NAME }}` or equivalent.
- **Always set `environment: <name>`** on jobs that deploy to a specific environment — this triggers protection rules.

## Output

- A `setup-environments.md` in `outputs/pipeline/` documenting the environment configuration a human must create in GitHub Settings
- Every workflow job targeting a specific environment has `environment: <name>` set

---

## References

### GitHub Documentation

| Topic | Link |
|---|---|
| GitHub Environments overview | https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment |
| Environment protection rules | https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment#environment-protection-rules |
| Required reviewers | https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment#required-reviewers |
| Wait timer | https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment#wait-timer |
| Environment secrets and variables | https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment#environment-secrets |
| Using secrets in GitHub Actions | https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions |
| `workflow_dispatch` inputs | https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#workflow_dispatch |

### Microsoft / Azure Documentation

| Topic | Link |
|---|---|
| Azure deployment environments | https://learn.microsoft.com/en-us/azure/deployment-environments/overview-what-is-azure-deployment-environments |
| Azure resource group naming best practices | https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming |
| Azure landing zone naming conventions | https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations |

### Best Practices

- **Never auto-deploy to prod from any push trigger** — production deployments must always require a human reviewer via GitHub Environment protection rules and `workflow_dispatch`.
- **Environment secrets over repo secrets for per-environment values** — this prevents a dev deployment from accidentally using prod credentials or resource group names.
- **Add a 10-minute wait timer to prod** — this provides a short window to cancel an approved deployment if a mistake is noticed after approval.
- **Separate reviewer teams for staging vs prod** — staging approval can be any team member; prod approval should require a lead engineer or ops team member.
