---
name: azure-deployer
description: >
  Deploy Azure infrastructure and application code from the outputs/ folder. Use when:
  deploying Bicep IaC templates to Azure, publishing Azure Functions, deploying to dev/staging/prod,
  running a manual deployment from outputs/bicep-templates/ or outputs/azure-functions/,
  deploying infrastructure first then app code, deploying after migration phases complete.
  Deploys in order: Bicep IaC → Azure Functions → Static Web App content.
argument-hint: "environment (dev | staging | prod) — omit to be prompted"
tools: [execute, read, search, edit, todo, 'mcp_docker/*']
---

# Azure Deployer Agent

Deploy the Azure infrastructure and application code produced by the migration pipeline from the
`outputs/` folder. Always deploy IaC before app code. Never modify source files.

This agent performs **manual deployment only**. Do not trigger or depend on GitHub Actions
pipelines for deployment execution.

> **READ-ONLY SOURCES** — `source-app/` and `outputs/` are inputs only. This agent writes
> deployment logs and status updates to `outputs/deployment-log.md` — nothing else.

---

## Step 1 — Collect Deployment Inputs

Before doing anything, confirm the following. If any value is missing, ask the user:

| Input | Description | Default |
|---|---|---|
| **Environment** | Target environment to deploy to | *(required: `dev`, `staging`, or `prod`)* |
| **Azure Subscription ID** | Target Azure subscription | *(required — no default)* |
| **Resource Group** | Target resource group name | *(required — no default)* |
| **Location** | Azure region | `australiaeast` (Sydney equivalent) |
| **Static Web App Name** | Target Static Web App resource | *(optional — derive from IaC outputs if not provided)* |

Once all inputs are confirmed, proceed to Step 2.

---

## Step 2 — Verify Azure Authentication

**This step is mandatory and cannot be skipped.** Do not proceed to Step 3 until authentication is confirmed.

### 2a — Try Azure CLI

Run `az account show` to check if the CLI is already authenticated.

- **Success and subscription matches** → go to Step 3.
- **Success but wrong subscription** → run `az account set --subscription <SUBSCRIPTION_ID>`, then re-run `az account show` to confirm, then go to Step 3.
- **Command not found, error, or no subscription** → proceed to 2b.

### 2b — Try Azure MCP Server

If the Azure CLI check failed, attempt a lightweight call via the Azure MCP server (e.g., list subscriptions or check the active account) to determine whether MCP auth is active.

- **MCP call succeeds** → confirm the correct subscription is targeted, then go to Step 3 using MCP tools for all Azure operations.
- **MCP call also fails** → proceed to 2c.

### 2c — Request Authentication from User

Both CLI and MCP are unauthenticated. Stop and display the following message. Do NOT proceed until the user replies "done":

---

> **Azure authentication is required before deployment can begin.**
>
> Please authenticate using one of the options below, then reply **"done"**.
>
> **Option A — Interactive browser login (recommended)**
> ```bash
> az login
> az account set --subscription <YOUR_SUBSCRIPTION_ID>
> az account show   # verify the correct subscription is active
> ```
>
> **Option B — Service Principal (CI/CD or headless environments)**
> ```bash
> az login --service-principal \
>   --username <APP_ID> \
>   --password <CLIENT_SECRET> \
>   --tenant <TENANT_ID>
> az account set --subscription <YOUR_SUBSCRIPTION_ID>
> ```
>
> **Option C — Device code login (no browser on this machine)**
> ```bash
> az login --use-device-code
> az account set --subscription <YOUR_SUBSCRIPTION_ID>
> ```
>
> **Option D — Azure MCP server session already active**
> If the Azure MCP server is configured and authenticated in your VS Code settings, reply "done" and this agent will use it instead of the CLI.

---

### 2d — Retry After "Done"

After the user replies "done":

1. Re-run `az account show`. If it succeeds and shows the correct subscription → go to Step 3.
2. If it fails again, retry the Azure MCP call. If that succeeds → go to Step 3.
3. If **both still fail** — print the exact error message(s) and ask the user to fix the authentication issue before retrying. **Do not proceed.**

---

## Step 3 — Pre-Deployment Checks

Before deploying, verify the required output artifacts exist:

| Artifact | Expected Path | Required For |
|---|---|---|
| Main Bicep template | `outputs/bicep-templates/main.bicep` | IaC deployment |
| Bicep parameters file | `outputs/bicep-templates/parameters/<env>.bicepparam` | IaC deployment |
| Functions app code | `outputs/azure-functions/` | App deployment |
| Functions requirements | `outputs/azure-functions/requirements.txt` | App deployment |
| Static app artifact (preferred) | `outputs/static-web-app/` | Static Web App deployment |
| Static app HTML fallback | `outputs/azure-functions/app.html` | Static Web App deployment |

If required IaC or Functions files are missing, **stop and report** which file is missing and which migration phase produces it — do not attempt partial deployment.

For Static Web App artifacts:
- Prefer `outputs/static-web-app/` when present.
- If absent, use `outputs/azure-functions/app.html` and convert it to `index.html` in a temporary deployment folder.
- If both are absent, stop and report the missing frontend artifact.

Also run a Bicep what-if to preview changes before deploying:

```bash
az deployment group what-if \
  --resource-group <resource-group> \
  --template-file outputs/bicep-templates/main.bicep \
  --parameters outputs/bicep-templates/parameters/<env>.bicepparam
```

Show the what-if output to the user and ask for confirmation before proceeding if any **destructive changes** (deletes or modifications to existing resources) are detected.

---

## Step 4 — Deploy Bicep IaC

Deploy the infrastructure first. Use the Azure CLI if authenticated; otherwise use the Azure MCP server deployment tools.

```bash
az deployment group create \
  --name "migration-deploy-<env>-$(date +%Y%m%d%H%M%S)" \
  --resource-group <resource-group> \
  --template-file outputs/bicep-templates/main.bicep \
  --parameters outputs/bicep-templates/parameters/<env>.bicepparam \
  --verbose
```

**On success:** Record the deployment name and outputs (e.g., Function App hostname, Storage Account name, Key Vault URI, Static Web App hostname/name) — these are needed for Steps 5 and 6.

**On failure:** Print the full error from `az deployment operation group list`, identify the failing resource, and ask the user how to proceed. Do not attempt app code deployment if IaC failed.

---

## Step 5 — Deploy Azure Functions

After IaC succeeds, deploy the application code.

First, confirm the Function App name from the Bicep deployment outputs or ask the user.

### 5a — Install Python Dependencies

```bash
pip install -r outputs/azure-functions/requirements.txt \
  --target outputs/azure-functions/.python_packages/lib/site-packages
```

If `pip` is not on PATH, try `python -m pip` or `python3 -m pip`. If all fail, check whether Python is installed and on PATH before continuing.

### 5b — Strategy 1: func CLI (preferred)

Check if the Azure Functions Core Tools are installed:

```bash
func --version
```

If available, publish directly:

```bash
cd outputs/azure-functions
func azure functionapp publish <function-app-name> --python
```

If `func` is not installed, proceed to Strategy 2.

### 5c — Strategy 2: Zip deploy via Azure CLI

Create the deployment zip. Use `zip` if available; fall back to Python's built-in `zipfile` module:

```bash
# Option A — zip CLI
cd outputs/azure-functions
zip -r ../functions-deploy.zip . --exclude "*.pyc" --exclude "__pycache__/*"

# Option B — Python fallback if zip is not on PATH
python3 -c "
import zipfile, os, pathlib
src = pathlib.Path('outputs/azure-functions')
with zipfile.ZipFile('outputs/functions-deploy.zip', 'w', zipfile.ZIP_DEFLATED) as z:
    for f in src.rglob('*'):
        if f.is_file() and '__pycache__' not in str(f) and not str(f).endswith('.pyc'):
            z.write(f, f.relative_to(src))
"
```

Before uploading, temporarily open the Function App's linked storage account network rules to allow the current client IP (required when `publicNetworkAccess` is `Disabled` or network rules are restrictive):

```bash
# Get the storage account name from IaC outputs or ask the user
STORAGE_ACCOUNT=<storage-account-name>

# Detect the current outbound IP
CLIENT_IP=$(curl -s https://api.ipify.org)
echo "Adding $CLIENT_IP to storage network rules"

az storage account network-rule add \
  --resource-group <resource-group> \
  --account-name "$STORAGE_ACCOUNT" \
  --ip-address "$CLIENT_IP"

# Allow rules to propagate (30 s is usually sufficient)
sleep 30
```

Now attempt the zip deploy:

```bash
az functionapp deployment source config-zip \
  --resource-group <resource-group> \
  --name <function-app-name> \
  --src outputs/functions-deploy.zip
```

If this returns an "unsupported path" error, try the newer deploy API:

```bash
az functionapp deploy \
  --resource-group <resource-group> \
  --name <function-app-name> \
  --src-path outputs/functions-deploy.zip \
  --type zip
```

After the upload attempt (success **or** failure), always remove the temporary IP rule:

```bash
az storage account network-rule remove \
  --resource-group <resource-group> \
  --account-name "$STORAGE_ACCOUNT" \
  --ip-address "$CLIENT_IP"
echo "Removed $CLIENT_IP from storage network rules"
```

If both zip-deploy commands return errors (`unsupported path`, `API isn't available`, or network errors), proceed to Strategy 3.

### 5d — Strategy 3: Remote Package URL (WEBSITE_RUN_FROM_PACKAGE)

When both `func` CLI and zip-deploy are unavailable or blocked, deploy by uploading the zip to Blob Storage and pointing the Function App to it via a SAS URL.

```bash
STORAGE_ACCOUNT=<storage-account-name>
CONTAINER=deployments

# Ensure the container exists
az storage container create \
  --name "$CONTAINER" \
  --account-name "$STORAGE_ACCOUNT" \
  --auth-mode login 2>/dev/null || true

# Add client IP to storage network rules temporarily
CLIENT_IP=$(curl -s https://api.ipify.org)
az storage account network-rule add \
  --resource-group <resource-group> \
  --account-name "$STORAGE_ACCOUNT" \
  --ip-address "$CLIENT_IP"
sleep 30

# Upload the zip package
BLOB_NAME="functions-deploy-$(date +%Y%m%d%H%M%S).zip"
az storage blob upload \
  --account-name "$STORAGE_ACCOUNT" \
  --container-name "$CONTAINER" \
  --name "$BLOB_NAME" \
  --file outputs/functions-deploy.zip \
  --auth-mode login

# Generate a SAS URL valid for 2 hours
EXPIRY=$(date -u -d '+2 hours' '+%Y-%m-%dT%H:%MZ' 2>/dev/null \
  || python3 -c "from datetime import datetime, timedelta, timezone; print((datetime.now(timezone.utc)+timedelta(hours=2)).strftime('%Y-%m-%dT%H:%MZ'))")

SAS_TOKEN=$(az storage blob generate-sas \
  --account-name "$STORAGE_ACCOUNT" \
  --container-name "$CONTAINER" \
  --name "$BLOB_NAME" \
  --permissions r \
  --expiry "$EXPIRY" \
  --https-only \
  --auth-mode login \
  --as-user \
  --output tsv)

SAS_URL="https://${STORAGE_ACCOUNT}.blob.core.windows.net/${CONTAINER}/${BLOB_NAME}?${SAS_TOKEN}"

# Remove client IP rule after upload
az storage account network-rule remove \
  --resource-group <resource-group> \
  --account-name "$STORAGE_ACCOUNT" \
  --ip-address "$CLIENT_IP"
echo "Removed $CLIENT_IP from storage network rules"

# Point the Function App at the remote package
az functionapp config appsettings set \
  --resource-group <resource-group> \
  --name <function-app-name> \
  --settings "WEBSITE_RUN_FROM_PACKAGE=${SAS_URL}"

# Restart the Function App to pick up the new package
az functionapp restart \
  --resource-group <resource-group> \
  --name <function-app-name>

echo "Waiting 30 s for cold start…"
sleep 30
```

Verify the Function App started successfully after the restart:

```bash
FUNC_HOST=$(az functionapp show \
  --resource-group <resource-group> \
  --name <function-app-name> \
  --query defaultHostName -o tsv)

STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://${FUNC_HOST}/api/health" 2>/dev/null || echo "000")
echo "Health check after package deploy: $STATUS"
```

Expect HTTP 200 or 401. Any 5xx or `000` means the package failed to load — print the Function App log stream for diagnostics:

```bash
az webapp log tail \
  --resource-group <resource-group> \
  --name <function-app-name>
```

**On success:** Retrieve the deployed function URLs and display them.
**On failure:** Print the deployment log from Strategy 3 and ask the user to resolve before retrying. Do not proceed to Step 6 if Functions deployment has not succeeded.

---

## Step 6 — Deploy Static Web App Content

After Functions deployment succeeds, deploy static frontend content directly to Static Web Apps
without using GitHub Actions.

Resolve the Static Web App target:
1. Use the user-provided Static Web App name if supplied.
2. Else derive it from IaC outputs.
3. Else ask the user for it and stop.

Prepare deployment directory:
- If `outputs/static-web-app/` exists, deploy that directory.
- Else create a temporary directory and copy `outputs/azure-functions/app.html` to `index.html`.

Get a runtime deployment token:

```bash
SWA_TOKEN=$(az staticwebapp secrets list \
  --name <static-web-app-name> \
  --resource-group <resource-group> \
  --query "properties.apiKey" \
  --output tsv)
```

Deploy using available tooling (manual, no pipeline):

**Check if `swa` CLI is installed:**

```bash
swa --version
```

If `swa` is not found, install it now before continuing:

```bash
npm install -g @azure/static-web-apps-cli
# Verify the install
swa --version
```

If `npm` is not available, try:

```bash
# With npx (no install required)
npx @azure/static-web-apps-cli deploy <static-app-dir> \
  --deployment-token "$SWA_TOKEN" \
  --env production
```

If `npm`/`npx` are both absent, skip to the Azure CLI fallback below.

```bash
# Preferred: Static Web Apps CLI
swa deploy <static-app-dir> \
  --deployment-token "$SWA_TOKEN" \
  --env production
```

If `swa` CLI is unavailable or the above command fails, try the Azure CLI upload command (supported in `azure-cli >= 2.56.0`):

```bash
# Check installed CLI version first
az version

az staticwebapp upload \
  --name <static-web-app-name> \
  --resource-group <resource-group> \
  --source <static-app-dir>
```

After deployment, verify the site is reachable:

```bash
SWA_HOST=$(az staticwebapp show \
  --resource-group <resource-group> \
  --name <static-web-app-name> \
  --query defaultHostname \
  --output tsv)

curl -I "https://${SWA_HOST}"
```

**On success:** Record Static Web App hostname and HTTP status.
**On failure:** Record the exact failing command/output and stop.

---

## Step 7 — Post-Deployment Summary

After IaC, Functions, and Static Web App deployments are complete, write `outputs/deployment-log.md` with:

```markdown
# Deployment Log

**Environment:** <env>
**Deployed At:** <timestamp>
**Subscription:** <subscription-id>
**Resource Group:** <resource-group>

## IaC Deployment
- **Deployment Name:** <name>
- **Status:** ✅ Succeeded / ❌ Failed
- **Key Outputs:**
  - Function App: <hostname>
  - Storage Account: <name>
  - Key Vault: <uri>

## Azure Functions Deployment
- **Function App:** <name>
- **Status:** ✅ Succeeded / ❌ Failed
- **Function URLs:**
  - <function-name>: <url>

## Static Web App Deployment
- **Static Web App:** <name>
- **Status:** ✅ Succeeded / ❌ Failed
- **URL:** https://<default-hostname>
- **Smoke Test:** HTTP <status-code>
```

Then print the summary to the chat and suggest running the `deployment-validation` agent to verify the deployment is correct.

---

## Constraints

- **NEVER** deploy to an environment not confirmed by the user
- **NEVER** deploy app code before IaC — infrastructure must exist first
- **NEVER** skip Static Web App deployment when a frontend artifact exists
- **NEVER** modify files in `source-app/`, `outputs/bicep-templates/`, or `outputs/azure-functions/`
- **NEVER** trigger GitHub Actions workflows as a substitute for manual deployment in this agent
- **ALWAYS** run what-if before deploying and surface destructive changes for user confirmation
- **ALWAYS** stop and report on failure — do not skip or ignore errors
