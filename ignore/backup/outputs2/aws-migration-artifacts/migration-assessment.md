# AWS Migration Assessment — Image Upload Service

**Account:** 535002891143  
**Region:** ap-southeast-2  
**Stack:** `image-upload` (CloudFormation, CREATE_COMPLETE)  
**Assessment Date:** 2026-06-28  
**Assessed By:** AWS Discovery Agent  

---

## Executive Summary

The Image Upload Service is a **serverless image management platform** built on AWS Lambda, API Gateway, and S3. It exposes a REST API for browser-based clients to upload, list, view, and delete image files. The frontend is a static HTML/JS app served from an S3 website bucket.

The application has **no database layer, no messaging services, and no VPC networking**, making it a **straightforward migration candidate**. The primary complexity points are:

1. **S3 Presigned URLs → Azure SAS Tokens**: All four Lambda functions generate presigned URLs; the client-side upload pattern (presigned POST) requires equivalent Azure Blob Storage SAS token generation.  
2. **IAM SigV4 client authentication → Azure AD / MSAL**: The web client uses a long-lived IAM user access key to sign API requests with AWS Signature Version 4. This pattern must be replaced with Azure AD authentication.  
3. **API Gateway AWS_IAM authorizer → Azure API Management**: The API uses IAM-based request signing for authorization, which has no direct Azure equivalent and requires re-implementation.  
4. **S3 Object Tags for metadata → Blob Storage metadata**: File metadata (description, tags, upload date) is stored as S3 object tags; Azure Blob uses key-value metadata instead.

**Security alert:** An IAM user secret access key is exposed in CloudFormation stack outputs — this must be rotated and removed before or during migration.

---

## Overall Complexity Rating: **MEDIUM**

| Dimension | Rating | Justification |
|---|---|---|
| Architecture complexity | LOW | Serverless, single-region, no VPC, no database |
| Migration complexity | MEDIUM | Auth pattern replacement (SigV4→AAD), presigned URL → SAS token |
| Security remediation | HIGH | IAM key exposure, client-side secret, open CORS |
| Code refactoring effort | MEDIUM | boto3 → Azure SDK; presigned URL logic → SAS token logic |
| IaC re-implementation | LOW–MEDIUM | CloudFormation → Bicep; straightforward resource mapping |

**Estimated total effort: 3–4 weeks** (1 developer, including security fixes)

---

## Service Complexity Matrix

| Service | Resource | Complexity | Effort Estimate | Risk Flags |
|---|---|---|---|---|
| Lambda | UploadFunction | Standard | 3–4 days | Presigned POST → SAS token; metadata tagging |
| Lambda | ListFilesFunction | Standard | 3–4 days | Presigned URL generation; metadata extraction from tags |
| Lambda | GetViewUrlFunction | Basic | 2 days | Presigned URL → SAS token |
| Lambda | DeleteFileFunction | Basic | 2 days | S3 prefix-based delete → Blob delete by prefix |
| S3 | ImageBucket | Standard | 2–3 days | CORS config; versioning; SAS token auth model |
| S3 | WebsiteBucket | Public/static | 2–3 days | Map to Azure Static Web Apps |
| API Gateway | image-upload-api | Standard | 3–4 days | AWS_IAM authorizer → APIM + AAD policy |
| IAM | LambdaExecutionRole | Low | 1 day | Map to Azure Managed Identity + RBAC |
| IAM | ApiUser + AccessKey | High | 2–3 days | Security remediation; replace with AAD auth |
| CloudWatch | Log groups (5) | Low | 0.5 days | Map to Azure Log Analytics |
| CloudFormation | image-upload stack | Medium | 2–3 days | Rewrite in Bicep |
| **TOTAL** | | **MEDIUM** | **~23–30 days** | |

---

## Resource Details

---

### Lambda Function — UploadFunction

**ARN:** `arn:aws:lambda:ap-southeast-2:535002891143:function:image-upload-UploadFunction-iIIJ7xiZECuB`  
**Type:** AWS Lambda  
**Region:** ap-southeast-2  
**Criticality:** HIGH  

#### Configuration
- Runtime: python3.11
- Memory: 256 MB
- Timeout: 30 s
- Handler: `upload_handler.lambda_handler`
- Environment Variables: `BUCKET_NAME`, `URL_EXPIRATION`
- VPC: None
- Layers: None
- Tracing: PassThrough (X-Ray not active)

#### Dependencies
**Uses:**
- `image-upload-imagebucket-t8isnbr8sswv` — writes (presigned POST generation)
- `image-upload-LambdaExecutionRole-2MhYmRQ3aAnA` — authenticates

**Used By:**
- `image-upload-api` — calls (POST /upload)

#### Migration Notes
- Replace `boto3.client('s3').generate_presigned_post()` with Azure Blob Storage SAS token (Service SAS with Write permission)
- S3 object tags (`x-amz-meta-*`) → Azure Blob metadata (`x-ms-meta-*`)
- Replace Lambda with Azure Functions (Python v2 programming model)
- Max 10 MB upload enforced via S3 conditions — replicate as client-side validation or Azure Blob size limit

#### Risk Flags
⚠️ **S3 presigned POST → Azure SAS token**: The presigned POST pattern (client uploads directly to S3) maps to Azure Blob SAS token with Write permission. The URL structure and signing algorithm differ.  
⚠️ **S3 object tags vs Blob metadata**: boto3 `put_object_tagging` must be replaced with Blob metadata or Azure Table Storage for richer querying.

---

### Lambda Function — ListFilesFunction

**ARN:** `arn:aws:lambda:ap-southeast-2:535002891143:function:image-upload-ListFilesFunction-Pb0dKq9dR0Is`  
**Type:** AWS Lambda  
**Region:** ap-southeast-2  
**Criticality:** HIGH  

#### Configuration
- Runtime: python3.11
- Memory: 256 MB
- Timeout: 30 s
- Handler: `list_handler.lambda_handler`
- Environment Variables: `BUCKET_NAME`, `URL_EXPIRATION`
- VPC: None
- Layers: None

#### Dependencies
**Uses:**
- `image-upload-imagebucket-t8isnbr8sswv` — reads (list_objects_v2, head_object, generate_presigned_url)

**Used By:**
- `image-upload-api` — calls (GET /files)

#### Migration Notes
- `s3:ListObjectsV2` → `BlobContainerClient.list_blobs()` in Azure SDK
- `s3:HeadObject` (metadata) → `BlobClient.get_blob_properties()` (returns metadata dict)
- `s3:GetObjectTagging` → Azure Blob metadata (tags not directly equivalent)
- `generate_presigned_url('get_object')` → `generate_sas()` with Read permission

#### Risk Flags
⚠️ **S3 object tags → Blob metadata**: Tags stored at upload time via `s3:PutObjectTagging` must be migrated to Blob metadata; tag query (`get_object_tagging`) must use metadata API.

---

### Lambda Function — GetViewUrlFunction

**ARN:** `arn:aws:lambda:ap-southeast-2:535002891143:function:image-upload-GetViewUrlFunction-yMGI9X8Us5Em`  
**Type:** AWS Lambda  
**Region:** ap-southeast-2  
**Criticality:** MEDIUM  

#### Configuration
- Runtime: python3.11
- Memory: 256 MB
- Timeout: 30 s
- Handler: `view_handler.lambda_handler`
- Environment Variables: `BUCKET_NAME`, `URL_EXPIRATION`
- VPC: None
- Layers: None

#### Dependencies
**Uses:**
- `image-upload-imagebucket-t8isnbr8sswv` — reads (list_objects_v2 by prefix, generate_presigned_url)

**Used By:**
- `image-upload-api` — calls (GET /files/{fileId}/view-url)

#### Migration Notes
- `s3:ListObjectsV2` by prefix → list blobs by virtual directory prefix
- `generate_presigned_url` → `generate_sas(BlobSasPermissions(read=True), expiry=...)`

---

### Lambda Function — DeleteFileFunction

**ARN:** `arn:aws:lambda:ap-southeast-2:535002891143:function:image-upload-DeleteFileFunction-EG7Cfj3m2P6f`  
**Type:** AWS Lambda  
**Region:** ap-southeast-2  
**Criticality:** HIGH  

#### Configuration
- Runtime: python3.11
- Memory: 256 MB
- Timeout: 30 s
- Handler: `delete_handler.lambda_handler`
- Environment Variables: `BUCKET_NAME`
- VPC: None
- Layers: None

#### Dependencies
**Uses:**
- `image-upload-imagebucket-t8isnbr8sswv` — writes (delete_objects by prefix)

**Used By:**
- `image-upload-api` — calls (DELETE /files/{fileId})

#### Migration Notes
- `s3:ListObjectsV2` + `s3:DeleteObjects` (batch) → `ContainerClient.delete_blob()` per blob or batch delete via `BlobBatchClient`
- Objects stored under `{fileId}/filename` prefix — same virtual directory structure works in Azure Blob

---

### S3 Bucket — ImageBucket

**ARN:** `arn:aws:s3:::image-upload-imagebucket-t8isnbr8sswv`  
**Type:** Amazon S3  
**Region:** ap-southeast-2  
**Criticality:** CRITICAL  

#### Configuration
- Versioning: Enabled
- Encryption: SSE-S3 (AES256, server-managed key)
- Public Access: All blocked
- CORS: GET, PUT, POST, HEAD, DELETE allowed from all origins (`*`)
- Max upload size enforced: 10 MB (presigned POST condition)
- No lifecycle policies

#### Dependencies
**Used By:**
- `image-upload-UploadFunction-iIIJ7xiZECuB` — writes
- `image-upload-ListFilesFunction-Pb0dKq9dR0Is` — reads
- `image-upload-GetViewUrlFunction-yMGI9X8Us5Em` — reads
- `image-upload-DeleteFileFunction-EG7Cfj3m2P6f` — writes (delete)

#### Migration Notes
- Azure equivalent: **Azure Blob Storage** (General Purpose v2, Hot tier)
- Versioning → Enable Blob soft delete + versioning on Storage Account
- SSE-S3 → Azure Storage Service Encryption (enabled by default with Microsoft-managed key)
- CORS → Configure CORS rules on Storage Account (restrict `*` to actual frontend origin)
- Consider `$web` container with Static Website enabled for uploads requiring direct browser access

#### Risk Flags
⚠️ **CORS `AllowedOrigins: ['*']`**: Migrate with restricted origins. Azure Blob Storage CORS is configured per-service, not per-container.  
⚠️ **Presigned URL auth model**: All access is through presigned URLs generated by Lambda — no direct IAM bucket access from clients. Replicate with SAS tokens scoped to blob or container.

---

### S3 Bucket — WebsiteBucket (Static Website)

**ARN:** `arn:aws:s3:::image-upload-websitebucket-vd866vxtcs1z`  
**Type:** Amazon S3 (Static Website Hosting)  
**Region:** ap-southeast-2  
**Criticality:** HIGH  

#### Configuration
- Versioning: Not enabled
- Encryption: SSE-S3
- Public Access: NOT blocked (required for public static website)
- Website: index=`app.html`, error=`error.html`
- Bucket Policy: `s3:GetObject` for all principals
- URL: `http://image-upload-websitebucket-vd866vxtcs1z.s3-website-ap-southeast-2.amazonaws.com`

#### Dependencies
**Used By:**
- Browser (end users)

#### Migration Notes
- Azure equivalent: **Azure Static Web Apps** (recommended) or Azure Blob Storage `$web` container
- Azure Static Web Apps provides built-in CI/CD, custom domain, SSL, and global CDN
- The frontend HTML/JS at `source-app/app-code/build/app.html` must be updated to use new Azure API endpoint and AAD auth instead of AWS SigV4

---

### API Gateway — image-upload-api

**ARN:** `arn:aws:apigateway:ap-southeast-2::/restapis/4lrh2l7i86`  
**Type:** Amazon API Gateway (REST)  
**Region:** ap-southeast-2  
**Criticality:** CRITICAL  

#### Configuration
- ID: `4lrh2l7i86`
- Type: REST (not HTTP API v2)
- Endpoint: Regional
- Authorization: `AWS_IAM` on all routes
- Stage: `dev`
- Stage URL: `https://4lrh2l7i86.execute-api.ap-southeast-2.amazonaws.com/dev`
- Tracing: Enabled (AWS X-Ray)
- Logging: INFO level, data trace enabled, metrics enabled
- Routes: POST /upload, GET /files, GET /files/{fileId}/view-url, DELETE /files/{fileId}
- CORS: OPTIONS mock responses on all resources

#### Dependencies
**Uses:**
- `image-upload-UploadFunction-iIIJ7xiZECuB` — calls
- `image-upload-ListFilesFunction-Pb0dKq9dR0Is` — calls
- `image-upload-GetViewUrlFunction-yMGI9X8Us5Em` — calls
- `image-upload-DeleteFileFunction-EG7Cfj3m2P6f` — calls
- `image-upload-ApiGatewayCloudWatchLogsRole-YGFCwY9oRVqq` — authenticates

**Used By:**
- `image-upload-api-user` — authenticates (SigV4)
- Browser (frontend JS)

#### Migration Notes
- Azure equivalent: **Azure API Management** (consumption tier) or **Azure Functions HTTP trigger** directly
- `AWS_IAM` authorizer → Replace with Azure AD JWT validation policy in APIM, or Azure AD B2C
- CORS mock responses → Configure CORS policy natively in APIM
- X-Ray tracing → Azure Application Insights (configure in Azure Functions + APIM)
- Stage naming (`dev`) → APIM environments / subscriptions

#### Risk Flags
⚠️ **AWS_IAM (SigV4) authorization**: The AWS-native request signing has no direct Azure equivalent. Must redesign auth layer using Azure AD, MSAL, or API key. Client code (app.html) requires changes.  
⚠️ **REST API v1 vs HTTP API v2**: This uses the older REST API type. Azure Functions HTTP trigger is closer to HTTP API v2 semantics.

---

### IAM Role — LambdaExecutionRole

**ARN:** `arn:aws:iam::535002891143:role/image-upload-LambdaExecutionRole-2MhYmRQ3aAnA`  
**Type:** AWS IAM Role  
**Criticality:** HIGH  

#### Configuration
- Principal: `lambda.amazonaws.com`
- Managed Policies: `AWSLambdaBasicExecutionRole` (CloudWatch Logs write)
- Inline Policy S3Access:
  - `s3:PutObject`, `s3:PutObjectTagging`, `s3:GetObject`, `s3:GetObjectTagging`, `s3:DeleteObject` on `arn:aws:s3:::image-upload-imagebucket-t8isnbr8sswv/*`
  - `s3:ListBucket` on `arn:aws:s3:::image-upload-imagebucket-t8isnbr8sswv`

#### Migration Notes
- Azure equivalent: **System-assigned Managed Identity** on the Function App
- RBAC assignment: `Storage Blob Data Contributor` role on the Storage Account
- No permission boundary needed (simple single-resource access)

---

### IAM User — image-upload-api-user

**ARN:** `arn:aws:iam::535002891143:user/image-upload-api-user`  
**Type:** AWS IAM User  
**Criticality:** HIGH  

#### Configuration
- Created: 2026-01-14T04:19:39Z
- Inline Policy: `execute-api:Invoke` on all methods of API `4lrh2l7i86`
- Access Key: `AKIAXZEFIIOD2OIWPRPK` (long-lived, permanent)

#### Migration Notes
- **SECURITY RISK — MUST REMEDIATE**: Long-lived IAM user key used for browser-side authentication. Secret key is exposed in CloudFormation outputs.
- Azure replacement: **Azure AD App Registration** + MSAL.js for browser-based auth, or Azure AD B2C for consumer identity
- If keeping simple key-based auth: **Azure API Management subscription key** (not ideal but comparable to current pattern)

#### Risk Flags
🔴 **CRITICAL**: Rotate the IAM access key immediately. Remove from CloudFormation outputs.  
🔴 **CLIENT-SIDE SECRET**: Long-lived AWS access key embedded/accessible in browser client is a severe security anti-pattern. Replace with short-lived tokens (AAD + MSAL).

---

### CloudWatch Log Groups

**ARN Prefix:** `arn:aws:logs:ap-southeast-2:535002891143:log-group:`  
**Type:** Amazon CloudWatch Logs  
**Criticality:** LOW  

#### Configuration
- `/aws/lambda/image-upload-UploadFunction-iIIJ7xiZECuB` — No retention, 1.6 KB stored
- `/aws/lambda/image-upload-ListFilesFunction-Pb0dKq9dR0Is` — No retention, 1.6 KB stored
- `/aws/lambda/image-upload-DeleteFileFunction-EG7Cfj3m2P6f` — No retention, 0.5 KB stored
- `/aws/lambda/image-upload-GetViewUrlFunction-yMGI9X8Us5Em` — No retention
- `API-Gateway-Execution-Logs_4lrh2l7i86/dev` — No retention, 32 KB stored

#### Migration Notes
- Azure equivalent: **Azure Log Analytics Workspace** + Application Insights
- Azure Functions automatically integrates with Application Insights when configured
- Set retention policy on migration (AWS best practice too — currently unset)

---

## Migration Phases

### Phase 1 — Foundation (Days 1–5)
**Goal:** Establish Azure infrastructure baseline

| Task | Effort | Notes |
|---|---|---|
| Create Resource Group, Storage Account (Azure Blob), Function App Plan | 1 day | Bicep/Terraform |
| Configure Managed Identity on Function App | 0.5 day | Replaces LambdaExecutionRole |
| Assign Storage Blob Data Contributor RBAC | 0.5 day | Scoped to Storage Account |
| Create Log Analytics Workspace + Application Insights | 0.5 day | Replaces CloudWatch |
| Create Azure Static Web Apps resource | 0.5 day | Replaces WebsiteBucket |
| Security: Rotate compromised IAM access key | 1 day | Urgent — do before migration |
| Deploy Azure API Management (consumption tier) | 1 day | Replaces API Gateway |

### Phase 2 — Storage Migration (Days 6–10)
**Goal:** Migrate S3 buckets to Azure Blob Storage

| Task | Effort | Notes |
|---|---|---|
| Create `images` container with private access | 0.5 day | Replaces ImageBucket |
| Configure CORS policy (restrict from `*`) | 0.5 day | Security improvement |
| Enable Blob versioning + soft delete | 0.5 day | Replaces S3 versioning |
| Migrate existing S3 objects (if any) via AzCopy | 1–2 days | Data migration |
| Update Blob metadata schema (from S3 object tags) | 1 day | Schema mapping |
| Deploy frontend to Azure Static Web Apps | 0.5 day | |

### Phase 3 — Compute Migration (Days 11–20)
**Goal:** Migrate Lambda functions to Azure Functions

| Task | Effort | Notes |
|---|---|---|
| Scaffold Azure Functions App (Python v2) | 1 day | |
| Migrate UploadFunction → upload_function (SAS token generation) | 3 days | Presigned POST → SAS; boto3 → azure-storage-blob |
| Migrate ListFilesFunction → list_function | 3 days | list_blobs; get_blob_properties; SAS generation |
| Migrate GetViewUrlFunction → view_url_function | 2 days | list_blobs by prefix; generate_sas |
| Migrate DeleteFileFunction → delete_function | 2 days | list_blobs + delete_blob or BlobBatchClient |

### Phase 4 — API Layer Migration (Days 21–25)
**Goal:** Configure API Management and authentication

| Task | Effort | Notes |
|---|---|---|
| Configure APIM routes → Azure Functions HTTP triggers | 2 days | Route definitions |
| Implement AAD authentication policy in APIM | 2 days | Replaces AWS_IAM SigV4 |
| Update frontend (app.html) for new API endpoint + MSAL auth | 2 days | JS code changes |
| Configure CORS in APIM | 0.5 day | |
| Enable Application Insights in APIM + Functions | 0.5 day | |

### Phase 5 — Validation (Days 26–30)
**Goal:** End-to-end testing and cutover

| Task | Effort | Notes |
|---|---|---|
| Integration testing (upload, list, view, delete flows) | 2 days | |
| Security review (credential rotation confirmed, CORS restricted) | 1 day | |
| Performance testing | 1 day | |
| DNS/URL cutover (if custom domain) | 0.5 day | |
| Decommission AWS resources | 0.5 day | After validation |

---

## Risk Register

| ID | Risk | Severity | Likelihood | Mitigation |
|---|---|---|---|---|
| R1 | IAM access key exposed in CloudFormation outputs | CRITICAL | Confirmed | Rotate immediately; use Key Vault on Azure |
| R2 | SigV4 client auth cannot be directly replicated on Azure | HIGH | Confirmed | Replace with MSAL + Azure AD; update frontend |
| R3 | S3 presigned POST has no direct Azure Blob equivalent | HIGH | Confirmed | Use SAS token with Write permission; update client upload logic |
| R4 | S3 object tags → Azure Blob metadata schema mismatch | MEDIUM | Confirmed | Map tags to metadata; test query patterns |
| R5 | No log retention policy (CloudWatch) | LOW | Confirmed | Set retention at migration time |
| R6 | CORS allows all origins (`*`) | MEDIUM | Confirmed | Restrict to known frontend domain at migration |
| R7 | Client-side secret (IAM key in browser) | HIGH | Confirmed | Replace with MSAL short-lived tokens |
| R8 | Frontend app.html hardcodes AWS endpoint URL | HIGH | Likely | Update API base URL + auth headers in JS |

---

## Azure Service Mapping

| AWS Service | Azure Equivalent | Notes |
|---|---|---|
| AWS Lambda (python3.11) | Azure Functions (Python v2) | Near 1:1 for HTTP triggers; boto3 → azure-storage-blob |
| Amazon S3 (ImageBucket) | Azure Blob Storage | Container = Bucket; presigned URL → SAS token |
| Amazon S3 (WebsiteBucket) | Azure Static Web Apps | Built-in CI/CD, CDN, custom domain, SSL |
| Amazon API Gateway REST | Azure API Management (Consumption) | Route definitions, auth policies, CORS |
| AWS IAM Role (Lambda) | Azure Managed Identity + RBAC | No code changes needed for auth |
| AWS IAM User (API client) | Azure AD App Registration + MSAL | Complete redesign of auth pattern |
| Amazon CloudWatch Logs | Azure Log Analytics + App Insights | Integrated in Functions/APIM automatically |
| AWS CloudFormation | Bicep or Terraform | Already partially done in repo |
| AWS X-Ray (PassThrough) | Azure Application Insights | Distributed tracing; auto-instrumented |

---

## Effort Summary

| Phase | Duration | Key Risk |
|---|---|---|
| Phase 1 — Foundation | 5 days | IAM key rotation (security-critical) |
| Phase 2 — Storage | 5 days | S3 tags → Blob metadata |
| Phase 3 — Compute | 10 days | boto3 → azure-storage-blob; SAS token logic |
| Phase 4 — API Layer | 7 days | SigV4 auth replacement (biggest complexity) |
| Phase 5 — Validation | 3 days | End-to-end testing |
| **Total** | **~30 working days** | **~6 calendar weeks (1 developer)** |

**Parallel team estimate:** 2–3 developers → **3–4 calendar weeks**
