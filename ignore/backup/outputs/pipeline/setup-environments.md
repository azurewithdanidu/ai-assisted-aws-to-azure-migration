# GitHub Environment Protection Rules Setup

> **One-time human setup** — configure these GitHub Environments before running
> any workflow that targets `staging` or `prod`. The `dev` environment can be
> auto-approved.

---

## Environment Configuration

Navigate to **GitHub → Settings → Environments** and create the following environments:

### `dev`

| Setting | Value |
|---|---|
| Required reviewers | None (auto-approve) |
| Wait timer | 0 minutes |
| Deployment branches | `main` and `dev` |

### `staging`

| Setting | Value |
|---|---|
| Required reviewers | 1 reviewer from the engineering team |
| Wait timer | 0 minutes |
| Deployment branches | `main` |

### `prod`

| Setting | Value |
|---|---|
| Required reviewers | 2 reviewers (require a lead engineer or ops team member) |
| Wait timer | 10 minutes (provides a cancellation window) |
| Deployment branches | `main` (manual `workflow_dispatch` only) |

---

## Secret and Variable Separation

| Secret / Variable | `dev` | `staging` | `prod` |
|---|---|---|---|
| `AZURE_CLIENT_ID` | Repo-level (shared) | Repo-level (shared) | Repo-level (shared) |
| `AZURE_TENANT_ID` | Repo-level (shared) | Repo-level (shared) | Repo-level (shared) |
| `AZURE_SUBSCRIPTION_ID` | Repo-level (shared) | Repo-level (shared) | Repo-level (shared) |
| `RESOURCE_GROUP_NAME` | `rg-image-upload` (repo var) | Override per-env if needed | Override per-env if needed |
| `FUNCTION_APP_NAME` | `img-upload-func-dev-ase` (repo var) | Override per-env if needed | Override per-env if needed |
| `STATIC_WEB_APP_NAME` | `img-upload-swa-dev-ase` (repo var) | Override per-env if needed | Override per-env if needed |

For `staging` and `prod`, you may add environment-level variable overrides in
**GitHub → Settings → Environments → \<env\> → Variables** to point to the
correct resource names for those environments.

---

## Branch-to-Environment Mapping

| Trigger | GitHub Environment | Auto-deploy? |
|---|---|---|
| Push to `main` (infra changes) | `dev` (via `vars.ENVIRONMENT`) | Yes |
| Push to `main` (function changes) | `dev` (via `vars.ENVIRONMENT`) | Yes |
| Push to `main` (static web changes) | `dev` (via `vars.ENVIRONMENT`) | Yes |
| `workflow_dispatch` with `environment: staging` | `staging` | No — 1 reviewer required |
| `workflow_dispatch` with `environment: prod` | `prod` | No — 2 reviewers + 10 min wait |

---

## OIDC Federated Credential Subjects

Each environment needs a matching federated credential (see `setup-oidc.md`):

| GitHub Environment | OIDC Subject |
|---|---|
| `dev` | `repo:azurewithdanidu/ai-assisted-aws-to-azure-migration:environment:dev` |
| `staging` | `repo:azurewithdanidu/ai-assisted-aws-to-azure-migration:environment:staging` |
| `prod` | `repo:azurewithdanidu/ai-assisted-aws-to-azure-migration:environment:prod` |

---

## References

- [GitHub Environments overview](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment)
- [Environment protection rules](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment#environment-protection-rules)
- [Environment secrets and variables](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment#environment-secrets)
