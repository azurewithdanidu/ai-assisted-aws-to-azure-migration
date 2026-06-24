---
name: what-if-validation
description: Run pre-deployment validation (Bicep syntax, policy compliance, quota, what-if) and security checks, then write a full validation report
---

# What-If Validation Skill

## Purpose

Catch dangerous infrastructure changes before they are deployed and verify all pre-deployment conditions are met. Covers Bicep syntax, what-if blocking conditions, policy compliance, quota, security, performance, and cost validation.

## When to Use

Before any Bicep deployment and after deployment to validate the deployed state. Always run what-if first — never skip it even for dev.

---

## Pre-Deployment Checklist

### 1. Bicep Syntax Validation

```bash
# Bicep syntax check — must exit 0
az bicep build --file outputs/bicep-templates/main.bicep

# Full ARM validation
az deployment group validate \
  --resource-group $RESOURCE_GROUP \
  --template-file outputs/bicep-templates/main.bicep \
  --parameters outputs/bicep-templates/parameters/prod.bicepparam
# Expected: validationState: "Valid"
```

**Gate:** Deployment MUST NOT proceed if `az bicep build` exits non-zero or if `validate` returns errors.

### 2. What-If Dry Run

For each environment (dev, staging, prod), run:

```bash
az deployment group what-if \
  --resource-group rg-<env>-migration \
  --template-file outputs/bicep-templates/main.bicep \
  --parameters outputs/bicep-templates/parameters/<env>.bicepparam \
  --mode Incremental \
  --output json > /tmp/whatif-<env>.json
```

Parse the output for **blocking conditions** — stop and alert the user if any are found:
- Any operation with `changeType: "Delete"` on a data resource (Storage Account, Key Vault, Database, Service Bus)
- Any change to a role assignment at subscription scope
- Any NSG security rule with `access: "Deny"` being removed
- Any `changeType: "Modify"` on `publicNetworkAccess` from `Disabled` to `Enabled`

Parse for **warning conditions** — log and continue:
- New resources being created (expected)
- Tag changes (expected)
- SKU upgrades (log for cost awareness)

### 3. Policy Compliance Check

```bash
az policy state summarize --resource-group $RESOURCE_GROUP
# Expected: no resources in "Non-compliant" state for Deny policies
```

Pre-deploy compliance checklist:
- [ ] All resources will have required tags: `Environment`, `Application`, `Owner`, `CostCenter`
- [ ] No public IPs on services that should be private
- [ ] Private endpoints configured for PaaS services requiring network isolation
- [ ] Encryption at rest enabled for all data services
- [ ] Managed Identity configured for all compute resources
- [ ] TLS 1.2+ enforced on all endpoints

### 4. Quota / Service Limit Check

```bash
az provider show --namespace Microsoft.Web \
  --query "resourceTypes[?resourceType=='sites']"
az provider show --namespace Microsoft.Storage \
  --query "resourceTypes[?resourceType=='storageAccounts']"
```

Quota checklist:
- [ ] Storage account count within subscription limit (250 per region)
- [ ] Function App count within region limits
- [ ] Container App environment quota available (if using Container Apps)
- [ ] Database SKU available in target region

---

## Post-Deployment Checklist

### 1. Resource Deployment Status

```bash
# Verify all expected resources are in Succeeded state
az resource list --resource-group $RESOURCE_GROUP \
  --query "[?provisioningState!='Succeeded'].[name,type,provisioningState]" \
  --output table
# Expected: empty table
```

- [ ] All resources: `provisioningState == Succeeded`
- [ ] No resources in Failed, Creating, or Deleting state
- [ ] Resource count matches expected count from design document

### 2. Connectivity Verification

```bash
# Function App reachable (200 or 401 acceptable; 5xx = fail)
curl -sf -o /dev/null -w "%{http_code}" "https://<functionapp>.azurewebsites.net/api/health"

# Static Web App reachable
curl -sf -o /dev/null "https://<swa>.azurestaticapps.net/index.html"

# Database host resolvable (from within VNet)
nslookup <postgres>.postgres.database.azure.com
```

- [ ] All Function App HTTP endpoints return 200 or 401 (not 5xx)
- [ ] Static Web App serves index.html (HTTP 200)
- [ ] Database host resolves and is reachable on the correct port
- [ ] Blob Storage containers accessible via Function App Managed Identity
- [ ] Key Vault secrets accessible from Function App

### 3. Managed Identity Verification

```bash
FUNC_PRINCIPAL_ID=$(az webapp identity show \
  --resource-group $RESOURCE_GROUP \
  --name $FUNCTION_APP_NAME \
  --query principalId -o tsv)

az role assignment list --assignee $FUNC_PRINCIPAL_ID --output table
```

- [ ] System-assigned Managed Identity enabled on Function App
- [ ] `Storage Blob Data Contributor` role assigned on storage account
- [ ] `Key Vault Secrets User` role assigned on Key Vault
- [ ] No access key credentials in app settings (all auth via Managed Identity)

### 4. Key Vault Access Verification

```bash
az keyvault secret list --vault-name $KEY_VAULT_NAME --query "[].name" -o tsv
```

- [ ] All required secrets exist in Key Vault
- [ ] Key Vault references resolving correctly in Function App settings
- [ ] Soft delete and purge protection enabled on Key Vault
- [ ] No secrets visible as plain-text app settings

---

## Security Validation

### Network Security

```bash
az network nsg rule list \
  --resource-group $RESOURCE_GROUP \
  --nsg-name $NSG_NAME \
  --output table
```

- [ ] Inbound rules: only port 443 (HTTPS) allowed from internet on app subnets
- [ ] All PaaS services accessed via private endpoint where required
- [ ] No `0.0.0.0/0` allow-all inbound rules on database subnets
- [ ] Storage account public access disabled (if using private endpoint)

### Identity & Access

- [ ] No credentials in source code, environment variables, or app settings
- [ ] No long-lived service principal secrets used (OIDC preferred)
- [ ] RBAC assignments scoped to resource group (not subscription) unless IaC requires it
- [ ] All identities use least-privilege roles (not `Owner` or `Contributor` where narrower roles work)

### Data Encryption

- [ ] Storage accounts: encryption at rest enabled (Azure-managed keys minimum)
- [ ] Database: encryption at rest enabled
- [ ] All HTTPS endpoints: TLS 1.2+ only (no TLS 1.0/1.1)
- [ ] Key Vault: soft delete (90 days) and purge protection enabled

### Compliance Tagging

- [ ] All resources tagged with: `Environment`, `Application`, `Owner`, `CostCenter`
- [ ] Audit logs enabled: Azure Activity Log, Diagnostic settings on Key Vault and Storage
- [ ] No diagnostic settings sending logs to public endpoints

---

## Performance Validation

### Baseline Comparison

| Metric | Acceptance Threshold |
|---|---|
| P50 response time | ≤ 1.5× AWS P50 |
| P95 response time | ≤ 2.0× AWS P95 |
| P99 response time | ≤ 3.0× AWS P99 |
| Error rate | ≤ 0.5% (same as AWS baseline or better) |
| Throughput (RPS) | ≥ 80% of AWS baseline |

```bash
# Quick load test (install hey: go install github.com/rakyll/hey@latest)
hey -n 1000 -c 50 -m GET "https://<functionapp>.azurewebsites.net/api/list"
```

Performance checklist:
- [ ] P95 response time ≤ design document SLA target
- [ ] No memory leaks (Function App memory trending flat)
- [ ] Cold start time acceptable for plan (Consumption: ≤ 3s, Premium: ≤ 500ms)

---

## Cost Validation

```bash
az consumption usage list \
  --billing-period-name $(az billing period list --query "[0].name" -o tsv) \
  --query "[?resourceGroup=='$RESOURCE_GROUP'].[instanceName,pretaxCost,currency]" \
  --output table
```

- [ ] Actual cost ≤ projected cost + 20% (within first month)
- [ ] No unexpected resource types incurring charges
- [ ] Consumption-plan Functions not charged when idle
- [ ] Storage lifecycle policies applied (Hot → Cool after 30 days)

---

## Validation Report Template

Write `outputs/validation-report.md` using this structure:

```markdown
# Azure Migration Validation Report

**Date:** YYYY-MM-DD
**Migration:** AWS → Azure
**Validated By:** deployment-validation agent
**Status:** PASS | FAIL | PARTIAL

---

## Executive Summary

| Category | Status | Notes |
|---|---|---|
| Pre-Deployment Validation | ✅ PASS / ❌ FAIL | |
| Post-Deployment Validation | ✅ PASS / ❌ FAIL | |
| Security Validation | ✅ PASS / ❌ FAIL | |
| Performance Validation | ✅ PASS / ❌ FAIL | |
| Cost Validation | ✅ PASS / ❌ FAIL | |
| **Overall** | **✅ PASS / ❌ FAIL** | |

---

## Pre-Deployment Validation

### Template Validation
- [ ] `az bicep build` — PASS / FAIL
- [ ] `az deployment group validate` — PASS / FAIL
- [ ] `az deployment group what-if` — PASS / BLOCKED

### What-If Change Table
| Environment | Change Type | Resource | Verdict |
|---|---|---|---|
| dev | Create | rg-dev-storage | OK |
| prod | Delete | rg-prod-keyvault | ❌ BLOCKED |

### Policy Compliance
- [ ] Required tags present — PASS / FAIL
- [ ] No public IPs on private services — PASS / FAIL

### Quota Checks
- [ ] Storage account quota sufficient — PASS / FAIL
- [ ] Function App quota sufficient — PASS / FAIL

---

## Post-Deployment Validation

### Resource Status
| Resource | Type | Status |
|---|---|---|
| functionApp | Microsoft.Web/sites | ✅ Succeeded |
| storageAccount | Microsoft.Storage/storageAccounts | ✅ Succeeded |
| keyVault | Microsoft.KeyVault/vaults | ✅ Succeeded |

### Connectivity
| Test | Result | Notes |
|---|---|---|
| Function App health endpoint | ✅ HTTP 200 | |
| SWA index.html | ✅ HTTP 200 | |
| Database connectivity | ✅ Reachable | |

### Smoke Tests
| Test | Result | Actual vs Expected |
|---|---|---|
| Upload file | ✅ PASS | HTTP 200, file in Blob |
| List files | ✅ PASS | File appears in list |
| View file | ✅ PASS | Correct content returned |
| Delete file | ✅ PASS | File removed |
| Error handling | ✅ PASS | 404 for missing resource |

---

## Security Validation

| Check | Result | Notes |
|---|---|---|
| No credentials in app settings | ✅ PASS | |
| Managed Identity enabled | ✅ PASS | |
| RBAC least privilege | ✅ PASS | |
| TLS 1.2+ enforced | ✅ PASS | |
| Key Vault soft delete | ✅ PASS | |
| Private endpoints configured | ✅ PASS | |

---

## Performance Validation

| Metric | AWS Baseline | Azure Result | Within Threshold |
|---|---|---|---|
| P50 response time | XXX ms | XXX ms | ✅ / ❌ |
| P95 response time | XXX ms | XXX ms | ✅ / ❌ |
| Error rate | X.X% | X.X% | ✅ / ❌ |
| Throughput (RPS) | XXX | XXX | ✅ / ❌ |

---

## Cost Validation

| Service | Projected (Monthly) | Actual (First Week × 4.3) | Within Budget |
|---|---|---|---|
| Azure Functions | $XXX | $XXX | ✅ / ❌ |
| Storage | $XXX | $XXX | ✅ / ❌ |
| Database | $XXX | $XXX | ✅ / ❌ |
| **Total** | **$XXX** | **$XXX** | **✅ / ❌** |

---

## Issues Found

### Critical (Must Fix Before Go-Live)
1. [Issue description, impacted resource, remediation steps]

### High (Fix Within 1 Week)
1. [Issue description, impacted resource, remediation steps]

---

## Sign-Off
- [ ] Infrastructure team: approved
- [ ] Security team: approved
- [ ] Application team: tested and approved
```

---

## Rules

- **Never proceed past a blocking what-if condition** without explicit user confirmation.
- **Always run what-if for all three environments** before declaring validation complete.
- **Never run what-if without `--mode Incremental`** — Complete mode deletes resources not in the template.
- **Never mark a check `[x] PASS`** unless the underlying validation actually succeeded.
- **Always save what-if JSON output** to `/tmp/whatif-<env>.json` for inspection.
- **The detailed report goes to `outputs/validation-report.md`** — the task plan summary is separate.

## Output

- `outputs/deployment-validation/what-if-report.md` — what-if results per environment (PASS/BLOCKED)
- `outputs/validation-report.md` — full validation report using the template above

---

## Companion Scripts

| Script | Purpose |
|---|---|
| `scripts/run-what-if.ps1` | Full pre-deployment validation gate: syntax → ARM validate → what-if → policy → quota |

Run before every environment deployment:

```powershell
./.github/skills/agents/deployment-validation/scripts/run-what-if.ps1 \
    -ResourceGroup "rg-dev-migration" -Environment dev
```

The script blocks on destructive what-if changes (deletes of data resources, `publicNetworkAccess` re-enabled).  It writes `outputs/deployment-validation/what-if-<env>.json` and `what-if-report.md`.

---

## References

### Microsoft / Azure Documentation

| Topic | Link |
|---|---|
| Bicep what-if overview | https://learn.microsoft.com/en-us/azure/azure-resource-manager/bicep/deploy-what-if |
| `az deployment group what-if` CLI | https://learn.microsoft.com/en-us/cli/azure/deployment/group#az-deployment-group-what-if |
| `az deployment group validate` CLI | https://learn.microsoft.com/en-us/cli/azure/deployment/group#az-deployment-group-validate |
| `az bicep build` CLI | https://learn.microsoft.com/en-us/cli/azure/bicep#az-bicep-build |
| Azure Policy overview | https://learn.microsoft.com/en-us/azure/governance/policy/overview |
| `az policy state summarize` CLI | https://learn.microsoft.com/en-us/cli/azure/policy/state#az-policy-state-summarize |
| Azure subscription limits and quotas | https://learn.microsoft.com/en-us/azure/azure-resource-manager/management/azure-subscription-service-limits |
| Azure Monitor Activity Log | https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/activity-log |
| Azure Security Benchmark | https://learn.microsoft.com/en-us/security/benchmark/azure/introduction |
| Azure Advisor cost recommendations | https://learn.microsoft.com/en-us/azure/advisor/advisor-cost-recommendations |
| `az consumption usage list` CLI | https://learn.microsoft.com/en-us/cli/azure/consumption/usage#az-consumption-usage-list |
| ARM Incremental vs Complete mode | https://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/deployment-modes |

### Best Practices

- **Always use `--mode Incremental`** in what-if and deployment commands — Complete mode deletes any resource in the resource group that is not in the template, which can cause catastrophic data loss.
- **Block on `changeType: Delete` for data resources** — accidental deletion of storage accounts, Key Vaults, or databases is not easily recoverable even with soft-delete enabled.
- **What-if is not a guarantee:** ARM what-if output can differ from actual deployment results in edge cases (e.g., resource provider bugs, concurrent changes). Always review what-if output before approving.
- **Policy compliance must be checked pre-deployment:** Deploying a non-compliant resource in `Deny` policy mode causes a 403 error mid-deployment and leaves the stack in a partial state.
