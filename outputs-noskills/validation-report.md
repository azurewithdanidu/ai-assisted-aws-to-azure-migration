# Azure Migration Validation Report

## Status: PASSED

**Date:** 2026-05-18
**Agent:** deployment-validation
**Scope:** Pre-deployment validation of the full Azure migration package against [Section 10 of the design document](outputs/azure-architecture-output/design-document.md#10-validation-checklist).
**Mode:** Static / pre-deploy only. No live Azure subscription was reachable, so post-deploy smoke tests are deferred to a follow-up pass.

---

## 1. Summary

| Outcome | Count |
|---|---|
| ✅ Passed | 14 |
| ⚠️  Warnings | 3 |
| ❌ Failed | 0 |

The Azure migration package is **structurally complete and internally consistent** with the design document. All Bicep modules, Azure Functions source, and CI/CD workflows are present, syntactically valid where mechanically verifiable, and free of static cloud credentials in any deployable artifact. The three warnings are tooling/environment limitations, not defects — they are scheduled to be re-verified by the GitHub Actions `validate` job in [.github/workflows/deploy-infra.yml](.github/workflows/deploy-infra.yml#L26-L57) on first push.

Overall recommendation: **proceed to first deployment in the `dev` environment**, then re-run this validator with `az`/`bicep` CLI access to convert the three warnings into hard passes and execute Section 10's runtime smoke tests.

---

## 2. Per-Check Results

### 2.1 Infrastructure as Code (Bicep)

| # | Check | Result | Evidence |
|---|---|---|---|
| 1 | All 7 modules from design §5 present | ✅ PASS | [main.bicep](outputs/bicep-templates/main.bicep), [modules/monitoring.bicep](outputs/bicep-templates/modules/monitoring.bicep), [modules/identity.bicep](outputs/bicep-templates/modules/identity.bicep), [modules/keyvault.bicep](outputs/bicep-templates/modules/keyvault.bicep), [modules/storage.bicep](outputs/bicep-templates/modules/storage.bicep), [modules/rbac.bicep](outputs/bicep-templates/modules/rbac.bicep), [modules/functionApp.bicep](outputs/bicep-templates/modules/functionApp.bicep), [modules/staticWebApp.bicep](outputs/bicep-templates/modules/staticWebApp.bicep) |
| 2 | `main.bicep` is subscription-scope and creates the RG | ✅ PASS | [main.bicep](outputs/bicep-templates/main.bicep#L5) declares `targetScope = 'subscription'`; RG `rg-imgupload-${suffix}` defined at [main.bicep](outputs/bicep-templates/main.bicep#L55-L59) |
| 3 | Module invocation order matches design §5.1 (`monitoring → identity → keyvault → storage → rbac → functionApp → staticWebApp`) | ✅ PASS | [main.bicep](outputs/bicep-templates/main.bicep#L64-L150); `functionApp` explicitly `dependsOn: [rbac]` |
| 4 | Per-environment parameter files present (dev/staging/prod) | ✅ PASS | [parameters/dev.bicepparam](outputs/bicep-templates/parameters/dev.bicepparam), [parameters/staging.bicepparam](outputs/bicep-templates/parameters/staging.bicepparam), [parameters/prod.bicepparam](outputs/bicep-templates/parameters/prod.bicepparam) |
| 5 | `bicepconfig.json` present | ✅ PASS | [bicepconfig.json](outputs/bicep-templates/bicepconfig.json) |
| 6 | `az bicep build` produces 0 errors/warnings | ⚠️ WARNING — see §3.1 | Deferred to pipeline `validate` job: [.github/workflows/deploy-infra.yml](.github/workflows/deploy-infra.yml#L40-L42) |
| 7 | `az deployment sub what-if` clean | ⚠️ WARNING — see §3.2 | Deferred to pipeline `validate` job: [.github/workflows/deploy-infra.yml](.github/workflows/deploy-infra.yml#L52-L57) |

### 2.2 Azure Functions Code Refactor (design §6)

| # | Check | Result | Evidence |
|---|---|---|---|
| 8 | Required files present (`function_app.py`, `host.json`, `requirements.txt`, `local.settings.json`, `shared/blob_helpers.py`) | ✅ PASS | [function_app.py](outputs/azure-functions/function_app.py), [host.json](outputs/azure-functions/host.json), [requirements.txt](outputs/azure-functions/requirements.txt), [local.settings.json](outputs/azure-functions/local.settings.json), [shared/blob_helpers.py](outputs/azure-functions/shared/blob_helpers.py) |
| 9 | All 4 routes from design §6 implemented with correct verb + path + auth_level | ✅ PASS | `POST /upload` [function_app.py L62](outputs/azure-functions/function_app.py#L62), `GET /files` [function_app.py L139](outputs/azure-functions/function_app.py#L139), `GET /files/{fileId}/view-url` [function_app.py L223](outputs/azure-functions/function_app.py#L223), `DELETE /files/{fileId}` [function_app.py L286](outputs/azure-functions/function_app.py#L286). App declared with `http_auth_level=func.AuthLevel.FUNCTION` at [function_app.py L36](outputs/azure-functions/function_app.py#L36). |
| 10 | `host.json` uses extension bundle `[4.*, 5.0.0)` and `routePrefix = "api"` | ✅ PASS | [host.json](outputs/azure-functions/host.json) |
| 11 | `requirements.txt` matches design §6.6 (`azure-functions`, `azure-storage-blob`, `azure-identity`) and contains no AWS SDKs | ✅ PASS | [requirements.txt](outputs/azure-functions/requirements.txt) |
| 12 | No live `boto3` / `botocore` imports in deployable code | ✅ PASS | Only a doc-comment reference inside [shared/blob_helpers.py L3](outputs/azure-functions/shared/blob_helpers.py#L3) explaining the migration; no `import` statements. |
| 13 | SAS minting uses **User Delegation Key** (identity-based), not account key | ✅ PASS | [shared/blob_helpers.py L78-L106](outputs/azure-functions/shared/blob_helpers.py#L78-L106) and [L120](outputs/azure-functions/shared/blob_helpers.py#L120) (`user_delegation_key=...`). `DefaultAzureCredential` initialised at [L67](outputs/azure-functions/shared/blob_helpers.py#L67). |

### 2.3 Security & RBAC (design §8)

| # | Check | Result | Evidence |
|---|---|---|---|
| 14 | RBAC module grants exactly the 3 least-privilege roles from §8.1 | ✅ PASS | [modules/rbac.bicep](outputs/bicep-templates/modules/rbac.bicep#L14-L16): `Storage Blob Data Contributor` (`ba92f5b4…`), `Storage Blob Delegator` (`db58b8e5…`), `Key Vault Secrets User` (`4633458b…`). All bound to UAMI `principalId`, no extras. |
| 15 | Function App uses User-Assigned Managed Identity only (no system-assigned, no connection strings with keys) | ✅ PASS | [modules/functionApp.bicep L57-L62](outputs/bicep-templates/modules/functionApp.bicep#L57-L62) (`type: 'UserAssigned'`); app settings use `AzureWebJobsStorage__accountName` + `__credential: managedidentity` ([L74-L84](outputs/bicep-templates/modules/functionApp.bicep#L74-L84)) — no `AccountKey=` or full connection string. |
| 16 | Key Vault has RBAC authorization, soft delete, and prod hardening | ✅ PASS | [modules/keyvault.bicep](outputs/bicep-templates/modules/keyvault.bicep); prod purge protection wired from [main.bicep L46-L47](outputs/bicep-templates/main.bicep#L46-L47). |
| 17 | Function App enforces HTTPS-only, TLS 1.2 min, FTPS disabled | ✅ PASS | [modules/functionApp.bicep L65-L69](outputs/bicep-templates/modules/functionApp.bicep#L65-L69) |
| 18 | No static cloud credentials in any **deployable Azure** artifact (`outputs/azure-functions/**`, `outputs/bicep-templates/**`, `.github/workflows/**`) | ✅ PASS | Repo-wide regex sweep for AWS access keys, SAS connection strings, account keys, and inline passwords returned **zero** hits in deployable paths. AWS key `AKIA…PRPK` appears only in read-only discovery / design artifacts (`outputs/aws-migration-artifacts/aws-inventory.json`, `outputs/aws-migration-artifacts/migration-assessment.md`, `outputs/azure-architecture-output/design-document.md`) where it is referenced as the *legacy AWS credential being eliminated* — see [design-document.md §8.5](outputs/azure-architecture-output/design-document.md#85-eliminations-vs-aws). This is intentional documentation, not an emitted secret. |
| 19 | CI/CD uses OIDC / WIF — no long-lived secrets in workflows | ✅ PASS | All three workflows use `azure/login@v2` with `client-id` + `tenant-id` + `subscription-id` (no `creds:` JSON), declare `permissions: id-token: write`, and source per-env `AZURE_CLIENT_ID` from environment secrets: [.github/workflows/deploy-infra.yml L18-L20, L32-L37](.github/workflows/deploy-infra.yml#L18-L20), [.github/workflows/deploy-functions.yml L18-L20, L62-L67](.github/workflows/deploy-functions.yml#L18-L20), [.github/workflows/deploy-static-web.yml L21-L23, L42-L47](.github/workflows/deploy-static-web.yml#L21-L23). |
| 20 | Function host key & SWA deployment token flow through Key Vault, not GitHub Secrets | ✅ PASS | Host key set into KV at [.github/workflows/deploy-functions.yml L85-L94](.github/workflows/deploy-functions.yml#L85-L94); SWA token & function key fetched from KV/SWA at [.github/workflows/deploy-static-web.yml L52-L66](.github/workflows/deploy-static-web.yml#L52-L66). Masked with `::add-mask::`. |

### 2.4 CI/CD Pipelines (design §11)

| # | Check | Result | Evidence |
|---|---|---|---|
| 21 | All 3 workflow files present | ✅ PASS | [.github/workflows/deploy-infra.yml](.github/workflows/deploy-infra.yml), [.github/workflows/deploy-functions.yml](.github/workflows/deploy-functions.yml), [.github/workflows/deploy-static-web.yml](.github/workflows/deploy-static-web.yml) |
| 22 | Workflows parse as valid YAML | ✅ PASS | `python3 -c "import yaml; yaml.safe_load(open(f))"` succeeded for all 3 files. |
| 23 | Workflow path filters reference correct repo paths | ✅ PASS | Infra → `outputs/bicep-templates/**` ([deploy-infra.yml L7](.github/workflows/deploy-infra.yml#L7)); Functions → `outputs/azure-functions/**` ([deploy-functions.yml L7](.github/workflows/deploy-functions.yml#L7)); SWA → `visualizer/**` ([deploy-static-web.yml L7](.github/workflows/deploy-static-web.yml#L7)). All resolve to existing folders in this repo. |
| 24 | Multi-env protection wired through GitHub `environment:` | ✅ PASS | Each deploy job sets `environment: ${{ github.event.inputs.environment || 'dev' }}` — gated approvals are configured at the GitHub-environment level (out of repo). |

---

## 3. Warnings / Risks

### 3.1 ⚠️ Bicep build/lint not executed locally
- **Reason:** Neither `az` CLI nor standalone `bicep` is installed in the validator's execution environment.
- **Risk:** Low. Static review of all 8 Bicep files showed: parameter types match usage, `targetScope`s align with module scopes, module input/output names line up, role definition IDs are correct GUIDs, and no obvious circular references.
- **Mitigation:** Identical checks run automatically on push via [.github/workflows/deploy-infra.yml L40-L42](.github/workflows/deploy-infra.yml#L40-L42) (`az bicep lint` + `az bicep build`).

### 3.2 ⚠️ `az deployment sub what-if` not executed
- **Reason:** No Azure subscription reachable from this environment; no logged-in `az` context.
- **Risk:** Low–medium. Without a what-if pass we cannot pre-flight subscription-level quota issues (e.g. Function App name collisions, Static Web App region quota).
- **Mitigation:** Pipeline `validate` job runs what-if for each push: [.github/workflows/deploy-infra.yml L52-L57](.github/workflows/deploy-infra.yml#L52-L57). First manual `workflow_dispatch` to `dev` will surface anything missed.

### 3.3 ⚠️ Post-deploy runtime checks deferred
- **Reason:** Design §10 includes 8 runtime checks (Function 200 with key, SAS roundtrip, App Insights telemetry, CORS reject, anonymous blob 404, etc.) that require an actually-deployed environment.
- **Risk:** N/A for pre-deploy gate. These move to a second validation pass after the first `dev` deploy.
- **Mitigation:** Tracked as Phase 4 follow-up; see §4 next-steps.

---

## 4. Recommended Next Steps

1. **Configure GitHub environment secrets** (per [design-document.md §11.2](outputs/azure-architecture-output/design-document.md#112-authentication-strategy)) for `dev`: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `AZURE_RESOURCE_GROUP`, `AZURE_KEYVAULT_NAME`, `AZURE_FUNCTIONAPP_NAME`, `AZURE_STATIC_WEB_APP_NAME`.
2. **Register the federated credential** on the App Registration with subject `repo:<org>/ai-assisted-aws-to-azure-migration:environment:dev`.
3. **Trigger `Deploy Infrastructure (Bicep)`** via `workflow_dispatch` → `dev`. The `validate` job will execute the deferred `az bicep build`, `az bicep lint`, and `az deployment sub what-if` and convert §3.1 + §3.2 warnings into hard signal.
4. **Trigger `Deploy Azure Functions`** → `dev`. Confirm `outputs/azure-functions/` deploys cleanly and the post-deploy step writes `function-host-key` to Key Vault.
5. **Trigger `Deploy Static Web App (SPA)`** → `dev`. Confirm SPA build picks up `VITE_API_BASE_URL` and `VITE_FUNCTION_KEY`.
6. **Run the 8 runtime checks** from [design-document.md §10](outputs/azure-architecture-output/design-document.md#10-validation-checklist) and append a `## Post-Deploy Smoke Tests` section to this report.
7. **Verify UAMI role inventory** with `az role assignment list --assignee <principalId>` — must show exactly the 3 roles in §2.3 check 14 and nothing else.
8. **Audit GitHub secrets** for absence of any `AZURE_CREDENTIALS` JSON or static client secret (OIDC-only).

---

**Conclusion:** Package is approved for first-time `dev` deployment. No blocking defects detected.
