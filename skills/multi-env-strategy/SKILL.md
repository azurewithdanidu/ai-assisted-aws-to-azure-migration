---
name: multi-env-strategy
description: 'Define the GitHub Environments and promotion path for dev, staging, and prod. Use when: configuring deployment approvals, secret naming, branch protection, promotion gates, or rollback rules for Azure migration workflows.'
---

# Multi-Environment Strategy Skill

## Purpose

Establish a repeatable and auditable promotion model from `dev` to `staging` to `prod` so Azure deployments are isolated, reviewable, and reversible.

## When to Use

- When designing or implementing GitHub Actions deployment workflows
- When documenting repo setup for maintainers
- When deciding environment-specific secrets, variables, or reviewers
- When validating that promotion controls are production-safe

## Inputs

| Path | Why it matters |
|---|---|
| `outputs/azure-architecture-output/design-document.md` | Section 11 defines the CI/CD contract |
| `.github/workflows/` | Workflow files that must reference environments correctly |
| `outputs/bicep-templates/parameters/` | Environment-specific parameter files |

## Outputs

| Path | Result |
|---|---|
| `outputs/pipeline/setup-environments.md` | Human setup guide for GitHub repository settings |
| `.github/workflows/*.yml` | Workflow files with explicit environment usage and promotion logic |

## Process

### 1. Branch-to-environment mapping

Use this default promotion path unless the design document states a different model:

| Event / Branch | Environment | Deployment mode |
|---|---|---|
| Pull request into `dev` | `dev` | Automatic for preview or validation |
| Merge / push into `main` after `dev` validation | `staging` | Automatic after required checks pass |
| Manual `workflow_dispatch` from `main` or release tag | `prod` | Manual plus approval gate |

### 2. Exact GitHub Environment configuration steps

Perform these steps in GitHub:

1. Open the repository.
2. Go to **Settings → Environments**.
3. Click **New environment**.
4. Create `dev`, then repeat for `staging` and `prod`.
5. Configure each environment as follows:

| Environment | Required reviewers | Wait timer | Deployment branch rules | Notes |
|---|---|---|---|---|
| `dev` | None or 1 optional reviewer | 0 minutes | allow `dev`, `feature/*`, `bugfix/*`, and pull request deployments | Fast feedback environment |
| `staging` | 1 required reviewer | 0 to 5 minutes | allow `main` only | Mirrors release candidate behavior |
| `prod` | 2 required reviewers | 10 minutes | allow `main` and optionally `refs/tags/v*` for tagged releases | No automatic push deployments |

6. Add environment secrets and variables to each environment.
7. Confirm that workflows reference `environment: dev`, `environment: staging`, or `environment: prod` on deployment jobs.

### 3. Secret naming convention

Use these names consistently. `DEV`, `STAGING`, and `PROD` are the only valid `{ENV}` tokens.

| Name | Scope | Example | Notes |
|---|---|---|---|
| `AZURE_CLIENT_ID_DEV` | Repository secret | `AZURE_CLIENT_ID_DEV` | Federated identity app registration for dev |
| `AZURE_CLIENT_ID_STAGING` | Repository secret | `AZURE_CLIENT_ID_STAGING` | Federated identity app registration for staging |
| `AZURE_CLIENT_ID_PROD` | Repository secret | `AZURE_CLIENT_ID_PROD` | Federated identity app registration for prod |
| `AZURE_TENANT_ID` | Repository secret | `AZURE_TENANT_ID` | Shared unless environments span tenants |
| `AZURE_SUBSCRIPTION_ID` | Repository secret | `AZURE_SUBSCRIPTION_ID` | Shared subscription default; use env-specific variants only if subscriptions differ |
| `RESOURCE_GROUP_NAME_DEV` | Repository variable or environment variable | `rg-orders-dev-aue` | Environment-specific resource group |
| `RESOURCE_GROUP_NAME_STAGING` | Repository variable or environment variable | `rg-orders-staging-aue` | Environment-specific resource group |
| `RESOURCE_GROUP_NAME_PROD` | Repository variable or environment variable | `rg-orders-prod-aue` | Environment-specific resource group |
| `FUNCTION_APP_NAME_DEV` | Variable | `func-orders-dev` | Example service-specific value |
| `FUNCTION_APP_NAME_STAGING` | Variable | `func-orders-staging` | Example service-specific value |
| `FUNCTION_APP_NAME_PROD` | Variable | `func-orders-prod` | Example service-specific value |

**Workflow mapping example**

```yaml
env:
  TARGET_ENV: ${{ inputs.environment }}
  AZURE_CLIENT_ID: ${{ secrets[format('AZURE_CLIENT_ID_{0}', upper(inputs.environment))] }}
```

### 4. Branch protection rules that must be set

Configure branch protection for both `dev` and `main`:

| Branch | Required settings |
|---|---|
| `dev` | Require pull request before merge, at least 1 approval, dismiss stale reviews, require status checks for unit tests and content validation, block force pushes and deletions |
| `main` | Require pull request before merge, at least 2 approvals, require conversation resolution, require status checks, enforce linear history if supported, block force pushes and deletions, restrict direct pushes to maintainers only |

Recommended required status checks:

- unit tests
- skill or markdown validation
- security scan
- architecture or content review workflow if present

### 5. Promotion gate checklist

A deployment must not promote forward until all gate items are satisfied.

#### Dev → Staging

- All repository-required status checks passed
- Bicep templates build cleanly
- Function application package or code validation passed
- No open blocker in `outputs/migration-task-plan.md`
- Architecture and service naming are stable
- Reviewer approved the staging deployment if the environment requires it

#### Staging → Prod

- Staging deployment completed successfully
- Smoke tests or validation workflow passed against staging
- Security-sensitive changes reviewed
- Cost-impacting changes acknowledged if they differ materially from Section 10
- `what-if` or equivalent infra diff was reviewed
- Prod environment approvals collected
- Wait timer completed without cancellation

### 6. Rollback trigger conditions

Trigger rollback or stop promotion when any of these occur:

- Deployment job fails after partial resource updates
- Smoke tests fail in the target environment
- Validation report status is `FAILED`
- Security controls such as OIDC, WAF, or private endpoints are missing or misconfigured
- Unexpected infra diff affects resources outside the approved scope
- Error rate, latency, or queue backlog exceeds the documented tolerance after release
- Manual approver spots incorrect environment targeting or wrong secret resolution

### 7. Environment-specific workflow rules

- Always set `environment: <name>` on the deployment job, not just on the workflow.
- Use environment-specific parameter files such as `outputs/bicep-templates/parameters/dev.bicepparam`.
- Keep build jobs environment-neutral when possible; apply environments only at deployment or promotion jobs.
- Reference environment secrets and variables explicitly so reviewers can trace what changes between stages.

### 8. Edge Cases / Failure Modes

- **Single subscription, separate resource groups:** keep `AZURE_SUBSCRIPTION_ID` shared and vary resource groups only.
- **Separate subscriptions per environment:** extend the convention to `AZURE_SUBSCRIPTION_ID_DEV`, `AZURE_SUBSCRIPTION_ID_STAGING`, and `AZURE_SUBSCRIPTION_ID_PROD` and document the exception.
- **Hotfix deployment pressure:** do not bypass prod approvals; use an expedited but still approved `workflow_dispatch` path.
- **Workflow missing `environment:` key:** GitHub protection rules will not fire; treat this as a release blocker.
- **Environment variables defined at repo scope by mistake:** move them to environment scope if they differ across stages.

## Rules

- **Never auto-deploy to prod on push.**
- **Never use the wrong client ID for the target environment.**
- **Always configure GitHub Environments in Settings before relying on workflow YAML.**
- **Always protect `main` more strictly than `dev`.**
- **Always define rollback triggers before the first production deployment.**

## Best Practices

- Keep secret names predictable so workflows can compute them safely.
- Separate reviewer groups for staging and prod whenever the team size allows it.
- Use promotion gates as decision points, not as documentation afterthoughts.
- Keep rollout and rollback instructions close to the workflow specification.
- Prefer repository secrets only for truly shared values; move the rest to environments or environment-scoped variables.

---

## Runtime Detection

This skill supports both Bash and PowerShell. Use the following detection order:

| Priority | Runtime | Condition | Script |
|---|---|---|---|
| 1 (preferred) | Bash | `curl` and `jq` available on PATH | `scripts/<name>.sh` |
| 2 | PowerShell 7+ | `pwsh` available on PATH | `scripts/<name>.ps1` |
| 3 (fallback) | Windows PowerShell 5.1 | `powershell.exe` available | `scripts/<name>.ps1 -ExecutionPolicy RemoteSigned` |

**Detection snippet (Bash):**
```bash
if command -v curl &>/dev/null && command -v jq &>/dev/null; then
  bash scripts/<name>.sh [args]
elif command -v pwsh &>/dev/null; then
  pwsh -File scripts/<name>.ps1 [args]
elif command -v powershell.exe &>/dev/null; then
  powershell.exe -ExecutionPolicy RemoteSigned -File scripts/<name>.ps1 [args]
else
  echo "ERROR: Requires curl+jq (Bash) or PowerShell 7+ (pwsh)"
  exit 1
fi
```

**Parameter naming convention:** Bash uses `--kebab-case`; PowerShell uses `-PascalCase`. Both produce identical output.

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
| Branch protection rules | https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches |

### Microsoft / Azure Documentation

| Topic | Link |
|---|---|
| Azure deployment environments | https://learn.microsoft.com/en-us/azure/deployment-environments/overview-what-is-azure-deployment-environments |
| Azure resource group naming best practices | https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-naming |
| Azure landing zone naming conventions | https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/resource-abbreviations |

### Best Practices

- **Production needs both human approval and a technical gate** — one without the other is fragile.
- **Environment names should map cleanly from workflow inputs to secret names** — this keeps YAML maintainable.
- **Branch protection is part of deployment safety** — not a separate governance concern.
- **Rollback conditions should be pre-agreed, not improvised during incident response.**
