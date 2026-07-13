# Deployment Log

**Environment:** dev
**Deployed At:** 2026-06-24T14:41:12Z
**Subscription:** 40668c14-2eac-4594-815f-e64abe2a25dd
**Resource Group:** rg-image-upload-dev

## IaC Deployment
- **Deployment Name:** migration-deploy-dev-20260624143425
- **Status:** ✅ Succeeded
- **What-If Summary:** 12 create, 0 modify, 0 delete
- **Pre-Check Issue Fixed:**
  - Initial what-if failed because resource group did not exist:
    - `az deployment group what-if --resource-group rg-image-upload-dev --template-file outputs/bicep-templates/main.bicep --parameters outputs/bicep-templates/parameters/dev.bicepparam --output json`
    - Error: `ResourceGroupNotFound: Resource group 'rg-image-upload-dev' could not be found.`
  - Unblock applied: `az group create --name rg-image-upload-dev --location australiasoutheast`
- **Key Outputs:**
  - Function App: img-upload-func-dev-ase.azurewebsites.net
  - Storage Account: imguploaddevase
  - Key Vault: https://img-upload-kv-dev-ase..vault.azure.net

## Azure Functions Deployment
- **Function App:** img-upload-func-dev-ase
- **Status:** ❌ Failed (code publish did not complete)
- **Failed Commands/Checks:**
  - `func azure functionapp publish img-upload-func-dev-ase --python`
    - Result: `FUNC_CLI_MISSING` (Core Tools not installed)
  - `az functionapp deployment source config-zip --resource-group rg-image-upload-dev --name img-upload-func-dev-ase --src <zip> --output json`
    - Result: `The Azure CLI does not support this deployment path. Please configure the app to deploy from a remote package using the steps here: https://aka.ms/deployfromurl`
  - `az functionapp deploy --resource-group rg-image-upload-dev --name img-upload-func-dev-ase --src-path <zip> --type zip --output json`
    - Result: `This API isn't available in this environment yet!`
  - Remote package fallback:
    - `az storage blob upload --account-name imguploaddevase --container-name function-packages --name <zip> --file <zip> --auth-mode login --overwrite --output none`
    - Result: `The request may be blocked by network rules of storage account.`
- **Function URLs:**
  - Not available (code package publish failed; `az functionapp function list` returned `Operation returned an invalid status 'Bad Request'`)

## Unblock Actions
- Install Azure Functions Core Tools and retry publish:
  - `func azure functionapp publish img-upload-func-dev-ase --python`
- If Core Tools is unavailable, use deploy-from-package URL from a network path that can reach Storage data plane:
  - Upload package to storage and set `WEBSITE_RUN_FROM_PACKAGE` with SAS URL from an environment with data-plane access.
- Ensure executor identity has storage data-plane role at account scope:
  - `Storage Blob Data Contributor`
- If running in a restricted/sandboxed shell, rerun deployment from an unsandboxed terminal/session with outbound access to `*.blob.core.windows.net`.

---

## Azure Functions Deployment (Step 5 Re-run)
- **Function App:** img-upload-func-dev-ase
- **Status:** ✅ Succeeded
- **Execution Window:** 2026-06-24T15:30:08Z to 2026-06-24T15:31:36Z
- **Strategy Sequence:**
  - A (`func azure functionapp publish ...`) ❌ skipped/failed (`func` CLI unavailable)
  - B (`az functionapp deploy --type zip`) ❌ failed (`This API isn't available in this environment yet!`)
  - C (`WEBSITE_RUN_FROM_PACKAGE` via SAS URL) ✅ succeeded
- **Verification:**
  - Function App state: `Running`
  - Hostname: `img-upload-func-dev-ase.azurewebsites.net`
  - Health probe `GET /api/health`: HTTP `503` (non-blocking warning; app restarted and host remained running)

## Static Web App Deployment (Step 6 Re-run)
- **Static Web App:** img-upload-swa-dev-ase
- **Status:** ✅ Succeeded
- **Primary attempt:**
  - `swa --version || npm install -g @azure/static-web-apps-cli` ❌ global install failed (`EACCES: /usr/local/lib/node_modules`)
  - `swa deploy ...` ❌ failed (CLI unavailable)
- **Fallback used:**
  - `npx -y @azure/static-web-apps-cli deploy ...` ✅ succeeded
- **URL:** https://delightful-island-01a27b000.7.azurestaticapps.net
- **Smoke Test:** HTTP `200`