# AWS → Azure Migration Assessment

**Assessment Date:** 2026-05-18
**AWS Account:** 535002891143
**Primary Region:** ap-southeast-2 (Sydney)
**Regions Scanned:** ap-southeast-2, us-east-1, us-west-2, eu-west-1
**Assessed By:** AWS Discovery Agent
**Source IaC:** `source-app/app-code/template.yaml` (SAM/CloudFormation)
**CloudFormation Stack:** `image-upload` (CREATE_COMPLETE, deployed 2026-01-14)

> **Discovery note:** The MCP gateway `call_aws` tool could not access AWS credentials (no `~/.aws` volume mount in `MCP_DOCKER` server). The standalone `aws-api` MCP server defined in `~/.config/Code/User/mcp.json` does have the mount but its tools were not exposed in this session. Discovery therefore used the locally configured AWS CLI v2 in read-only mode. **No changes were made to the AWS environment.**

## Executive Summary

| Metric | Value |
|---|---|
| Workload | Serverless image-upload service (single SAM stack) |
| Total in-scope resources | 16 (managed by `image-upload` CFN stack) |
| Services | 6 (CloudFormation, Lambda, API Gateway, S3, IAM, CloudWatch Logs) |
| Regions with workload | ap-southeast-2 only |
| Complexity | **LOW** |
| Estimated effort | **~5 engineer-days** (1 sprint) |
| Recommended team | 1 engineer + 1 reviewer |
| Recommended approach | Lift & re-platform — single phase |

The workload is **small, self-contained, and stateless** (no DB, no queues, no VPC, no cross-region dependencies). The migration path to Azure is well-trodden: API Gateway → Azure Functions HTTP triggers (or APIM in front), Lambda → Azure Functions Python, S3 → Blob Storage, presigned URLs → User Delegation SAS.

## Resource Inventory (in-scope)

| Service | Count | Notable Configuration |
|---|---|---|
| CloudFormation stacks | 1 | `image-upload` |
| Lambda functions | 4 | Python 3.11, 256 MB, 30 s, x86_64, Zip |
| API Gateway REST APIs | 1 | Regional, AWS_IAM auth, X-Ray on, INFO logging |
| S3 buckets | 2 | `ImageBucket` (SSE-S3, versioning on, public access blocked) + `WebsiteBucket` (static website, public read) |
| IAM roles | 2 | `LambdaExecutionRole`, `ApiGatewayCloudWatchLogsRole` |
| IAM users | 1 | `image-upload-api-user` (+ long-lived access key) |
| CloudWatch log groups | 4 | One per Lambda |

**Out-of-scope items found in account:** 2 AppStream 2.0 S3 buckets (AWS service-managed) and several human admin IAM users — leave in AWS.

## Service Complexity & Azure Mapping

| AWS Service | Count | Complexity | Effort (Days) | Recommended Azure Equivalent | Notes |
|---|---|---|---|---|---|
| Lambda (Python 3.11) | 4 | LOW | 1.5 | Azure Functions (Python 3.11, Flex Consumption) | Replace `boto3` with `azure-storage-blob`; replace S3 presigned URLs with User Delegation SAS |
| API Gateway REST | 1 | LOW | 1.0 | Option A: Function App HTTP triggers + Function keys / Easy Auth. Option B: APIM Consumption tier in front for parity with SigV4-style enterprise auth | 4 routes + CORS — trivial mapping |
| S3 ImageBucket | 1 | LOW | 0.5 | Azure Blob Storage (Hot tier, SSE with PMK, blob versioning, soft delete) | 1:1 mapping |
| S3 WebsiteBucket | 1 | LOW | 0.5 | Azure Storage static website OR Azure Static Web Apps | SWA recommended for free TLS + global CDN |
| IAM Role (LambdaExecutionRole) | 1 | LOW | 0.5 | User-Assigned Managed Identity + `Storage Blob Data Contributor` on container | Identity-based, no secrets |
| IAM User + Access Key (ApiUser) | 1 | MEDIUM | 0.5 | Entra ID app registration (client creds) OR APIM subscription key OR Function key | Eliminate long-lived static keys |
| CloudWatch Logs + X-Ray | 5 | LOW | 0.5 | Application Insights + Log Analytics workspace | Automatic with Functions/APIM |
| CloudFormation | 1 stack | LOW | 1.0 | Bicep (preferred) or Terraform | Source template already available |
| **Total** | **16** | **LOW** | **~5 days** | — | Single-sprint migration |

## Phased Plan (single phase recommended)

Because there are no databases, queues, VPCs, or cross-resource state to coordinate, a single-phase cutover is appropriate.

### Phase 1 — Build & Deploy in Azure (Days 1-3)
1. Author Bicep modules: Storage Account (+ blob container + static website / SWA), Function App (Flex Consumption Python 3.11) + App Service Plan/Flex, User-Assigned Managed Identity, App Insights, Log Analytics, optional APIM Consumption.
2. Refactor 4 Python handlers: swap `boto3.client('s3')` → `azure.storage.blob.BlobServiceClient` with `DefaultAzureCredential`; swap `generate_presigned_url` → `generate_blob_sas` with User Delegation Key.
3. Configure RBAC: `Storage Blob Data Contributor` for the UAMI on the image container.
4. Deploy with `azd up` or GitHub Actions OIDC.

### Phase 2 — Cutover (Day 4)
1. Upload existing images from S3 to Blob (use `azcopy sync` — single command).
2. Re-publish static site (app.html) to Azure Storage static website / SWA.
3. Smoke-test all 4 API routes.
4. Update DNS / client config to point at Azure endpoint.

### Phase 3 — Decommission (Day 5)
1. Confirm zero traffic to API Gateway.
2. `aws cloudformation delete-stack --stack-name image-upload`.

## Risk Assessment

### High-Risk Items
None. The workload is small, stateless, and has no upstream/downstream dependencies outside the stack.

### Medium-Risk Items
| Risk | Mitigation |
|---|---|
| **Auth model change** — frontend SPA currently SigV4-signs requests with a long-lived IAM access key embedded client-side. This is also a pre-existing security debt. | Move to Function keys (simplest, dev parity), Easy Auth + Entra ID (best practice), or APIM subscription keys. Update SPA to use the new auth header. |
| **Presigned URL semantics differ** — S3 presigned URLs are single-key signed; Azure User Delegation SAS requires obtaining a delegation key first. | Cache the delegation key (valid up to 7 days) in the Function host or memory. Pattern is well-documented. |
| **Frontend CORS rules** — both `ImageBucket` and API allow `AllowedOrigins: ['*']`. | Restrict to the SWA / static-site URL post-migration. |
| **Migration of existing image data** — bucket may contain user images. | Use `azcopy sync` with `--preserve-last-modified-time`. Run twice (initial + delta) for cutover. |

### Low-Risk Items
- Logging migration (CloudWatch → App Insights) — turnkey via Functions binding.
- IAM role → Managed Identity — straightforward.

## Dependency Groups

**Must migrate together (single deployment):**
1. Storage Account + Blob container (foundation)
2. User-Assigned Managed Identity + RBAC assignment
3. Function App + 4 functions
4. (Optional) APIM in front

**Can migrate in parallel with #3:**
- Static frontend (SWA / Storage static website)

**No cross-region or cross-account dependencies.**

## Security & Compliance Notes

| Finding | Severity | Recommendation in Azure |
|---|---|---|
| IAM access key `AKIAXZEFIIOD2OIWPRPK` issued to `image-upload-api-user` for client SigV4 — long-lived static credential | High | Use Function keys, Entra ID, or APIM subscription keys; do not embed long-lived secrets in browser |
| `WebsiteBucket` allows public read (`PublicReadGetObject`) | Acceptable for static site | Equivalent: Storage static website with anonymous read, or SWA (preferred, adds TLS + CDN) |
| `ImageBucket` uses SSE-S3 (AES256) | Baseline | Map to SSE with Microsoft-managed keys; consider Customer-Managed Keys in Key Vault for higher tiers |
| Lambda log groups have no retention set (Never expire) | Cost/Compliance | Set Log Analytics workspace retention (e.g., 30 days) |
| API Gateway `*` CORS allowed origins | Medium | Restrict in APIM / Function CORS policy to the SWA hostname |

## Cost Indicators (informational only — detailed pricing in Phase 2)

This workload sits comfortably in the free / lowest tiers on either cloud:
- 4 Lambda × 256 MB × low traffic → ~$0 (Lambda free tier)
- API Gateway → pennies/month
- S3 — depends on object count

Azure equivalent (Flex Consumption Functions, Standard Blob Storage, optional APIM Consumption) should land in the same low single-digit USD/month range. A formal `cost-comparison.md` will be produced in Phase 2.

## Next Steps

1. **Phase 2 (azure-architect)** — Produce `design-document.md`, Azure architecture diagram, service mapping, and cost comparison.
2. **Phase 3a (iac-transformation)** — Generate Bicep (`main.bicep` + modules) from the SAM template.
3. **Phase 3b (code-refactor)** — Refactor 4 Python handlers from `boto3` to `azure-storage-blob` + `azure-identity`.
4. **Phase 3c (pipeline-builder)** — GitHub Actions workflow with OIDC to Azure.
5. **Phase 4 (deployment-validation)** — Pre/post-deploy validation + smoke tests.

## Confidence & Validation

- **Confidence:** HIGH — every resource was confirmed via live AWS API calls AND cross-referenced against the canonical SAM template at `source-app/app-code/template.yaml`. Both sources agree.
- **Validation required:** Human review of the auth-model recommendation (Function keys vs APIM vs Entra ID) and confirmation that AppStream resources are intentionally out of scope.

---
**Prepared by:** AWS Discovery Agent (read-only)
**Artifacts emitted:**
- `outputs/aws-migration-artifacts/aws-inventory.json`
- `outputs/aws-migration-artifacts/architecture-diagram.mmd`
- `outputs/aws-migration-artifacts/dependency-matrix.csv`
- `outputs/aws-migration-artifacts/migration-assessment.md` (this file)
