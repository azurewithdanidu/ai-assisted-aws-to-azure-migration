# Azure Migration Deployment Validation Report

**Date:** 2026-04-18  
**Validator:** Deployment Validation Agent  
**Workspace:** `d:\MVP\Boot-Camp-2025\ai-assisted-aws-to-azure-migration`  
**Scope:** Static pre-deployment analysis — no live Azure calls  
**Reference:** [design-document.md](azure-architecture-output/design-document.md) §10 Validation Checklist

---

## Status: PASSED

All 15 required pre-deployment checks pass. Three warnings are documented below; none block deployment.

**Summary**

| Category | Checks | PASS | FAIL | WARN |
|---|---|---|---|---|
| Bicep Templates | 5 | 5 | 0 | 1 |
| Azure Functions Code | 6 | 6 | 0 | 1 |
| CI/CD Pipelines | 4 | 4 | 0 | 0 |
| Security | 1 | 1 | 0 | 1 |
| **TOTAL** | **16** | **16** | **0** | **3** |

---

## Detailed Checklist

### Bicep Templates (`outputs/bicep-templates/`)

| # | Check | Status | Notes |
|---|---|---|---|
| 1 | `main.bicep` has `targetScope = 'subscription'` | ✅ PASS | Line 1 of `main.bicep`: `targetScope = 'subscription'` — enables subscription-scoped RG creation and deployment |
| 2 | All 6 modules present (monitoring, storage, staticweb, keyvault, functions, rbac) and no apim module referenced in `main.bicep` | ✅ PASS | All 6 modules referenced in `main.bicep`. `apim.bicep` file exists in modules/ but is **not** imported or called from `main.bicep`. ⚠️ See Warning W-1 |
| 3 | `BLOB_CONTAINER_NAME` used throughout; `CONTAINER_NAME` (reserved) absent | ✅ PASS | `functions.bicep` app setting name is `BLOB_CONTAINER_NAME`; `CONTAINER_NAME` does not appear in any `outputs/` file |
| 4 | `functions.bicep` uses `Python\|3.11` runtime and system-assigned managed identity | ✅ PASS | `linuxFxVersion: 'Python\|3.11'`; `managedIdentities: { systemAssigned: true }` |
| 5 | `storage.bicep` has `allowBlobPublicAccess: false` and `supportsHttpsTrafficOnly: true` | ✅ PASS | Both properties set in the AVM `storage-account` module call |

---

### Azure Functions Code (`outputs/azure-functions/`)

| # | Check | Status | Notes |
|---|---|---|---|
| 6 | `function_app.py` imports `DefaultAzureCredential` and `azure-storage-blob`; no `boto3` | ✅ PASS | `from azure.identity import DefaultAzureCredential`; `from azure.storage.blob import BlobServiceClient, BlobSasPermissions, generate_blob_sas` — no `boto3` import |
| 7 | `CONTAINER_NAME` (bare) never referenced; only `BLOB_CONTAINER_NAME` used | ✅ PASS | `BLOB_CONTAINER_NAME = os.environ["BLOB_CONTAINER_NAME"]` — used at lines 22, 71, 79, 187, 282, 358. Bare `CONTAINER_NAME` absent throughout |
| 8 | All 4 API routes present: `POST /api/upload`, `GET /api/files`, `GET /api/files/{fileId}/view-url`, `DELETE /api/files/{fileId}` | ✅ PASS | `@app.route(route="upload", methods=["POST"])` ✓; `@app.route(route="files", methods=["GET"])` ✓; `@app.route(route="files/{fileId}/view-url", methods=["GET"])` ✓; `@app.route(route="files/{fileId}", methods=["DELETE"])` ✓ |
| 9 | `host.json` is schema version `2.0` with extension bundle `[4.*, 5.0.0)` | ✅ PASS | `"version": "2.0"`; `"id": "Microsoft.Azure.Functions.ExtensionBundle"`; `"version": "[4.*, 5.0.0)"` |
| 10 | `requirements.txt` contains `azure-functions`, `azure-storage-blob`, `azure-identity`; does NOT contain `boto3` | ✅ PASS | File contains exactly: `azure-functions`, `azure-storage-blob>=12.19.0`, `azure-identity>=1.15.0` — no `boto3` |
| 11 | `local.settings.json` uses `BLOB_CONTAINER_NAME` and no reserved variable names | ✅ PASS | Settings: `FUNCTIONS_WORKER_RUNTIME`, `AzureWebJobsStorage` (Azurite placeholder), `BLOB_CONTAINER_NAME`, `AZURE_STORAGE_ACCOUNT_NAME`, `URL_EXPIRATION` — no `CONTAINER_NAME`, no `WEBSITE_*` misuse. ⚠️ See Warning W-3 |

---

### CI/CD Pipelines (`.github/workflows/`)

| # | Check | Status | Notes |
|---|---|---|---|
| 12 | `deploy-infra.yml` uses `az deployment sub create` (subscription scope, not group scope) | ✅ PASS | Both the what-if step (`az deployment sub what-if`) and deploy step (`az deployment sub create`) use subscription scope — matches `targetScope = 'subscription'` in `main.bicep` |
| 13 | `deploy-functions.yml` uses Python 3.11 | ✅ PASS | `uses: actions/setup-python@v5` with `python-version: '3.11'`; comment explains why: "Azure Functions v4: 3.9–3.11 only; 3.12+ crashes" |
| 14 | No workflow references `APIM` or `apimGatewayUrl` | ✅ PASS | Searched all three workflow files — zero APIM references |
| 15 | OIDC authentication: `azure/login@v2` with `client-id`, `tenant-id`, `subscription-id` — no `client-secret` | ✅ PASS | Both `deploy-infra.yml` and `deploy-functions.yml` use `azure/login@v2` with federated credential secrets only. `deploy-static-web.yml` uses SWA deployment token (`STATIC_WEB_APP_TOKEN`) — no client-secret anywhere |

---

### Security

| # | Check | Status | Notes |
|---|---|---|---|
| 16 | No hardcoded credentials, access keys, or secrets in any generated file | ✅ PASS | No literal AWS keys, passwords, or SAS tokens found. `local.settings.json` uses `"UseDevelopmentStorage=true"` (Azurite placeholder) and `"<your-storage-account-name>"` (placeholder). All workflows use `${{ secrets.* }}` references. ⚠️ See Warning W-2 |

---

## Warnings (Non-Blocking)

### W-1 — Orphaned `apim.bicep` module file

**File:** `outputs/bicep-templates/modules/apim.bicep`  
**Finding:** The file exists and is syntactically complete (deploys `Microsoft.ApiManagement/service`) but is **not imported** in `main.bicep`. It is never deployed. This is a leftover from an earlier design iteration before APIM was removed from the architecture.  
**Risk:** None for deployment. Could cause confusion during future maintenance.  
**Recommendation:** Delete `outputs/bicep-templates/modules/apim.bicep` to keep the modules directory clean.

```bash
# Safe to delete — not referenced from main.bicep
del outputs\bicep-templates\modules\apim.bicep
```

---

### W-2 — `AzureWebJobsStorage` uses `listKeys()` in Bicep

**File:** `outputs/bicep-templates/modules/functions.bicep`  
**Finding:** The `AzureWebJobsStorage` app setting is constructed with `funcStorageAccount.listKeys().keys[0].value` — a Bicep ARM function call evaluated at deploy time. The key is stored as a Function App app setting (encrypted at rest by Azure).  
**Context:** This is the **required** pattern for Azure Functions Consumption plan trigger infrastructure (AzureWebJobsStorage cannot use managed identity at the infrastructure level on Consumption/Y1). The Functions runtime uses this for trigger coordination, not for the application's blob operations (which use `DefaultAzureCredential`/managed identity).  
**Risk:** Low — the key is not hardcoded, is encrypted at rest, and is scoped to the Functions runtime storage account (not the images storage account). No application code reads it.  
**Recommendation:** No immediate action required. For defence-in-depth: rotate the Functions runtime storage account key quarterly and consider migrating to Azure Functions Flex Consumption plan once available in `australiaeast`, which supports managed identity for `AzureWebJobsStorage`.

---

### W-3 — Architecture diagram references APIM (documentation drift)

**File:** `outputs/azure-architecture-output/architecture-diagram-azure.mmd`  
**Finding:** The Mermaid diagram references APIM nodes and `Ocp-Apim-Subscription-Key` header from an earlier design iteration. The actual IaC (Bicep) and code correctly have no APIM.  
**Risk:** None for deployment. Documentation inconsistency only.  
**Recommendation:** Update `architecture-diagram-azure.mmd` to remove APIM nodes and replace with a direct browser → Azure Functions arrow. Not required before deployment.

---

## Design Document vs. Actual Implementation Notes

| Point | Design Doc §11.3.1 Spec | Actual `deploy-infra.yml` | Verdict |
|---|---|---|---|
| Infra deploy command | `az deployment group create` | `az deployment sub create` | **Implementation is correct.** Design doc contains a stale reference to group-scope deployment. The actual workflow correctly matches `targetScope = 'subscription'`. |
| Bicep what-if | `az deployment group what-if` | `az deployment sub what-if` | **Implementation is correct.** Same issue — workflow is right. |

---

## Next Steps — Deployment Commands

Complete these steps in order to deploy the full stack to Azure.

### Prerequisites

```bash
# 1. Install Azure CLI (if not already installed)
winget install Microsoft.AzureCLI

# 2. Install Bicep CLI
az bicep install

# 3. Log in to Azure
az login

# 4. Set your subscription
az account set --subscription "<your-subscription-id>"
```

### Step 1 — Register an App Registration for OIDC (one-time)

```bash
# Create the App Registration
az ad app create --display-name "img-upload-github-oidc"

# Note the appId (CLIENT_ID) from output, then create service principal
az ad sp create --id <appId>

# Assign Contributor role on the subscription (or narrow to RG after first deploy)
az role assignment create \
  --assignee <appId> \
  --role Contributor \
  --scope /subscriptions/<your-subscription-id>

# Assign RBAC Administrator (needed so the deploy can assign MI roles in rbac.bicep)
az role assignment create \
  --assignee <appId> \
  --role "Role Based Access Control Administrator" \
  --scope /subscriptions/<your-subscription-id>

# Add federated credential for GitHub Actions main branch
az ad app federated-credential create \
  --id <appId> \
  --parameters '{
    "name": "github-main",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:<owner>/<repo>:ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
  }'
```

Then add these GitHub repository secrets:
- `AZURE_CLIENT_ID` — App Registration `appId`
- `AZURE_TENANT_ID` — your Azure AD tenant ID (`az account show --query tenantId -o tsv`)
- `AZURE_SUBSCRIPTION_ID` — your subscription ID (`az account show --query id -o tsv`)
- `AZURE_RESOURCE_GROUP` — `img-upload-dev-rg` (created by Bicep)
- `AZURE_FUNCTION_APP_NAME` — `img-upload-dev-func`

### Step 2 — Validate Bicep Templates (local, no deployment)

```bash
cd d:\MVP\Boot-Camp-2025\ai-assisted-aws-to-azure-migration

# Lint all modules
az bicep lint --file outputs/bicep-templates/main.bicep

# What-if dry run (dev environment)
az deployment sub what-if \
  --location australiaeast \
  --template-file outputs/bicep-templates/main.bicep \
  --parameters outputs/bicep-templates/parameters/dev.bicepparam \
  --name "whatif-manual"
```

### Step 3 — Deploy Infrastructure (Bicep, subscription scope)

```bash
# Deploy dev environment
az deployment sub create \
  --location australiaeast \
  --template-file outputs/bicep-templates/main.bicep \
  --parameters outputs/bicep-templates/parameters/dev.bicepparam \
  --name "deploy-$(date +%s)" \
  --output json

# Capture outputs (Function App URL, Storage Account Name, etc.)
az deployment sub show \
  --name "deploy-<run-id>" \
  --query "properties.outputs" \
  --output table
```

### Step 4 — Deploy Azure Functions (ZIP deploy)

```bash
cd outputs/azure-functions

# Create Python 3.11 virtual environment and install dependencies
python3.11 -m venv .venv
.venv\Scripts\activate

pip install -r requirements.txt \
  --target .python_packages/lib/site-packages \
  --upgrade

# Create deployment ZIP
cd ..
zip -r function-deploy.zip azure-functions/ \
  --exclude '*.pyc' \
  --exclude '__pycache__/*' \
  --exclude '.git/*'

# Deploy to Azure Functions
az functionapp deployment source config-zip \
  --resource-group img-upload-dev-rg \
  --name img-upload-dev-func \
  --src function-deploy.zip \
  --build-remote false \
  --timeout 300
```

### Step 5 — Deploy Static Web App

```bash
# Get the deployment token
STATIC_WEB_APP_TOKEN=$(az staticwebapp secrets list \
  --name img-upload-dev-swa \
  --resource-group img-upload-dev-rg \
  --query "properties.apiKey" \
  --output tsv)

# Deploy using SWA CLI
npx @azure/static-web-apps-cli deploy outputs/static-web-app \
  --deployment-token "$STATIC_WEB_APP_TOKEN" \
  --env production
```

### Step 6 — Post-Deployment Smoke Tests

Run these against the deployed environment (replace `img-upload-dev-func` with your actual Function App name):

```bash
BASE="https://img-upload-dev-func.azurewebsites.net/api"

# 1. Upload — expect HTTP 200 with uploadUrl in body
curl -s -X POST "$BASE/upload" \
  -H "Content-Type: application/json" \
  -d '{"fileName":"validation-test.jpg","fileType":"image/jpeg"}' | python3 -m json.tool

# 2. List files — expect HTTP 200 with files array
curl -s "$BASE/files" | python3 -m json.tool

# 3. View URL (replace <fileId> from upload response)
curl -s "$BASE/files/<fileId>/view-url" | python3 -m json.tool

# 4. Delete (replace <fileId>)
curl -s -X DELETE "$BASE/files/<fileId>" | python3 -m json.tool

# 5. Confirm deletion — file should not appear
curl -s "$BASE/files" | python3 -m json.tool

# 6. Confirm CONTAINER_NAME app setting is absent
az functionapp config appsettings list \
  --resource-group img-upload-dev-rg \
  --name img-upload-dev-func \
  --query "[?name=='CONTAINER_NAME']"
# Expected: [] (empty array)

# 7. Confirm Python 3.11 runtime
az functionapp config show \
  --resource-group img-upload-dev-rg \
  --name img-upload-dev-func \
  --query linuxFxVersion
# Expected: "Python|3.11"
```

### Step 7 — Promote to Staging / Production

```bash
# Staging
az deployment sub create \
  --location australiaeast \
  --template-file outputs/bicep-templates/main.bicep \
  --parameters outputs/bicep-templates/parameters/staging.bicepparam \
  --name "deploy-staging-$(date +%s)"

# Production
az deployment sub create \
  --location australiaeast \
  --template-file outputs/bicep-templates/main.bicep \
  --parameters outputs/bicep-templates/parameters/prod.bicepparam \
  --name "deploy-prod-$(date +%s)"
```

### Cleanup (Optional — after AWS decommission)

```bash
# After successful cutover, delete AWS stack
aws cloudformation delete-stack --stack-name image-upload --region ap-southeast-2

# Invalidate and rotate the leaked AWS access key
aws iam delete-access-key \
  --user-name image-upload-api-user \
  --access-key-id AKIAXZEFIIOD2OIWPRPK
```

---

## Sign-Off

| Role | Status | Notes |
|---|---|---|
| Pre-deployment static validation | ✅ Complete | All 15 checks pass; 3 non-blocking warnings |
| Live Azure deployment | ⏳ Pending | Requires Azure subscription + secrets configured |
| Smoke tests | ⏳ Pending | Run after Step 4 (Functions deploy) |
| AWS decommission | ⏳ Pending | After successful production smoke tests |

---

*Report generated by: Deployment Validation Agent*  
*Validation method: Static file analysis of workspace artifacts (no live Azure API calls)*  
*Next validation: Post-deployment smoke test run (live)*
