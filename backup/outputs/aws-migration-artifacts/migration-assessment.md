# AWS to Azure Migration Assessment

**Assessment Date:** 2026-06-24
**Account:** 535002891143
**Region:** ap-southeast-2
**Stack:** image-upload (CloudFormation CREATE_COMPLETE)
**Assessed By:** AWS Discovery Agent

---

## Executive Summary

- **Total Resources:** 14 (in migration scope)
- **Services Count:** 6 (Lambda, S3, API Gateway, IAM, CloudWatch, X-Ray)
- **Complexity Rating:** MEDIUM
- **Estimated Effort:** 3–4 weeks (team of 2 engineers)
- **Recommended Approach:** **Replatform** — the application is a clean serverless architecture with no stateful databases, no complex event pipelines, and no VPC networking. A direct replatform to Azure Functions + Azure Blob Storage + Azure API Management (or HTTP-triggered Functions) is achievable with minimal business logic changes. The primary re-engineering effort is the auth model (AWS SigV4 IAM → Azure AD / Managed Identity) and presigned URL pattern (S3 presigned POST/GET → Azure Blob SAS tokens).

---

## Service Complexity Matrix

| Service | Logical ID | Count | Complexity | Effort (Days) | Risk Flags | Azure Equivalent | Notes |
|---|---|---|---|---|---|---|---|
| Lambda | UploadFunction | 1 | Medium | 3 | S3 presigned POST → SAS token; SigV4 CORS headers in presigned POST fields | Azure Functions (HTTP trigger) | Generates presigned POST for direct S3 upload. Must rewrite to generate Azure Blob SAS Upload URL. Boto3 s3v4 config is explicit — SAS generation is different API entirely. |
| Lambda | ListFilesFunction | 1 | Medium | 4 | list_objects_v2 → listBlobs; get_object_tagging → getBlobTags; generate_presigned_url → SAS token per object | Azure Functions (HTTP trigger) | Iterates all objects, fetches metadata+tags per object, generates presigned GET URL for each. Heaviest SDK surface area of the 4 functions. |
| Lambda | GetViewUrlFunction | 1 | Medium | 3 | S3 presigned GET → Azure Blob SAS token; list + head pattern to resolve fileId to S3 key | Azure Functions (HTTP trigger) | Resolves fileId prefix to exact key, then generates presigned URL. Straightforward refactor. |
| Lambda | DeleteFileFunction | 1 | Medium | 2 | delete_object → deleteBlob; boto3 s3v4 SigV4 config explicit | Azure Functions (HTTP trigger) | Simplest function — list prefix then delete matching objects. Low risk. |
| S3 | ImageBucket | 1 | Medium | 2 | S3 presigned URLs (SigV4) → Azure Blob SAS tokens (different algorithm + URL shape); CORS config needed on Blob; object tagging → blob tags | Azure Blob Storage | Core image store. Versioning enabled (map to Blob versioning). SSE-AES256 → Azure Storage SSE (default). CORS rules must be replicated. Public access blocked — maintain on Blob container. |
| S3 | WebsiteBucket | 1 | Low | 1 | S3 static website → Azure Static Web Apps or Blob static website; public read via bucket policy → public access level on container | Azure Static Web Apps or Azure Blob static website + CDN | Hosts frontend SPA (app.html). Currently HTTP-only (no HTTPS). Azure Static Web Apps provides HTTPS + CDN natively. |
| API Gateway | ImageUploadApi | 1 | Medium | 3 | AWS_IAM auth on all routes → must reimplement with Azure AD, APIM policies, or Function-level auth keys; OPTIONS MOCK methods for CORS → replicate in APIM or Functions CORS config | Azure API Management + Azure Functions HTTP triggers (or Functions-only) | Regional REST API with 4 resource paths, X-Ray tracing enabled, full request/response logging. |
| IAM Role | LambdaExecutionRole | 1 | Low | 1 | IAM role + inline S3Access policy → Azure Managed Identity + RBAC (Storage Blob Data Contributor); AWSLambdaBasicExecutionRole → built-in Functions logging | Azure Managed Identity + RBAC | Single shared role for all 4 functions. Recommend per-function managed identities in Azure for least-privilege. |
| IAM User | ApiUser (image-upload-api-user) | 1 | High | 2 | Long-lived IAM access key used by frontend SPA for SigV4 signing → must replace with short-lived credentials or frontend auth flow (Azure AD MSAL, SPA OAuth2) | Azure AD App Registration or Azure Static Web Apps built-in auth | **HIGH RISK:** Long-lived static access key embedded in frontend. Frontend must be refactored to use Azure AD interactive auth or an auth proxy. |
| CloudWatch Logs | 4 Lambda log groups + 1 API GW log group | 5 | Low | 1 | CloudWatch Logs → Azure Monitor Log Analytics / Application Insights; no retention policy set on any group | Azure Monitor (Log Analytics workspace) | No alarms or metric filters configured. Historical logs need not be migrated unless required for audit. |
| X-Ray | Default sampling rule | 1 | Low | 0.5 | X-Ray → Application Insights distributed tracing; Lambda TracingMode=PassThrough means no Lambda segments today | Azure Application Insights | Tracing configured on API GW stage but incomplete (Lambda passthrough). Enabling App Insights SDK in Functions gives full end-to-end traces without extra config. |
| CloudFormation | image-upload stack | 1 | Low | 1 | CloudFormation → Bicep IaC; stack outputs consumed by downstream (ApiUrl, BucketName, WebsiteUrl exports) | Azure Bicep | All resources managed in a single stack. Convert to Bicep with equivalent module structure. |

---

## Resource Detail

### Lambda — UploadFunction

**Type:** AWS Lambda
**ARN:** `arn:aws:lambda:ap-southeast-2:535002891143:function:image-upload-UploadFunction-iIIJ7xiZECuB`
**Region:** ap-southeast-2
**Criticality:** HIGH

#### Configuration
- Runtime: python3.11 / x86_64
- Memory: 256 MB | Timeout: 30 s | Ephemeral Storage: 512 MB
- Handler: `upload_handler.lambda_handler`
- Source: `source-app/app-code/lambda/upload/upload_handler.py`
- Environment Variables: `BUCKET_NAME`, `URL_EXPIRATION`
- No VPC | No Layers | TracingMode: PassThrough

#### Dependencies
**Uses:**
- `image-upload-imagebucket-t8isnbr8sswv` — writes (presigned POST generation via `s3.generate_presigned_post`)
- `image-upload-LambdaExecutionRole-2MhYmRQ3aAnA` — authenticates

**Used By:**
- `image-upload-api (4lrh2l7i86)` — POST /upload — calls

#### Security
- IAM Role: `image-upload-LambdaExecutionRole-2MhYmRQ3aAnA`
- VPC: None
- Security Groups: None
- Encryption: SSE-AES256 on target S3 bucket

#### Migration Notes
- Complexity: **MEDIUM**
- Risk Flags: S3 presigned POST → Azure Blob SAS Upload URL (different API, different signature); `x-amz-tagging` header in presigned POST fields has no direct SAS equivalent — tags must be set separately after upload or via a callback
- Azure Equivalent: Azure Functions (HTTP trigger, Python)
- The presigned POST pattern (direct browser-to-storage upload) can be replicated with Azure Blob SAS tokens using `generate_sas` from `azure-storage-blob`. The client flow is slightly different (single PUT vs. multipart POST form).

---

### Lambda — ListFilesFunction

**Type:** AWS Lambda
**ARN:** `arn:aws:lambda:ap-southeast-2:535002891143:function:image-upload-ListFilesFunction-Pb0dKq9dR0Is`
**Region:** ap-southeast-2
**Criticality:** HIGH

#### Configuration
- Runtime: python3.11 / x86_64
- Memory: 256 MB | Timeout: 30 s | Ephemeral Storage: 512 MB
- Handler: `list_handler.lambda_handler`
- Source: `source-app/app-code/lambda/list/list_handler.py`
- Environment Variables: `BUCKET_NAME`, `URL_EXPIRATION`
- No VPC | No Layers | TracingMode: PassThrough

#### Dependencies
**Uses:**
- `image-upload-imagebucket-t8isnbr8sswv` — reads (`list_objects_v2`, `head_object`, `generate_presigned_url`, `get_object_tagging`)
- `image-upload-LambdaExecutionRole-2MhYmRQ3aAnA` — authenticates

**Used By:**
- `image-upload-api (4lrh2l7i86)` — GET /files — calls

#### Security
- IAM Role: `image-upload-LambdaExecutionRole-2MhYmRQ3aAnA`
- VPC: None

#### Migration Notes
- Complexity: **MEDIUM** (highest SDK surface area)
- Risk Flags: 4 distinct S3 API calls per invocation (`list_objects_v2`, `head_object`, `generate_presigned_url`, `get_object_tagging`) all need Azure SDK equivalents
- Azure Equivalent: Azure Functions (HTTP trigger, Python) using `azure-storage-blob`: `list_blobs`, `get_blob_properties`, `generate_blob_sas`, `get_blob_tags`
- N+1 pattern (head + tags per object) — consider optimising during migration

---

### Lambda — GetViewUrlFunction

**Type:** AWS Lambda
**ARN:** `arn:aws:lambda:ap-southeast-2:535002891143:function:image-upload-GetViewUrlFunction-yMGI9X8Us5Em`
**Region:** ap-southeast-2
**Criticality:** HIGH

#### Configuration
- Runtime: python3.11 / x86_64
- Memory: 256 MB | Timeout: 30 s
- Handler: `view_handler.lambda_handler`
- Source: `source-app/app-code/lambda/view/view_handler.py`
- Environment Variables: `BUCKET_NAME`, `URL_EXPIRATION`
- No VPC | No Layers | TracingMode: PassThrough

#### Dependencies
**Uses:**
- `image-upload-imagebucket-t8isnbr8sswv` — reads (`list_objects_v2`, `head_object`, `generate_presigned_url`)
- `image-upload-LambdaExecutionRole-2MhYmRQ3aAnA` — authenticates

**Used By:**
- `image-upload-api (4lrh2l7i86)` — GET /files/{fileId}/view-url — calls

#### Migration Notes
- Complexity: **MEDIUM**
- Risk Flags: `generate_presigned_url` → `generate_blob_sas` (different parameters and URL format)
- Azure Equivalent: Azure Functions (HTTP trigger, Python)

---

### Lambda — DeleteFileFunction

**Type:** AWS Lambda
**ARN:** `arn:aws:lambda:ap-southeast-2:535002891143:function:image-upload-DeleteFileFunction-EG7Cfj3m2P6f`
**Region:** ap-southeast-2
**Criticality:** HIGH

#### Configuration
- Runtime: python3.11 / x86_64
- Memory: 256 MB | Timeout: 30 s
- Handler: `delete_handler.lambda_handler`
- Source: `source-app/app-code/lambda/delete/delete_handler.py`
- Environment Variables: `BUCKET_NAME` (no URL_EXPIRATION — delete doesn't need it)
- No VPC | No Layers | TracingMode: PassThrough

#### Dependencies
**Uses:**
- `image-upload-imagebucket-t8isnbr8sswv` — writes/deletes (`list_objects_v2`, `delete_object`)
- `image-upload-LambdaExecutionRole-2MhYmRQ3aAnA` — authenticates

**Used By:**
- `image-upload-api (4lrh2l7i86)` — DELETE /files/{fileId} — calls

#### Migration Notes
- Complexity: **MEDIUM** (per skill rules — all Lambda migrations are minimum Medium)
- Risk Flags: boto3 S3 client explicitly sets `s3v4` signature and `virtual` addressing — this detail does not carry to Azure; `delete_blob` replaces `delete_object`
- Azure Equivalent: Azure Functions (HTTP trigger, Python)

---

### S3 — ImageBucket

**Type:** Amazon S3
**ARN:** `arn:aws:s3:::image-upload-imagebucket-t8isnbr8sswv`
**Region:** ap-southeast-2
**Criticality:** CRITICAL

#### Configuration
- Versioning: Enabled
- Public Access: Fully blocked (all 4 flags = true)
- Encryption: SSE-AES256 (server-managed, no CMK)
- CORS: GET, PUT, POST, HEAD, DELETE from * | Expose: ETag, Content-Type, x-amz-* headers | MaxAge: 3000s
- Lifecycle: None configured
- Replication: None
- Static Website: Disabled

#### Dependencies
**Used By:**
- All 4 Lambda functions — reads/writes/deletes

#### Migration Notes
- Complexity: **MEDIUM**
- Risk Flags:
  - **S3 presigned URLs** (SigV4 v4) → Azure Blob SAS tokens — different URL structure, different client-side signing library required in the frontend SPA
  - **CORS configuration** must be replicated on the Azure Blob container (Storage account CORS settings)
  - **Object versioning** → Azure Blob versioning (enable on storage account)
  - **Object tagging** (`x-amz-tagging`, `get_object_tagging`) → Azure Blob Tags (GA feature, similar semantics)
  - **Custom metadata** (`x-amz-meta-*`) → Azure Blob user-defined metadata (identical key-value model)
- Azure Equivalent: Azure Blob Storage (private container, CORS-enabled)

---

### S3 — WebsiteBucket

**Type:** Amazon S3 Static Website
**ARN:** `arn:aws:s3:::image-upload-websitebucket-vd866vxtcs1z`
**Region:** ap-southeast-2
**Criticality:** MEDIUM

#### Configuration
- Static Website: Enabled (index: app.html, error: error.html)
- Versioning: Disabled
- Public Access: Fully open (all 4 flags = false)
- Bucket Policy: `s3:GetObject` Allow for Principal: *
- Encryption: SSE-AES256
- Website URL: `http://image-upload-websitebucket-vd866vxtcs1z.s3-website-ap-southeast-2.amazonaws.com`

#### Migration Notes
- Complexity: **LOW**
- Risk Flags: Currently HTTP-only (S3 website endpoints don't support HTTPS without CloudFront)
- Azure Equivalent: **Azure Static Web Apps** (recommended — includes HTTPS, CDN, custom domain, built-in auth) OR Azure Blob static website ($web container) + Azure CDN
- Migration is primarily deploying app.html and static assets to the new host and updating the API endpoint URL

---

### API Gateway — ImageUploadApi

**Type:** Amazon API Gateway REST API
**ARN:** `arn:aws:apigateway:ap-southeast-2::/restapis/4lrh2l7i86`
**Region:** ap-southeast-2
**Criticality:** HIGH

#### Configuration
- Type: Regional REST API
- Stage: `dev` — tracing enabled, full metrics, DataTrace logging (INFO)
- Auth: `AWS_IAM` on all functional methods (POST /upload, GET /files, GET /files/{fileId}/view-url, DELETE /files/{fileId})
- CORS: MOCK OPTIONS method on each resource path
- Throttling: Burst 5000 / Rate 10000 RPS
- Base URL: `https://4lrh2l7i86.execute-api.ap-southeast-2.amazonaws.com/dev`

#### Migration Notes
- Complexity: **MEDIUM**
- Risk Flags:
  - **AWS_IAM authorizer** — there is no direct Azure equivalent. Options: (a) Azure APIM with JWT policy, (b) Azure Functions with Azure AD auth, (c) API key via APIM subscription
  - **CORS OPTIONS MOCK methods** — must replicate via APIM CORS policy or Functions CORS config
  - **DataTrace logging** (full request/response body) — replicate via APIM diagnostic settings
  - **X-Ray stage tracing** → Application Insights end-to-end tracing
- Azure Equivalent: Azure API Management (consumption tier) fronting Azure Functions, OR Azure Functions with HTTP triggers directly (simpler but loses centralised logging/auth layer)

---

### IAM — LambdaExecutionRole

**Type:** AWS IAM Role
**ARN:** `arn:aws:iam::535002891143:role/image-upload-LambdaExecutionRole-2MhYmRQ3aAnA`
**Criticality:** HIGH

#### Configuration
- Trust: `lambda.amazonaws.com`
- Managed Policies: `AWSLambdaBasicExecutionRole` (CloudWatch Logs write)
- Inline Policy `S3Access`: PutObject, PutObjectTagging, GetObject, GetObjectTagging, DeleteObject, ListBucket on `image-upload-imagebucket-t8isnbr8sswv`

#### Migration Notes
- Complexity: **LOW**
- Azure Equivalent: Azure Managed Identity assigned to each Function App
- Recommended: Create one system-assigned managed identity per Function App (4 total) rather than one shared identity — follows least-privilege principle
- RBAC Role: `Storage Blob Data Contributor` on the Azure Blob Storage container

---

### IAM — ApiUser

**Type:** AWS IAM User
**ARN:** `arn:aws:iam::535002891143:user/image-upload-api-user`
**Criticality:** MEDIUM

#### Configuration
- Inline Policy: `execute-api:Invoke` on `4lrh2l7i86/*`
- Active Access Key: `AKIAXZEFIIOD2OIWPRPK` (created 2026-01-14, never rotated)
- Purpose: Frontend SPA signs API requests with SigV4 using these long-lived credentials

#### Migration Notes
- Complexity: **HIGH** (security concern)
- Risk Flags:
  - **Long-lived static credential** in frontend SPA — significant security risk; likely embedded in JavaScript
  - No equivalent IAM user pattern exists in Azure for end-user-facing apps
- Azure Equivalent: Azure AD App Registration (SPA flow) with MSAL.js, or Azure Static Web Apps built-in authentication provider
- **Action Required:** Frontend must be refactored to use short-lived tokens. The access key pattern must not be replicated in Azure.

---

## Dependency Risk Analysis

### Critical Path Resources
1. **IAM Role / Managed Identity** — must exist before Lambda / Azure Functions can access storage
2. **S3 ImageBucket / Azure Blob Storage** — must exist before any Lambda function can run
3. **Lambda Functions / Azure Functions** — must be deployed before API Gateway routes can be tested
4. **API Gateway / Azure APIM** — deployed last; depends on all compute and storage being ready

### Cross-Service Dependency Chains
```
Frontend SPA (WebsiteBucket)
  → IAM User (SigV4 auth)
    → API Gateway (4lrh2l7i86)
      → Lambda UploadFunction → S3 ImageBucket (presigned POST)
      → Lambda ListFilesFunction → S3 ImageBucket (list + presigned GET + tags)
      → Lambda GetViewUrlFunction → S3 ImageBucket (presigned GET)
      → Lambda DeleteFileFunction → S3 ImageBucket (delete)
```

### Key Risk: Presigned URL / SAS Token Pattern
The entire application is built around client-side direct upload/download via pre-authorised URLs:
- **Upload:** Browser calls UploadFunction → gets presigned POST URL → POSTs file directly to S3
- **View/List:** Browser calls ListFilesFunction/GetViewUrlFunction → gets presigned GET URL → fetches file directly from S3

This pattern works identically in Azure with SAS tokens, **but** the URL structure, fields, and signature are completely different. Any hardcoded expectations about `x-amz-*` headers or signature format in the frontend must be updated.

### Network Isolation
- No VPC configured — all Lambda functions run in the public AWS network
- Azure equivalent: Azure Functions consumption plan (no VNET injection required)
- **Low risk** — no VPN/ExpressRoute needed

---

## Migration Phases (Recommended)

Dependencies before dependents:

### Phase 1 — Security & Identity (Day 1–2)
- Create Azure resource group
- Create Azure Managed Identities for each Function App
- Configure Azure AD App Registration for frontend SPA authentication (replaces IAM user)
- Create RBAC role assignments (Storage Blob Data Contributor)

### Phase 2 — Storage (Day 2–4)
- Create Azure Storage Account (ap-southeast-2 → australiasoutheast)
- Create Blob containers: `images` (private), `$web` (public static website)
- Enable Blob versioning (replaces S3 versioning)
- Configure CORS on Storage Account (replicate S3 CORS rules)
- Enable blob tags (replaces S3 object tagging)
- Deploy frontend SPA to `$web` container OR Azure Static Web Apps

### Phase 3 — Compute (Day 4–10)
- Create Azure Function App (Python 3.11, Consumption plan)
- Refactor 4 Lambda functions to Azure Functions:
  - `upload_handler.py` → HTTP-triggered Function: generate Blob SAS Upload URL
  - `list_handler.py` → HTTP-triggered Function: list blobs + SAS GET URLs + blob tags
  - `view_handler.py` → HTTP-triggered Function: resolve blobId + SAS GET URL
  - `delete_handler.py` → HTTP-triggered Function: delete blob by prefix
- Configure Application Settings: `BLOB_CONTAINER_NAME`, `URL_EXPIRATION`, `STORAGE_ACCOUNT_NAME`
- Enable Application Insights on Function App

### Phase 4 — API Layer (Day 10–14)
- Deploy Azure API Management (Consumption tier) OR configure Function HTTP triggers with CORS
- Define API routes matching existing API Gateway paths
- Configure authentication (Azure AD JWT policy or function-level auth)
- Configure CORS (replace OPTIONS MOCK methods)
- Configure diagnostic logging (replace DataTrace logging)
- Update frontend SPA with new API base URL

### Phase 5 — Monitoring (Day 14–16)
- Create Log Analytics workspace
- Configure Application Insights
- Create Azure Monitor alerts (Lambda error rate → Function failure alert)
- Replicate relevant CloudWatch log queries as KQL queries

### Phase 6 — IaC & CI/CD (Day 16–20)
- Convert CloudFormation template to Bicep modules
- Create GitHub Actions pipeline for infrastructure + Function deployment
- Configure OIDC workload identity federation (replace static AWS access keys)

---

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| S3 presigned URL → SAS token pattern change | High | High | Refactor all 4 Lambda functions and update frontend SPA to handle SAS token URL format |
| AWS_IAM auth (SigV4) → Azure AD auth | High | High | Implement Azure AD App Registration + MSAL.js in frontend SPA; replace API GW AWS_IAM with Azure AD JWT validation |
| Long-lived IAM access key in frontend | High | Critical | **Must not replicate in Azure.** Replace with Azure AD interactive auth flow before go-live |
| x-amz-tagging in presigned POST | Medium | Medium | Azure Blob SAS tokens don't support setting tags inline; refactor UploadFunction to set tags via a separate API call after upload confirmation |
| CORS configuration gap | Medium | Medium | Replicate S3 and API GW CORS config on Azure Blob Storage and APIM/Functions |
| No CloudWatch alarms today | Low | Low | No alarms to migrate; add Azure Monitor alerts as a new capability |
| X-Ray tracing incomplete (PassThrough) | Low | Low | Application Insights provides better end-to-end tracing out of the box — net improvement |
| No log retention policy | Low | Low | Set 30-day retention on all Azure Monitor log tables to reduce cost |

---

## Open Questions / Gaps

1. **Frontend auth model decision** — the frontend SPA currently uses long-lived IAM access keys. Does the team want to implement Azure AD interactive login (MSAL.js), or use a simpler auth proxy / API key approach?
2. **Static website hosting** — Azure Static Web Apps (includes HTTPS, CDN, auth) vs. Blob static website + CDN? Static Web Apps is recommended but requires a GitHub/GitLab repo integration for deployment.
3. **API Management tier** — Consumption (pay-per-call, no SLA) vs. Developer/Basic (always-on, SLA)? For a dev environment, Consumption is appropriate.
4. **AppStream resources** — 2 AppStream S3 buckets and 2 CloudWatch alarms exist in the account but are unrelated to the image-upload stack. Confirm with the customer whether AppStream is in scope for a separate migration or can be decommissioned.
5. **Data migration** — Are existing images in `image-upload-imagebucket-t8isnbr8sswv` required to be migrated to Azure Blob Storage, or is a clean-slate deployment acceptable?

---

## Next Steps

1. **azure-architect:** Design Azure architecture mapping the 6 services above to their Azure equivalents; produce `design-document.md` with Bicep module structure and Azure resource naming
2. **azure-architect:** Include frontend auth design decision in `design-document.md` Section 6 (authentication model)
3. **code-refactor:** Refactor 4 Lambda handlers from boto3 to `azure-storage-blob` SDK; replace presigned URL calls with SAS token generation
4. **iac-transformation:** Convert `template.yaml` to Bicep; create modules for storage, function-app, api-management, static-web-app
5. **pipeline-builder-agent:** Create GitHub Actions CI/CD with OIDC workload identity federation for Azure
