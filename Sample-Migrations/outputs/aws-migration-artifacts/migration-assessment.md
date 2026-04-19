# AWS to Azure Migration Assessment

**Assessment Date:** 2026-04-18  
**AWS Account:** 535002891143  
**Assessed By:** AWS Discovery Agent (Read-Only)  
**Primary Region:** ap-southeast-2 (Sydney, Australia)  
**CloudFormation Stack:** image-upload  

---

## Executive Summary

The AWS environment hosts a **serverless image upload application** — a straightforward, event-driven architecture with no databases, no containers, and no complex networking. All production resources are deployed in a single region and managed by one CloudFormation stack.

| Metric | Value |
|--------|-------|
| **Total Resources** | 30 |
| **Active Application Resources** | 13 |
| **Residual / Legacy Resources** | 7 (AppStream artefacts) |
| **Services In Use** | 9 |
| **Active Regions** | 1 (ap-southeast-2) |
| **Overall Complexity** | **LOW** |
| **Estimated Total Effort** | **2–3 weeks** |
| **Recommended Team Size** | 1–2 engineers |
| **Recommended Approach** | Lift-and-shift with targeted SDK refactor |
| **IaC Status** | Azure Bicep templates already drafted in workspace |

---

## Application Architecture Overview

```
Browser
  │
  ├─► S3 Static Website (app.html)  ──► downloads SPA frontend
  │
  └─► API Gateway REST API (AWS_IAM / SigV4)
        ├─ POST   /upload                → Lambda UploadFunction     → S3 (pre-signed PUT URL)
        ├─ GET    /files                 → Lambda ListFilesFunction   → S3 (list + pre-signed GET)
        ├─ GET    /files/{id}/view-url   → Lambda GetViewUrlFunction  → S3 (pre-signed GET URL)
        └─ DELETE /files/{id}           → Lambda DeleteFileFunction  → S3 (DeleteObject)
```

All Lambda functions share one IAM execution role and one S3 bucket (`image-upload-imagebucket-t8isnbr8sswv`).  
Authentication is AWS SigV4 using a dedicated IAM user (`image-upload-api-user`).

---

## Service Complexity Matrix

| AWS Service | Azure Equivalent | Resource Count | Complexity | Effort (Days) | Key Migration Notes |
|---|---|---|---|---|---|
| **AWS Lambda** | Azure Functions (Consumption) | 4 functions | MEDIUM | 3 | boto3 → azure-storage-blob; pre-signed URLs → SAS tokens; env var rename |
| **API Gateway (REST)** | Azure API Management / Azure Functions HTTP trigger | 1 API, 4 routes | MEDIUM | 2 | AWS_IAM auth → Azure AD / API Key; CORS re-configure; SigV4 client logic update |
| **S3 (Image Bucket)** | Azure Blob Storage | 1 bucket | LOW | 1 | Versioning → Blob versioning; CORS → Blob CORS; private access |
| **S3 (Website Bucket)** | Azure Static Web Apps | 1 bucket | LOW | 1 | Static website hosting; note index doc is `app.html` not `index.html` |
| **IAM Roles** | Azure Managed Identity + RBAC | 2 custom roles | LOW | 0.5 | LambdaExecutionRole → System-assigned Managed Identity + Storage Blob Data Contributor |
| **IAM User (API access)** | Azure AD Service Principal or API Key | 1 user + access key | LOW | 0.5 | Eliminate long-lived key; use Azure AD token or APIM subscription key |
| **CloudFormation** | Azure Bicep / ARM | 1 stack | LOW | 1 | Bicep templates already drafted; validate and deploy |
| **CloudWatch Logs** | Azure Monitor / Application Insights | 8 log groups | LOW | 0.5 | Function App built-in App Insights integration |
| **VPC / Networking** | N/A (no migration needed) | 1 default VPC | NONE | 0 | Lambda not VPC-attached; Azure Functions Consumption plan has no VNet requirement |
| **KMS** | Azure Key Vault (optional) | 1 key | LOW | 0 | S3 bucket uses SSE-S3 not CMK; Azure Blob uses Microsoft-managed key by default |
| **AppStream (legacy)** | N/A | 0 active | NONE | 0 | Decommissioned; residual S3 buckets and alarms can be deleted |
| **TOTAL** | | **~13 active** | **LOW** | **~9.5** | Recommend 2–3 week sprint including testing |

---

## AWS → Azure Service Mapping

| AWS Resource | Azure Resource |
|---|---|
| AWS Lambda (python3.11) | Azure Functions v4 (Python 3.11) – Consumption plan |
| Amazon API Gateway REST API | Azure API Management + Function HTTP triggers, or APIM alone |
| S3 Bucket (private, versioned) | Azure Blob Storage (Standard LRS) with versioning enabled |
| S3 Bucket (static website) | Azure Static Web Apps (Free tier) |
| IAM Role (Lambda execution) | System-assigned Managed Identity on Function App |
| IAM inline policy (S3 access) | RBAC: Storage Blob Data Contributor on storage account |
| IAM User + Access Key (API auth) | Azure AD App Registration or APIM Subscription Key |
| AWS SigV4 request signing | Azure AD Bearer token or APIM Ocp-Apim-Subscription-Key |
| CloudWatch Logs | Application Insights + Log Analytics Workspace |
| CloudWatch Alarms | Azure Monitor Metric Alerts |
| AWS CloudFormation | Azure Bicep / ARM templates |
| AWS KMS CMK | Azure Key Vault (if CMK needed — currently not required) |

---

## Complexity Scoring (per skill rubric)

| Service | Score |
|---|---|
| Lambda (4 functions × 2) | 8 |
| S3 (2 app buckets × 2) | 4 |
| API Gateway | 3 |
| IAM | 2 |
| VPC (default, no attachment) | 1 |
| CloudWatch | 1 |
| **Total** | **19** |
| **Weeks estimate (÷ 2)** | **~9.5 days → 2 weeks** |

> Complexity rating: **LOW**. This is a compact, well-scoped demo-grade serverless application with no stateful services (no database, no cache, no message queues).

---

## Risk Assessment

### High Risk Items

**None identified** — the architecture is simple and well-understood.

### Medium Risk Items

| Risk | Description | Mitigation |
|---|---|---|
| **Pre-signed URL pattern change** | AWS S3 pre-signed URLs (boto3 `generate_presigned_url`) must be replaced with Azure Blob SAS tokens (`generate_blob_sas`). URL format and expiry logic differ. | Update all 3 Lambda functions (upload/list/view handlers). SAS token generation is well-documented. |
| **Authentication model change** | Frontend uses AWS SigV4 request signing (via IAM user access key). Azure has no equivalent — must switch to Azure AD Bearer token, APIM subscription key, or anonymous (demo). | Agree on target auth pattern before coding. API key (APIM subscription) is simplest equivalent. |
| **Static website index document** | S3 website uses `app.html` as index (not `index.html`). Azure Static Web Apps defaults to `index.html`. | Rename file or configure routes in `staticwebapp.config.json`. Note in user memory: this is known. |
| **Access key exposed in CloudFormation outputs** | The IAM user's secret access key is visible in CloudFormation stack outputs. | Do not migrate the secret to Azure. Rotate/delete the IAM user access key post-migration. |
| **CORS configuration parity** | S3 image bucket has wildcard CORS (`AllowedOrigins: ['*']`). Must replicate in Azure Blob Storage CORS settings. | Apply CORS rules to Azure Storage account via Bicep. |

### Low Risk Items

- **AppStream residual resources**: Two S3 buckets and two stale CloudWatch alarms remain from a decommissioned AppStream deployment (June 2025). These are not part of the application. Recommend deletion before or after migration.
- **Legacy log groups**: Several CloudWatch log groups from previous deployment iterations (`image-upload-v2-*`, `API-Gateway-Execution-Logs_5v4osrc2kc/*`, etc.) can be cleaned up independently.
- **KMS key**: One KMS CMK exists in `ap-southeast-2` but is not used by the active stack. No action needed for migration.

---

## Dependency Groups & Migration Order

Resources **must** be migrated in the following order (cannot parallelise within a phase):

### Phase 1: Infrastructure Foundation (Days 1–2)

> Prerequisite for all other phases.

| Task | AWS Source | Azure Target | Notes |
|---|---|---|---|
| Create Resource Group | N/A | azure-image-upload-rg | Target RG for all resources |
| Provision Storage Account | image-upload-imagebucket-t8isnbr8sswv | Azure Blob Storage | Enable versioning + CORS |
| Provision Static Web App | image-upload-websitebucket-vd866vxtcs1z | Azure Static Web Apps | Upload app.html |
| Assign RBAC | IAM inline S3 policy | Storage Blob Data Contributor | On Function App managed identity |
| Deploy Bicep templates | image-upload (CFN) | main.bicep + modules | Bicep already exists in workspace |

**Can parallelise:** Storage account and Static Web App provisioning are independent.

### Phase 2: Function App Code Refactor (Days 3–5)

> Depends on Phase 1 (needs storage account connection string / managed identity).

| Task | AWS Source | Azure Target | Code Change |
|---|---|---|---|
| Upload handler | `upload_handler.py` (boto3) | `function_app.py` (azure-storage-blob) | `generate_presigned_url(PUT)` → `generate_blob_sas(BlobSasPermissions.write)` |
| List handler | `list_handler.py` (boto3) | `function_app.py` | `list_objects_v2` → `list_blobs` + SAS per blob |
| View URL handler | `view_handler.py` (boto3) | `function_app.py` | `generate_presigned_url(GET)` → `generate_blob_sas(BlobSasPermissions.read)` |
| Delete handler | `delete_handler.py` (boto3) | `function_app.py` | `delete_object` → `delete_blob` |
| Env var rename | `BUCKET_NAME` | `BLOB_CONTAINER_NAME` | Reserved var: do NOT use CONTAINER_NAME |

**Can parallelise:** All 4 function rewrites are independent of each other.

### Phase 3: API Layer & Authentication (Days 6–7)

> Depends on Phase 2 (functions must be deployed).

| Task | AWS Source | Azure Target | Notes |
|---|---|---|---|
| Configure HTTP triggers | API Gateway routes | Azure Function HTTP triggers | Routes already match (POST /upload, GET /files, etc.) |
| Configure authentication | AWS_IAM (SigV4) | API Key (APIM) or Azure AD | Simplest: APIM subscription key |
| Update frontend SPA | SigV4 signing JS | API key header / Bearer token | Update app.html fetch() calls |

### Phase 4: Validation & Cutover (Days 8–10)

| Task | Description |
|---|---|
| Functional testing | Test all 4 API routes end-to-end |
| Performance testing | Validate cold start times and SAS token expiry |
| DNS / URL update | Update any bookmarks; S3 website URL → Azure Static Web Apps URL |
| Decommission AWS | After validation: delete image-upload CFN stack; clean up AppStream residuals |
| Monitor | Verify Application Insights logs and metrics |

---

## Critical Path Analysis

```
Day 1-2:  [Bicep deploy] → [Storage Account + Static Web App + RBAC]
               │
Day 3-5:       └─────────► [Refactor 4 Lambda → Function App] (parallel)
                                    │
Day 6-7:                            └─► [HTTP triggers + Auth config + Frontend update]
                                                │
Day 8-10:                                        └─► [Test + Cutover + AWS decommission]
```

**Minimum calendar time:** 2 weeks (with 1 engineer)  
**Optimum calendar time:** 1 week (with 2 engineers parallelising Phase 2)

---

## Azure Architecture (Target State)

```
Browser
  │
  ├─► Azure Static Web Apps  ──► serves app.html (SPA frontend)
  │
  └─► Azure API Management (or direct Function HTTP trigger)
        ├─ POST   /upload               → Azure Function UploadFunction    → Blob Storage (SAS write)
        ├─ GET    /files                → Azure Function ListFilesFunction  → Blob Storage (list + SAS read)
        ├─ GET    /files/{id}/view-url  → Azure Function GetViewUrlFunction → Blob Storage (SAS read)
        └─ DELETE /files/{id}          → Azure Function DeleteFileFunction → Blob Storage (delete)

Identity: System-assigned Managed Identity on Function App
          + Storage Blob Data Contributor RBAC on Storage Account
Monitoring: Application Insights + Log Analytics
IaC: Azure Bicep (outputs/bicep-templates/main.bicep)
```

---

## Effort Estimate Summary

| Phase | Duration | Parallelisable |
|---|---|---|
| Phase 1: Infrastructure | 2 days | Partially |
| Phase 2: Code Refactor | 3 days | Fully (4 functions) |
| Phase 3: API & Auth | 2 days | No |
| Phase 4: Validation & Cutover | 3 days | Partially |
| **Total** | **~10 days (2 weeks)** | — |

**Cost Impact:** Current AWS spend ~$7.50/month. Azure equivalent (Functions Consumption + Blob Storage + Static Web Apps Free) would be approximately **$3–5/month** — a ~40–60% cost reduction at demo-scale.

---

## Pre-Migration Checklist

- [ ] Rotate/invalidate the IAM user access key (`AKIAXZEFIIOD2OIWPRPK`) currently exposed in CloudFormation outputs
- [ ] Confirm target Azure subscription and resource group naming conventions
- [ ] Confirm authentication model for Azure (API key vs Azure AD)
- [ ] Verify Azure Static Web Apps handles `app.html` as root document (add `staticwebapp.config.json`)
- [ ] Review BLOB_CONTAINER_NAME env var (do not use `CONTAINER_NAME` — reserved by Azure Functions host)
- [ ] Confirm Python 3.11 is used for Azure Functions (3.12+ not supported by Functions v4)
- [ ] Remove AppStream residual S3 buckets and stale CloudWatch alarms from AWS post-migration

---

## Post-Migration Cleanup (AWS)

After Azure validation is complete and traffic has cut over:

1. Delete CloudFormation stack `image-upload` (removes Lambda, API Gateway, S3, IAM user, IAM roles)
2. Manually delete orphaned resources not in the stack:
   - `appstream-app-settings-ap-southeast-2-535002891143-ar2b5jb0` (S3)
   - `appstream2-36fb080bb8-ap-southeast-2-535002891143-hwzroy6c` (S3)
   - `Appstream2-ExampleStack-fleet-*` CloudWatch alarms (2)
   - Legacy CloudWatch log groups
   - KMS key `6c852b32-93c4-4049-91fe-050814d33c10` (if unused)
3. Remove AWS IAM admin users no longer required for this workload

---

## Next Steps

1. **Review & Approve** — Human architect reviews this assessment and confirms target architecture
2. **Validate Bicep** — Review existing `outputs/bicep-templates/main.bicep` for completeness
3. **Begin Phase 1** — `az deployment sub create` to provision Azure infrastructure
4. **Code Refactor** — Update the 4 Lambda Python files to use `azure-storage-blob` SAS tokens
5. **Test locally** — Use Azure Functions Core Tools to run functions locally against Azure Blob
6. **Deploy & Validate** — Deploy to Azure, run end-to-end tests
7. **Cutover** — Update frontend URL, notify users
8. **Decommission AWS** — Delete CloudFormation stack and residual resources

---

**Prepared by:** AWS Discovery Agent (Read-Only)  
**Confidence Level:** High — based on AWS MCP server API discovery of live account  
**Validation Required:** Review by human architect before executing any migration steps  
**Note:** No changes were made to the AWS environment during this discovery.
# AWS to Azure Migration Assessment

**Assessment Date:** 2026-04-18  
**AWS Account:** 535002891143  
**Primary Region:** ap-southeast-2 (Sydney, Australia)  
**Application:** Image Upload Service  
**Assessed By:** AWS Discovery Agent (read-only discovery — no changes made to AWS environment)

---

## Executive Summary

The AWS account hosts a single greenfield serverless application — an **Image Upload Service** — deployed via CloudFormation in `ap-southeast-2`. The architecture is minimal and modern: four Python 3.11 Lambda functions fronted by a REST API Gateway, backed by S3 for image storage, and a static website for the frontend.

No databases, no message queues, no container workloads, and no custom networking are present. All other AWS regions are empty. Two AppStream-related legacy resources (S3 buckets and CloudWatch alarms) are present from a June 2025 demo and are not part of the active application.

This is a **LOW complexity migration**. The application maps cleanly to Azure equivalents, and Bicep templates already exist in the workspace (`bicep-templates/`). The primary effort is SDK translation (boto3 → Azure SDK), authentication model modernisation (IAM user key → Managed Identity/SAS), and CORS/routing configuration.

| Metric | Value |
|--------|-------|
| Total resources discovered | 36 |
| Active application resources | 16 |
| Legacy/orphaned resources | 4 |
| Regions with active workloads | 1 (ap-southeast-2) |
| CloudFormation stacks | 1 (image-upload, CREATE_COMPLETE) |
| Estimated migration complexity | **LOW** |
| Estimated migration effort | **8–12 days (1.5–2 weeks)** |
| Recommended team size | 1–2 engineers |
| Source code available | Yes (`app-code/`) |
| Bicep templates pre-existing | Yes (`bicep-templates/`) |

---

## Resource Inventory Summary

### Active Application Resources

| Service | Resource | Count | Region | Status |
|---------|----------|-------|--------|--------|
| AWS Lambda | Python 3.11 functions | 4 | ap-southeast-2 | Active |
| API Gateway | REST API (Regional, IAM Auth) | 1 | ap-southeast-2 | Active |
| S3 | Image storage bucket (private, versioned) | 1 | ap-southeast-2 | Active |
| S3 | Static website bucket (public) | 1 | ap-southeast-2 | Active |
| IAM Role | LambdaExecutionRole | 1 | Global | Active |
| IAM Role | ApiGatewayCloudWatchLogsRole | 1 | Global | Active |
| IAM User | image-upload-api-user (service account) | 1 | Global | Active |
| CloudFormation | image-upload stack | 1 | ap-southeast-2 | CREATE_COMPLETE |
| CloudWatch Log Groups | Active Lambda + API GW logs | 5 | ap-southeast-2 | Active |
| VPC | Default VPC + 3 subnets | 1 | ap-southeast-2 | Default (unused by app) |
| KMS | AWS-managed Lambda key | 1 | ap-southeast-2 | AWS-managed |

### Legacy / Orphaned Resources (not part of application)

| Service | Resource | Count | Notes |
|---------|----------|-------|-------|
| S3 | AppStream auto-created buckets | 2 | From June 2025 demo, no active fleet |
| CloudWatch Alarms | AppStream auto-scaling alarms | 2 | No active fleet, INSUFFICIENT_DATA state |
| CloudWatch Log Groups | Residual from deleted stacks | 5 | From image-upload-v2 and older iterations |

### Services Confirmed Absent

EC2, ECS, EKS, Elastic Beanstalk, RDS, Aurora, DynamoDB, ElastiCache, Redshift, SQS, SNS, EventBridge, Kinesis, CloudFront, Route 53, ACM, Secrets Manager, CodePipeline, CodeBuild, CodeDeploy, Step Functions, Direct Connect, VPN, WAF, Shield.

---

## Lambda Functions — Detail

| Function | Handler | Memory | Timeout | S3 SDK Operation | API Route |
|----------|---------|--------|---------|-----------------|-----------|
| UploadFunction | upload_handler.lambda_handler | 256 MB | 30 s | generate_presigned_post() | POST /upload |
| ListFilesFunction | list_handler.lambda_handler | 256 MB | 30 s | list_objects_v2() + generate_presigned_url() | GET /files |
| GetViewUrlFunction | view_handler.lambda_handler | 256 MB | 30 s | list_objects_v2() + generate_presigned_url() | GET /files/{fileId}/view-url |
| DeleteFileFunction | delete_handler.lambda_handler | 256 MB | 30 s | list_objects_v2() + delete_object() | DELETE /files/{fileId} |

All functions: Python 3.11, x86_64, no VPC attachment, X-Ray PassThrough, shared IAM execution role.

---

## Service Mapping — AWS to Azure

| AWS Service | Azure Equivalent | Mapping Notes |
|-------------|-----------------|---------------|
| AWS Lambda (Python 3.11) | Azure Functions (Python 3.11, Flex Consumption or Consumption plan) | Function signatures differ: `def main(req: func.HttpRequest)` vs Lambda handler. boto3 → azure-storage-blob SDK. |
| API Gateway REST (Regional) | Azure API Management (APIM) or Azure Functions HTTP triggers | APIM provides full feature parity. Simple case can use Function HTTP triggers directly with custom routing. |
| AWS IAM Auth / SigV4 | Azure Entra ID (MSAL) + APIM policy OR Azure SAS tokens | IAM user static key authentication must be replaced. SAS tokens for storage; Entra ID for API auth. |
| S3 (image bucket, private, versioned) | Azure Blob Storage (Standard LRS, versioning enabled) | Container = Bucket. Blob = Object. SAS token = pre-signed URL. Object tags = Blob metadata/tags. |
| S3 (website bucket, public, HTTP) | Azure Static Web Apps (HTTPS, free tier) | Azure Static Web Apps provides HTTPS by default, CI/CD, and global CDN. |
| IAM Role + inline policy | Azure Managed Identity + RBAC (Storage Blob Data Contributor) | No code changes needed; SDK uses DefaultAzureCredential. |
| IAM User (static key) | Remove; replace with Managed Identity + SAS | Static long-lived credentials in the browser are a security anti-pattern. |
| CloudFormation | Azure Bicep (already in bicep-templates/) | Bicep templates are already authored in this workspace. |
| CloudWatch Logs | Azure Monitor / Application Insights | Application Insights SDK auto-captures function logs and metrics. |
| CloudWatch Alarms | Azure Monitor Metric Alerts | Simple threshold alerts map directly. |
| KMS (AWS-managed) | Azure Key Vault (service-managed keys) | No customer key management required; Azure Storage encrypts at rest by default. |

---

## Complexity Assessment

### By Service

| Component | Migration Complexity | Effort (Days) | Blocking Dependencies | Notes |
|-----------|---------------------|---------------|----------------------|-------|
| Storage (Bicep) | LOW | 0.5 | None | Bicep template already exists |
| S3 data migration | LOW | 0.5 | Storage account created | AzCopy from S3 to Blob Storage |
| IAM → Managed Identity | LOW | 0.5 | Storage, Functions deployed | Assign RBAC roles |
| Lambda → Azure Functions (code) | MEDIUM | 3 | Storage | boto3 → azure-storage-blob; handler signature change; SAS token generation differs |
| API Gateway → APIM / Function routes | MEDIUM | 2 | Functions | Route mapping is straightforward; CORS config must be replicated; AUTH model change |
| Authentication refactor (IAM key → SAS/Entra) | MEDIUM | 2 | Functions + APIM | Main security improvement; requires frontend SPA changes |
| Static website → Azure Static Web Apps | LOW | 0.5 | APIM URL | Update API endpoint URL in frontend JS; redeploy |
| Observability (CloudWatch → App Insights) | LOW | 0.5 | Functions deployed | Add APPLICATIONINSIGHTS_CONNECTION_STRING env var |
| Bicep deployment validation | LOW | 0.5 | All above | Validate existing bicep-templates/ against discovered resources |
| Testing & smoke validation | MEDIUM | 2 | All above | End-to-end upload/list/view/delete test suite |
| Legacy cleanup (AppStream buckets, old logs) | LOW | 0.5 | Independent | Optional; can be done post-migration |
| **Total** | **LOW** | **10.5–12 days** | | |

### Complexity Scoring

- Lambda functions: 4 × 2 = 8 points (SDK rewrite required)
- API Gateway: 1 × 3 = 3 points (route mapping + auth)
- S3 buckets (active): 2 × 2 = 4 points
- IAM: 1 × 2 = 2 points
- CloudFormation: 1 × 1 = 1 point (Bicep already exists)

**Total: 18 points ÷ 2 = ~2 weeks (LOW)**

---

## Risk Assessment

### High Risk

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Authentication model change (IAM user key → Managed Identity / SAS) | HIGH — entire auth flow must change, including frontend JS | CERTAIN | Design Azure SAS token generation as a new Azure Function endpoint; update frontend to call it before upload |
| Pre-signed URL logic (boto3 → Azure SAS) | HIGH — core upload and view functionality | HIGH | `generate_presigned_post()` maps to `BlobClient.generate_sas()` with read/write permissions; test SAS expiry and CORS behavior carefully |

### Medium Risk

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| CORS configuration on Azure | MEDIUM — browser will block cross-origin requests if misconfigured | MEDIUM | Test CORS rules on Azure Blob Storage and APIM/Function; mirror the current wildcard origin policy |
| API Gateway HTTP routes not perfectly mapped | MEDIUM — endpoints fail if paths differ | LOW | Routes are simple (4 functions); document the mapping and test each endpoint |
| S3 object key format (fileId/filename) | LOW — existing data must remain accessible if migrating live data | LOW | Blob container uses the same key scheme; AzCopy preserves keys |

### Low Risk

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Python runtime differences | LOW | LOW | Python 3.11 is supported on Azure Functions v4; boto3 removal is the main change |
| CloudFormation stack drift | LOW | LOW | Stack is CREATE_COMPLETE with no manual changes detected; template matches codebase |
| Legacy AppStream resources | LOW | N/A | Simply delete AppStream buckets and alarms post-migration |

---

## Security Observations

> ⚠️ These items should be remediated during migration, not ported as-is.

1. **HIGH — Static IAM access key in browser SPA**: The `image-upload-api-user` IAM user's access key is embedded in the SPA to sign API requests. This is a security anti-pattern. **Recommendation:** Replace with an Azure Function that generates short-lived SAS tokens, or use Azure AD authentication with MSAL.

2. **MEDIUM — HTTP-only static website**: The S3 website bucket serves content over plain HTTP with no CloudFront. **Recommendation:** Azure Static Web Apps enforces HTTPS by default — this is automatically resolved by migration.

3. **MEDIUM — TLS 1.0 on API Gateway**: The API Gateway security policy is `TLS_1_0`. **Recommendation:** Azure APIM uses TLS 1.2/1.3 by default — automatically resolved.

4. **LOW — Orphaned CloudFormation stack secret in outputs**: The CloudFormation stack output `ApiUserSecretAccessKey` contains a plaintext IAM secret access key. This output should be rotated and the value purged from CloudFormation outputs. **Note:** This value has NOT been included in any migration artifact file.

---

## Recommended Migration Strategy

### Approach: Lift-and-Modernise (single phase)

Given the small scope and clean architecture, a single-phase lift-and-modernise is recommended over phased migration. The Bicep templates are already drafted in `bicep-templates/`, significantly reducing infrastructure work.

### Migration Phases

#### Phase 1: Infrastructure Provisioning (Days 1–2)
- Deploy Azure resource group, Storage Account (Blob), Static Web App, Function App, APIM using `bicep-templates/main.bicep`
- Configure Managed Identity on Function App
- Assign `Storage Blob Data Contributor` RBAC role to Function App managed identity
- Validate connectivity: Function App can read/write Blob Storage

#### Phase 2: Code Migration — Lambda → Azure Functions (Days 3–6)
- Refactor each Lambda handler to Azure Function HTTP trigger:
  - Replace `boto3.client('s3')` with `BlobServiceClient` from `azure-storage-blob`
  - Replace `generate_presigned_post()` with `generate_sas()` (BlobSasPermissions.write)
  - Replace `generate_presigned_url('get_object')` with `generate_sas()` (read)
  - Replace `list_objects_v2()` with `container_client.list_blobs()`
  - Replace `head_object()` with `blob_client.get_blob_properties()`
  - Replace `delete_object()` with `blob_client.delete_blob()`
  - Use `DefaultAzureCredential` instead of implicit role assumption
- Update `requirements.txt`: remove boto3, add azure-storage-blob, azure-identity
- Unit test each function locally with `func start`

#### Phase 3: API Layer & Authentication (Days 7–8)
- Configure Azure Function HTTP routes to match existing API paths:
  - `POST /upload`, `GET /files`, `GET /files/{fileId}/view-url`, `DELETE /files/{fileId}`
- Configure CORS on Function App (match current wildcard or restrict to Static Web App origin)
- Replace IAM user static key authentication with:
  - Option A (recommended): Azure Entra External ID / B2C for user identity
  - Option B (simpler, lower friction): SAS token vending endpoint on the Function App
- Update APIM policies if APIM is used for routing

#### Phase 4: Frontend & Observability (Days 9–10)
- Update `app.html` SPA:
  - Replace AWS SDK SigV4 signing with standard `fetch()` calls (if auth is SAS-based)
  - Update API base URL to Azure Function / APIM URL
- Deploy updated frontend to Azure Static Web App
- Add Application Insights connection string to Function App env vars
- Validate CloudWatch → Application Insights log forwarding

#### Phase 5: Validation & Cutover (Days 11–12)
- End-to-end test: upload a file, list files, view URL, delete file
- Validate CORS behavior in browser
- Update DNS / URL references (if any external consumers)
- Decommission AWS resources (after validation period):
  - Delete CloudFormation stack `image-upload`
  - Delete AppStream legacy resources
  - Delete orphaned CloudWatch log groups

---

## Estimated Timeline

| Phase | Duration | Key Deliverable |
|-------|----------|-----------------|
| Phase 1: Infrastructure | 2 days | Azure resources deployed |
| Phase 2: Code migration | 4 days | Azure Functions operational |
| Phase 3: API + Auth | 2 days | Endpoints accessible, auth working |
| Phase 4: Frontend + Observability | 2 days | SPA deployed, logs flowing |
| Phase 5: Validation + Cutover | 2 days | AWS decommissioned |
| **Total** | **~12 working days** | **Migration complete** |

**Recommended team:** 1 senior engineer (full-time) + 1 reviewer for security/testing.

---

## Azure Target Architecture

```
[Browser]
    ↓ HTTPS
[Azure Static Web Apps]   ←  frontend SPA (app.html)
    ↓ HTTPS (fetch / MSAL)
[Azure API Management]   ←  route: POST /upload, GET /files, GET/DELETE /files/{fileId}
    ↓ HTTP
[Azure Functions (Python 3.11, Consumption)]
    ├── upload_function      → BlobSasPermissions.WRITE → [Azure Blob Storage]
    ├── list_function        → list_blobs() + SAS read  → [Azure Blob Storage]
    ├── view_url_function    → get_blob_properties() + SAS read → [Azure Blob Storage]
    └── delete_function      → delete_blob()            → [Azure Blob Storage]

[Azure Blob Storage]   ← private container, versioning, CORS configured
    ↑
[Managed Identity] ← assigned to Function App; RBAC: Storage Blob Data Contributor
[Application Insights] ← telemetry from Functions + APIM
[Azure Key Vault] ← optional; store connection strings and config
```

---

## Pre-existing Azure Work

The following Azure artifacts are already present in this workspace and should be reviewed/validated against the discovered AWS architecture:

| Artifact | Location | Status |
|----------|----------|--------|
| Bicep main template | `bicep-templates/main.bicep` | Exists — review modules for completeness |
| Bicep modules | `bicep-templates/modules/` | functions, keyvault, monitoring, staticweb, storage, apim |
| Bicep parameters | `bicep-templates/parameters/dev.bicepparam` | Exists |
| Azure Functions Python | `outputs/azure-functions/function_app.py` | Exists — validate against discovered handlers |
| Azure architecture diagram | `outputs/azure-architecture-output/architecture-diagram-azure.mmd` | Exists |
| Service mapping | `outputs/azure-architecture-output/service-mapping.md` | Exists |
| Cost comparison | `outputs/azure-architecture-output/cost-comparison.md` | Exists |

---

## Next Steps

1. **Review Bicep templates** (`bicep-templates/`) against this assessment — ensure all discovered resources have Azure equivalents
2. **Review `outputs/azure-functions/function_app.py`** against the 4 Lambda handlers documented here
3. **Design authentication replacement** — determine SAS-token vending vs. Entra External ID approach
4. **Execute Phase 1** — deploy Azure infrastructure via Bicep
5. **Rotate the IAM user access key** (`image-upload-api-user`) discovered in the AWS account as a security hygiene step, regardless of migration timeline

---

**Prepared by:** AWS Discovery Agent  
**Confidence Level:** HIGH — All resources discovered via live AWS API calls; source code inspected.  
**Validation Required:** Human architect review recommended before execution.  
**IMPORTANT:** No changes were made to the AWS environment during this discovery. This is a read-only assessment.
# AWS to Azure Migration Assessment

**Assessment Date:** 2026-04-14  
**AWS Account:** 535002891143  
**Primary Region:** ap-southeast-2 (Sydney, Australia)  
**Assessed By:** AWS Discovery Agent  
**Discovery User:** sinan.nar@arinco.co.nz  

---

## Executive Summary

Account `535002891143` runs a **single serverless application** — an Image Upload Service — deployed entirely via AWS CloudFormation in `ap-southeast-2`. The architecture is clean and modern (Lambda + API Gateway + S3), with no databases, no containers, and no complex networking. This is one of the simplest possible migration candidates.

Additionally, there are orphaned resources from a decommissioned **AppStream 2.0** deployment (June 2025) that should be cleaned up before or during migration.

| Item | Value |
|------|-------|
| **Total Active Resources** | ~18 (application) + ~8 (AppStream remnants) |
| **Active AWS Services** | Lambda, API Gateway, S3, IAM, CloudWatch, KMS, CloudFormation |
| **Deployment Method** | AWS CloudFormation (template saved) |
| **Application Pattern** | Serverless REST API + Static Website |
| **Overall Complexity** | **LOW** |
| **Estimated Migration Effort** | **2–3 weeks** (1–2 engineers) |
| **Recommended Azure Region** | Australia East (matches ap-southeast-2) |

---

## Application Architecture Overview

The **Image Upload Service** is a serverless web application that allows users to upload, view, list, and delete images stored in S3. The frontend is a static HTML/JS app hosted on S3. All API calls use AWS SigV4 IAM authentication.

```
Browser → S3 Static Website (app.html)
       → API Gateway (IAM Auth / SigV4)
            → POST   /upload                  → UploadFunction (Lambda)    → S3 ImageBucket (pre-signed PUT URL)
            → GET    /files                   → ListFilesFunction (Lambda) → S3 ImageBucket (list objects)
            → GET    /files/{fileId}/view-url → GetViewUrlFunction (Lambda)→ S3 ImageBucket (pre-signed GET URL)
            → DELETE /files/{fileId}          → DeleteFileFunction (Lambda)→ S3 ImageBucket (delete object)
```

**Key design characteristics:**
- Pre-signed URLs: Clients upload/download directly to/from S3 — Lambda only generates the URL
- IAM Auth: API calls require AWS SigV4 signed requests (access key + secret)
- No VPC: Lambda functions run in AWS-managed network, no private endpoints
- No database: All state stored in S3 object metadata

---

## Service Complexity Matrix

| AWS Service | Resources | Azure Equivalent | Complexity | Effort (Days) | Notes |
|-------------|-----------|-----------------|------------|---------------|-------|
| Lambda (Python 3.11) | 4 functions | Azure Functions (Python 3.11) | **LOW** | 3 | Code changes limited to SDK (boto3 → azure-blob-storage) and SAS URL generation |
| API Gateway REST | 1 API, 4 routes, 1 stage | Azure API Management (Consumption) or Azure Functions HTTP triggers | **LOW** | 2 | IAM auth → APIM policy / key-based; CORS config must be replicated |
| S3 (image store) | 1 bucket | Azure Blob Storage | **LOW** | 1 | Versioning → Blob versioning; CORS config → Blob service CORS |
| S3 (static website) | 1 bucket | Azure Static Web Apps | **LOW** | 1 | Static website hosting maps directly |
| IAM Roles | 2 app roles | Azure Managed Identity + RBAC | **LOW** | 1 | LambdaExecutionRole → Managed Identity with Storage Blob Data Contributor |
| IAM Users | 1 service user | Azure Service Principal / Entra ID App Registration | **LOW** | 1 | API user access key → SP client credential or Managed Identity |
| CloudFormation | 1 stack | Bicep (or Terraform) | **LOW** | 3 | Template is clean; ~250 lines; straightforward conversion |
| CloudWatch Logs | 8 log groups | Azure Monitor / Log Analytics | **LOW** | 1 | Built-in with Azure Functions; Application Insights for APM |
| KMS Key | 1 key | Azure Key Vault | **LOW** | 0.5 | Likely AppStream-related; may not need active migration |
| **AppStream remnants** | 8 orphaned resources | N/A (delete) | **NONE** | 0.5 | Clean up before/during migration |
| **Total** | **~26 resources** | | **LOW** | **~13–14 days** | **Recommend: 2–3 weeks for 1–2 engineers** |

---

## Critical Path Analysis

### Phase 0: Pre-Migration Cleanup (Day 1 — 0.5 days)
> **Goal:** Remove AppStream remnants to reduce noise

- [ ] Delete CloudWatch alarms: `Appstream2-ExampleStack-fleet-default-scale-in-Alarm`, `Appstream2-ExampleStack-fleet-default-scale-out-Alarm`
- [ ] Empty and delete S3 buckets: `appstream-app-settings-*`, `appstream2-36fb080bb8-*`
- [ ] Delete IAM roles: `AmazonAppStreamPCAAccess`, `AmazonAppStreamServiceAccess`, `ApplicationAutoScalingForAmazonAppStreamAccess`
- [ ] Delete orphaned CloudWatch log groups (legacy Lambda/API GW logs from deleted stacks)

### Phase 1: Azure Infrastructure (Days 1–3)
> **Goal:** Provision Azure foundation

- [ ] Create Azure Resource Group in `australiaeast`
- [ ] Create Azure Storage Account + Blob Container (image storage, versioning enabled, CORS configured)
- [ ] Create Azure Static Web Apps resource (or Blob Storage static website)
- [ ] Create System-Assigned Managed Identity for Functions
- [ ] Assign `Storage Blob Data Contributor` RBAC role to Managed Identity on storage container
- [ ] Create Azure API Management (Consumption tier) with subscription key auth
- [ ] Create Azure Key Vault (if KMS key migration required)

### Phase 2: Function Code Migration (Days 4–7)
> **Goal:** Port 4 Lambda functions to Azure Functions

- [ ] **UploadFunction** → Azure Function (HTTP trigger, POST /upload)
  - Replace `boto3.client('s3').generate_presigned_url('put_object')` with Azure Blob SAS URL generation
  - Use `azure-storage-blob` SDK with `BlobSasPermissions(write=True)`
- [ ] **ListFilesFunction** → Azure Function (HTTP trigger, GET /files)
  - Replace `s3.list_objects_v2(Bucket, Prefix)` with `container_client.list_blobs(name_starts_with=prefix)`
- [ ] **GetViewUrlFunction** → Azure Function (HTTP trigger, GET /files/{fileId}/view-url)
  - Replace `generate_presigned_url('get_object')` with `generate_sas()` + `BlobSasPermissions(read=True)`
- [ ] **DeleteFileFunction** → Azure Function (HTTP trigger, DELETE /files/{fileId})
  - Replace `s3.delete_object()` with `blob_client.delete_blob()`
- [ ] Update environment variables: `BUCKET_NAME` → `STORAGE_ACCOUNT_NAME` + `CONTAINER_NAME`
- [ ] Remove `URL_EXPIRATION` env var → pass expiry as integer to SAS generation

### Phase 3: API & Auth Migration (Days 8–10)
> **Goal:** Replicate API Gateway routing and authentication

- [ ] Configure Azure APIM routes matching AWS API Gateway structure:
  - `POST /upload`, `GET /files`, `GET /files/{fileId}/view-url`, `DELETE /files/{fileId}`
- [ ] Configure CORS in APIM (matching current S3 CORS wildcard config)
- [ ] Replace AWS IAM / SigV4 auth with APIM subscription key or Entra ID app registration
- [ ] Update frontend `app.html` to:
  - Point to Azure APIM endpoint URL
  - Use new auth mechanism (subscription key header or bearer token)
  - Replace AWS SigV4 signing logic with new auth

### Phase 4: IaC Conversion (Days 11–13)
> **Goal:** Convert CloudFormation to Bicep for repeatable deployments

- [ ] Convert `cloudformation-template.yaml` to Bicep modules:
  - `storage.bicep` (Blob Storage account + container)
  - `functions.bicep` (Function App + 4 functions)
  - `apim.bicep` (API Management + routes)
  - `staticweb.bicep` (Static Web Apps)
  - `iam.bicep` (Managed Identity + RBAC)
- [ ] Deploy IaC to Azure and verify all resources are provisioned correctly

### Phase 5: Testing & Cutover (Days 14–15)
> **Goal:** Validate and go live

- [ ] End-to-end testing: upload, list, view URL, delete
- [ ] Performance testing: compare pre-signed/SAS URL generation latency
- [ ] Decommission AWS CloudFormation stack `image-upload` (delete stack to clean all resources)
- [ ] Update any client applications pointing to old API Gateway URL

---

## Risk Assessment

### Low Risk Items

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Pre-signed URL → SAS URL logic change | Medium | Medium | Boto3 and azure-blob-storage have equivalent APIs; unit test both |
| AWS SigV4 auth → Azure auth model | Medium | Medium | Frontend JS must be updated; well-documented migration path |
| CORS configuration | Low | Low | APIM and Blob Storage both support CORS; copy exact config |
| CloudFormation → Bicep conversion | Low | Low | Template is clean and small (~250 lines); use Bicep transformation tools |

### No High/Critical Risks Identified
This migration is low-risk because:
- **No database migration** — all data is in S3 (migrated as blob copy)
- **No VPC/network complexity** — Lambda functions have no VPC attachment
- **No stateful services** — no RDS, no ElastiCache, no DynamoDB
- **Small codebase** — 4 Lambda functions, all < 2KB of code
- **Modern runtime** — Python 3.11 is supported natively by Azure Functions

---

## AWS → Azure Service Mapping

| AWS Service | AWS Resource | Azure Equivalent | Azure Resource Type |
|-------------|-------------|-----------------|---------------------|
| Lambda | 4x Python 3.11 functions | Azure Functions | `Microsoft.Web/sites` (kind: functionapp) |
| API Gateway REST | 1x Regional REST API | Azure API Management (Consumption) | `Microsoft.ApiManagement/service` |
| S3 (private) | ImageBucket | Azure Blob Storage | `Microsoft.Storage/storageAccounts` |
| S3 (static website) | WebsiteBucket | Azure Static Web Apps | `Microsoft.Web/staticSites` |
| IAM Role | LambdaExecutionRole | Managed Identity + RBAC | `Microsoft.ManagedIdentity/userAssignedIdentities` |
| IAM User (API access key) | image-upload-api-user | Entra ID Service Principal | App Registration + Client Secret |
| CloudWatch Logs | Lambda + API GW log groups | Azure Monitor / Log Analytics + App Insights | `Microsoft.Insights/components` |
| X-Ray Tracing (API GW stage) | Tracing enabled | Application Insights Distributed Tracing | Built into App Insights |
| KMS | 1 managed key | Azure Key Vault | `Microsoft.KeyVault/vaults` |
| CloudFormation | image-upload stack | Bicep | `.bicep` templates |
| AWS Organizations | Service-linked role | Microsoft Entra / Azure Management Groups | N/A (no migration needed) |

---

## Data Migration

| Dataset | Volume | Migration Method | Estimated Time |
|---------|--------|-----------------|----------------|
| S3 ImageBucket objects | Unknown (not measured) | AzCopy with S3 source | < 1 hour (typical) |
| S3 WebsiteBucket (HTML/JS) | < 1 MB | Direct upload to Azure Static Web Apps | Minutes |
| AppStream S3 buckets | Unknown | Delete (no migration needed) | N/A |

**Recommended tool:** `azcopy copy 'https://s3.amazonaws.com/...' 'https://<storage>.blob.core.windows.net/...' --recursive`

---

## Security Improvements Available in Azure

| Current AWS Implementation | Azure Improvement |
|---------------------------|------------------|
| IAM User + long-lived access key for API auth | Replace with Entra ID App Registration (short-lived tokens) or Managed Identity |
| S3 CORS allows `*` origins | Restrict to specific frontend origin in Azure APIM / Blob Storage CORS |
| TLS_1_0 security policy on API Gateway | Azure APIM enforces TLS 1.2+ by default |
| No WAF on API Gateway | Azure APIM supports WAF via Azure Front Door integration |
| Static website bucket with public read policy | Azure Static Web Apps with CDN and built-in HTTPS |

---

## Dependency Groups & Migration Order

```
Order 1 (No dependencies):   Azure Storage Account + Blob Container
Order 1 (No dependencies):   Azure Static Web Apps
Order 2 (Depends on Order 1): Azure Function App + 4 Functions (need storage for backend)
Order 2 (Depends on Order 1): Managed Identity + RBAC assignment (needs storage)
Order 3 (Depends on Order 2): Azure APIM + routes (needs Function App URLs)
Order 3 (Depends on Order 2): Frontend update (needs APIM URL)
Order 4 (After validation):  Decommission AWS stack
```

---

## Recommended Azure Architecture

```
Browser
  │
  ├─→ Azure Static Web Apps (australiaeast)
  │     ├── app.html (frontend)
  │     └── Calls Azure APIM with subscription-key header
  │
  └─→ Azure API Management (Consumption tier, australiaeast)
        ├── POST   /upload              → Azure Function: upload_function
        ├── GET    /files               → Azure Function: list_files_function
        ├── GET    /files/{fileId}/view → Azure Function: get_view_url_function
        └── DELETE /files/{fileId}      → Azure Function: delete_file_function
                                               │
                                               ▼
                                  Azure Blob Storage (australiaeast)
                                  image-container (versioning, private)
                                  (Managed Identity auth)
```

---

## Next Steps

1. **Approve** this assessment with the engineering team
2. **Execute Phase 0** — clean up AppStream remnants (half a day, low impact)
3. **Provision Azure environment** — Resource Group, Storage, Static Web Apps
4. **Port Lambda code** — 4 functions, ~4 days with testing
5. **Configure APIM** — routing + auth + CORS
6. **Convert CloudFormation → Bicep** — use the saved template as input
7. **Run end-to-end tests** on Azure before cutover
8. **Delete CloudFormation stack** `image-upload` after successful validation

---

## Artefact Index

| File | Description |
|------|-------------|
| `migration-artifacts/aws-inventory.json` | Full structured resource inventory |
| `migration-artifacts/architecture-diagram.mmd` | Mermaid architecture diagram |
| `migration-artifacts/dependency-matrix.csv` | Resource dependency relationships |
| `migration-artifacts/cloudformation-template.yaml` | Original CloudFormation template (YAML) |
| `migration-artifacts/migration-assessment.md` | This document |

---

**Prepared by:** AWS Discovery Agent  
**Confidence Level:** High — all resources discovered via live AWS API calls  
**Validation Required:** Human architect review before execution  
