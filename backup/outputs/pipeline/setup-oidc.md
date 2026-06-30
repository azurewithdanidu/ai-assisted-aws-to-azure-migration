# OIDC / Workload Identity Federation Setup

> **One-time human setup** — run these commands once per environment before the
> GitHub Actions workflows can authenticate to Azure via OIDC.
>
> **Prerequisites:** `az` CLI authenticated as an Entra Global Administrator or
> Application Administrator with Owner on the target subscription or resource group.

---

## Repository & Environment Details

| Field | Value |
|---|---|
| GitHub Org / Repo | `azurewithdanidu/ai-assisted-aws-to-azure-migration` |
| Azure Subscription | Set via `AZURE_SUBSCRIPTION_ID` GitHub Secret |
| Resource Group | `rg-image-upload` (`vars.RESOURCE_GROUP_NAME`) |
| Default Environment | `dev` (`vars.ENVIRONMENT`) |

---

## Step 1 — Create App Registration and Service Principal

```bash
# Create the App Registration (one per repo, shared across all environments)
APP_ID=$(az ad app create \
  --display-name "gh-azurewithdanidu-ai-assisted-aws-to-azure-migration" \
  --query appId -o tsv)

# Create the Service Principal
SP_ID=$(az ad sp create --id "$APP_ID" --query id -o tsv)

echo "App Registration Client ID : $APP_ID"
echo "Service Principal Object ID: $SP_ID"
```

---

## Step 2 — Assign RBAC Roles (§11.6)

The deployment identity requires two roles on the resource group `rg-image-upload`.

```bash
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
RESOURCE_GROUP="rg-image-upload"

# Contributor — allows deploy of all resources
az role assignment create \
  --assignee "$SP_ID" \
  --role "Contributor" \
  --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}"

# User Access Administrator — required because Bicep creates role assignments
# for the Function App managed identity (§11.6)
az role assignment create \
  --assignee "$SP_ID" \
  --role "User Access Administrator" \
  --scope "/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}"
```

---

## Step 3 — Create Federated Credentials

Create one federated credential per GitHub Environment / branch that deploys.

### dev environment (push to `main`)

```bash
az ad app federated-credential create --id "$APP_ID" --parameters '{
  "name": "gh-actions-dev",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:azurewithdanidu/ai-assisted-aws-to-azure-migration:environment:dev",
  "audiences": ["api://AzureADTokenExchange"]
}'
```

### staging environment

```bash
az ad app federated-credential create --id "$APP_ID" --parameters '{
  "name": "gh-actions-staging",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:azurewithdanidu/ai-assisted-aws-to-azure-migration:environment:staging",
  "audiences": ["api://AzureADTokenExchange"]
}'
```

### prod environment

```bash
az ad app federated-credential create --id "$APP_ID" --parameters '{
  "name": "gh-actions-prod",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:azurewithdanidu/ai-assisted-aws-to-azure-migration:environment:prod",
  "audiences": ["api://AzureADTokenExchange"]
}'
```

---

## Step 4 — Add GitHub Secrets

Navigate to **GitHub → Settings → Secrets and Variables → Actions → Secrets** and add:

| Secret Name | Value | Scope |
|---|---|---|
| `AZURE_CLIENT_ID` | `$APP_ID` from Step 1 | Repository |
| `AZURE_TENANT_ID` | `$(az account show --query tenantId -o tsv)` | Repository |
| `AZURE_SUBSCRIPTION_ID` | `$(az account show --query id -o tsv)` | Repository |

```bash
# Print values to copy into GitHub Secrets
echo "AZURE_CLIENT_ID       = $APP_ID"
echo "AZURE_TENANT_ID       = $(az account show --query tenantId -o tsv)"
echo "AZURE_SUBSCRIPTION_ID = $(az account show --query id -o tsv)"
```

> ⚠️ These three secrets are **repository-level**, not environment-level.
> They are shared across dev/staging/prod.

---

## Step 5 — Add GitHub Repository Variables

Navigate to **GitHub → Settings → Secrets and Variables → Actions → Variables** and add:

| Variable | Value |
|---|---|
| `RESOURCE_GROUP_NAME` | `rg-image-upload` |
| `LOCATION` | `australiasoutheast` |
| `ENVIRONMENT` | `dev` |
| `FUNCTION_APP_NAME` | `img-upload-func-dev-ase` |
| `STATIC_WEB_APP_NAME` | `img-upload-swa-dev-ase` |
| `BICEP_TEMPLATE` | `outputs/bicep-templates/main.bicep` |
| `BICEP_PARAMETERS` | `outputs/bicep-templates/parameters/dev.bicepparam` |

---

## Verification

After completing all steps, trigger a test run:

```bash
gh workflow run deploy-infra.yml \
  --repo azurewithdanidu/ai-assisted-aws-to-azure-migration \
  --field environment=dev
```

Expected: the `validate` job should authenticate to Azure, run `az bicep build`, and run `what-if` without errors.

---

## References

- [Configuring OIDC in Azure](https://docs.github.com/en/actions/security-for-github-actions/security-hardening-your-deployments/configuring-openid-connect-in-azure)
- [Azure Workload Identity Federation](https://learn.microsoft.com/en-us/entra/workload-id/workload-identity-federation)
- [az ad app federated-credential](https://learn.microsoft.com/en-us/cli/azure/ad/app/federated-credential)
