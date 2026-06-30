## Status: FAILED

# Azure Migration Validation Report

- Date (UTC): 2026-06-24T15:49:52Z
- Migration: AWS (535002891143, ap-southeast-2) -> Azure
- Subscription: 40668c14-2eac-4594-815f-e64abe2a25dd
- Resource Group: rg-image-upload-dev
- Deployment: migration-deploy-dev-20260624143425

## 1. Pre-deployment checks

| Check | Result | Evidence |
|---|---|---|
| Bicep syntax (`az bicep build`) | PASS | Build succeeded for `outputs/bicep-templates/main.bicep`. |
| ARM validate (`az deployment group validate`) | PASS | `provisioningState: Succeeded` for validation request. |
| What-if dry run (`az deployment group what-if`) | PASS (with warnings) | Summary: `2 to create, 9 to modify, 1 no change, 1 to ignore`; no delete operations shown in summary output. |

## 2. Post-deployment resource existence checks

| Check | Result | Evidence |
|---|---|---|
| Resource group exists in expected region | PASS | `rg-image-upload-dev` in `australiasoutheast`. |
| Deployment provisioning state | PASS | `Succeeded` for `migration-deploy-dev-20260624143425`. |
| Resources in non-succeeded states | PASS | `az resource list` non-succeeded query returned empty result. |
| Storage account shape | PASS | `imguploaddevase`: `StorageV2`, `Standard_LRS`, `Hot`, `allowBlobPublicAccess=false`, `minimumTlsVersion=TLS1_2`. |
| Blob container `images` exists and private | PASS | Management-plane container check returned `publicAccess: null` (private). |
| Blob versioning enabled | PASS | Blob service properties: `isVersioningEnabled=true`. |
| Function App runtime/plan | PASS | `img-upload-func-dev-ase` Running; plan `Y1` Dynamic Consumption; runtime `PYTHON|3.11`. |
| Managed identity enabled | PASS | System-assigned principal present (`principalId` returned). |
| App Insights linked to Log Analytics | PASS | App Insights `workspaceResourceId` points to LAW in same resource group. |
| Static Web App deployed | PASS | `img-upload-swa-dev-ase` exists; hostname `delightful-island-01a27b000.7.azurestaticapps.net`. |
| RBAC assignments created | PASS | Function MI has `Storage Blob Data Contributor` on storage and `Key Vault Secrets User` on Key Vault. |

## 3. API smoke tests (`/api/files`, `/api/upload`)

| Endpoint | Expected | Observed | Result |
|---|---|---|---|
| `GET /api/files` | 200/401/non-5xx | 503 | FAIL |
| `HEAD /api/upload` | 200/401/405/non-5xx | 503 | FAIL |
| `POST /api/upload` | 200/201/401/415/non-5xx | 503 | FAIL |

Overall smoke API status: FAIL (critical).

## 4. Static Web App HTTP 200 check

| Check | Result | Evidence |
|---|---|---|
| SWA root URL availability | PASS | `https://delightful-island-01a27b000.7.azurestaticapps.net` returned HTTP 200. |
| SWA `/index.html` availability | PASS | HTTP 200. |

## 5. Security compliance

| Control | Result | Evidence |
|---|---|---|
| Managed identity on Function App | PASS | System-assigned identity configured and principal ID present. |
| No shared keys in runtime config | PASS | `AzureWebJobsStorage__credential=managedidentity`; storage `allowSharedKeyAccess=false`; no `AccountKey=` patterns found in app settings filter results. |
| HTTPS/TLS settings | PASS | Function App `httpsOnly=true`, min TLS `1.2`; Storage min TLS `TLS1_2`. |
| Key Vault RBAC integration | PASS | Function MI has `Key Vault Secrets User`; Key Vault uses RBAC (`enableRbacAuthorization=true`). |
| Key Vault hardening (public access + purge protection) | FAIL | Key Vault has `publicNetworkAccess=Enabled` and `enablePurgeProtection=null` (not enabled). |
| Function unauthenticated access rejection | FAIL | EasyAuth `enabled=false`; app routes are anonymous; runtime endpoint probes currently return 503 (cannot enforce auth behavior in current state). |
| CORS restriction to SWA + localhost only | FAIL | Allowed origins are localhost and Azure Functions domains; SWA hostname is not present. |

## 6. Warnings and non-blocking findings

- Non-blocking (known): `/api/health` returned 503; this was treated as non-blocking per instruction, but both `/api/files` and `/api/upload` also returned 503 and are blocking.
- Non-blocking (known): Functions currently deployed via `WEBSITE_RUN_FROM_PACKAGE` SAS URL (Strategy C).
- Observability query gap: Log Analytics extension had to be installed during validation; AppRequests/AppExceptions queries returned empty sets at validation time.
- Key Vault secret listing with current operator identity returned RBAC `Forbidden`; runtime access was inferred via MI role assignment, but direct secret-read verification could not be completed from this identity.
- Frontend packaging note: SWA serves root successfully; however, CORS and auth configuration do not yet align with checklist security targets.

## Section 10 Checklist Rollup (critical items)

- Infrastructure: PASS with minor warnings.
- Security: FAIL due to auth and Key Vault hardening gaps.
- Functional: FAIL due to API smoke endpoints returning 503.
- Observability: PARTIAL (resources exist, telemetry queries empty at validation time).
- Frontend-specific: PARTIAL (SWA up; no AWS markers in deployed root HTML; auth/cors controls not complete).

## Final Decision

Critical checks failed. Migration validation result is FAILED until API availability and security hardening findings are remediated and re-tested.
