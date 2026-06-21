---
name: smoke-testing
description: Verify a deployed Azure environment is functional — endpoint availability, managed identity, Key Vault access, and end-to-end data flow
---

# Smoke Testing Skill

## Purpose

Confirm a deployed environment works end-to-end by running targeted checks against the actual deployed resources, not just validating templates.

## When to Use

After a successful Bicep deployment, before marking Phase 4 complete.

## Process

1. **Get deployed resource names** from Bicep outputs:
   ```bash
   az deployment group show \
     --name <deployment-name> \
     --resource-group rg-<env>-migration \
     --query properties.outputs \
     --output json
   ```

2. **HTTP endpoint check** — expect 200 or 401 (auth required is OK; 5xx is a failure):
   ```bash
   HOST=$(az functionapp show \
     --name <functionapp-name> \
     --resource-group rg-<env>-migration \
     --query defaultHostName -o tsv)
   STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://${HOST}/api/health")
   echo "Health endpoint: $STATUS"
   [ "$STATUS" -eq 200 ] || [ "$STATUS" -eq 401 ] || exit 1
   ```

3. **Managed identity check** — must return a `principalId`:
   ```bash
   az functionapp identity show \
     --name <functionapp-name> \
     --resource-group rg-<env>-migration \
     --query principalId -o tsv
   ```

4. **Key Vault secret resolution check** — verify the app can read a secret:
   ```bash
   az keyvault secret show \
     --vault-name <kv-name> \
     --name TestSecret \
     --query value -o tsv
   ```

5. **End-to-end data flow check** — write a test blob and read it back:
   ```bash
   az storage blob upload \
     --account-name <storage-account> \
     --container-name uploads \
     --name smoke-test.txt \
     --data "smoke test" \
     --auth-mode login

   az storage blob show \
     --account-name <storage-account> \
     --container-name uploads \
     --name smoke-test.txt \
     --auth-mode login \
     --query name -o tsv
   ```

6. Write results to `outputs/deployment-validation/smoke-test-report.md`:
   ```markdown
   # Smoke Test Report — <env>
   ## Status: PASSED / FAILED

   | Check | Result | Details |
   |---|---|---|
   | HTTP health endpoint | PASS | HTTP 200 |
   | Managed identity | PASS | principalId: abc-123 |
   | Key Vault secret read | PASS | Secret resolved |
   | End-to-end blob write/read | PASS | smoke-test.txt created and read |
   ```

## Rules

- **Never mark smoke tests passed if any HTTP endpoint returns 5xx.**
- **Always test at least one end-to-end data flow** — writing and reading back from storage is the minimum acceptable test.
- **Always clean up test data** — delete `smoke-test.txt` after the test passes.
- **If any check fails**, write `## Status: FAILED` at the top of the report and include the error message.

## Output

- `outputs/deployment-validation/smoke-test-report.md` — contains `## Status: PASSED` or `## Status: FAILED`, plus a results table for each check
