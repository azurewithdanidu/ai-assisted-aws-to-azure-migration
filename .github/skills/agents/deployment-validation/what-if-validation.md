---
name: what-if-validation
description: Run pre-deployment what-if checks against all three environments and block on dangerous changes before any real deployment
---

# What-If Validation Skill

## Purpose

Catch dangerous infrastructure changes before they are deployed by running `az deployment group what-if` and evaluating the output for blocking conditions.

## When to Use

Before any Bicep deployment — always run what-if first. Do not skip for dev environments.

## Process

1. For each environment (dev, staging, prod), run:
   ```bash
   az deployment group what-if \
     --resource-group rg-<env>-migration \
     --template-file outputs/bicep-templates/main.bicep \
     --parameters outputs/bicep-templates/parameters/<env>.bicepparam \
     --mode Incremental \
     --output json > /tmp/whatif-<env>.json
   ```

2. Parse the output for **blocking conditions** — stop and alert the user if any are found:
   - Any operation with `changeType: "Delete"` on a data resource (Storage Account, Key Vault, Database, Service Bus)
   - Any change to a role assignment at subscription scope
   - Any NSG security rule with `access: "Deny"` being removed
   - Any `changeType: "Modify"` on `publicNetworkAccess` from `Disabled` to `Enabled`

3. Parse for **warning conditions** — log and continue:
   - New resources being created (expected)
   - Tag changes (expected)
   - SKU upgrades (log for cost awareness)

4. Write findings to `outputs/deployment-validation/what-if-report.md`:
   ```markdown
   # What-If Validation Report

   ## dev — PASS / BLOCKED
   | Change | Resource | Type | Verdict |
   |---|---|---|---|
   | Create | rg-dev-storage | Storage Account | OK |

   ## staging — PASS / BLOCKED
   ...

   ## prod — PASS / BLOCKED
   ...
   ```

## Rules

- **Never proceed past a blocking condition without explicit user confirmation** — stop, report the blocking change, and wait for the user to decide.
- **Always run what-if for all three environments** before declaring validation complete — a change safe in dev may be destructive in prod.
- **Never run what-if without `--mode Incremental`** — Complete mode deletes resources not in the template.
- **Always save what-if JSON output** to `/tmp/whatif-<env>.json` for inspection.

## Output

- `outputs/deployment-validation/what-if-report.md` — contains a section per environment with PASS or BLOCKED status and change table
