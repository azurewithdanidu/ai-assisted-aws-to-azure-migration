# Service Mapping: AWS → Azure — Image Upload Service

**Prepared by:** azure-architect agent  
**Date:** 2026-06-28  
**Source:** `outputs/aws-migration-artifacts/aws-inventory.json`, `migration-assessment.md`  
**Target Azure Region:** australiaeast  

---

## Overview

The Image Upload Service uses 6 AWS service categories mapping to 6 Azure service categories. There is no database layer, no messaging services, and no VPC — making this a clean serverless-to-serverless migration.

| AWS Service Category | Resource Count | Azure Equivalent | Migration Complexity |
|---|---|---|---|
| Lambda | 4 functions | Azure Functions (Consumption plan) | Medium — boto3 → azure-sdk; presigned URL → SAS |
| S3 (private) | 1 bucket | Azure Blob Storage GPv2 | Medium — object tags → blob metadata; CORS config |
| S3 (website) | 1 bucket | Azure Static Web Apps | Low — direct equivalent |
| API Gateway (REST) | 1 API, 8 routes | Azure Functions HTTP triggers (built-in) | Medium — AWS_IAM auth → Azure AD Bearer |
| IAM | 2 roles, 1 user, 1 key | Managed Identity + Azure AD App Registration | High — security remediation required |
| CloudWatch Logs | 5 log groups | Log Analytics Workspace + Application Insights | Low — automatic with Functions |
| CloudFormation | 1 stack | Azure Bicep | Low–Medium — rewrite in Bicep |

---

## Detailed Service Mapping

---

### 1. AWS Lambda → Azure Functions

#### 1.1 UploadFunction

| Attribute | AWS | Azure |
|---|---|---|
| **Service** | AWS Lambda | Azure Functions (Consumption plan) |
| **Runtime** | python3.11 | Python 3.11 |
| **Memory** | 256 MB | Consumption: 1.5 GB max (auto-managed) |
| **Timeout** | 30 s | 230 s max (Consumption) |
| **Handler** | `upload_handler.lambda_handler` | `@app.route(route="upload", methods=["POST"])` in `function_app.py` |
| **Trigger** | API Gateway `POST /upload` (AWS_IAM) | HTTP trigger `POST /api/upload` (ANONYMOUS / Bearer) |
| **Entry point** | `lambda_handler(event, context)` | `upload_function(req: func.HttpRequest) -> func.HttpResponse` |
| **S3 operation** | `generate_presigned_post(Bucket, Key, Fields, Conditions, ExpiresIn)` | `generate_blob_sas(account_name, container_name, blob_name, permission=BlobSasPermissions(write=True, create=True), expiry=..., user_delegation_key=...)` |
| **Metadata storage** | S3 object tags via `x-amz-tagging` / `PutObjectTagging` | Azure Blob metadata (`metadata={'key': 'value'}` on blob properties) |
| **Environment vars** | `BUCKET_NAME`, `URL_EXPIRATION` | `STORAGE_ACCOUNT_NAME` (Key Vault ref), `AZURE_STORAGE_CONTAINER_NAME`, `URL_EXPIRATION` |
| **Auth** | IAM execution role → S3 presigned URL signed with HMAC-SHA256 | `DefaultAzureCredential()` → `get_user_delegation_key()` → user delegation SAS |
| **Monthly cost** | $0.50 | $0.00 (free tier) |

**Migration notes:**
- The presigned POST pattern (client → S3 directly) maps to a Blob SAS token with Write+Create permissions. The client performs a `PUT` to the SAS URL (not a multipart form POST as with S3).
- S3 object tags (`x-amz-tagging`) have no direct equivalent in Azure Blob. Store metadata as blob metadata key-value pairs using the `metadata` parameter.
- The max 10 MB upload condition (`content-length-range`) must be enforced client-side or via Azure Blob `maxSinglePutSize` configuration.

---

#### 1.2 ListFilesFunction

| Attribute | AWS | Azure |
|---|---|---|
| **Service** | AWS Lambda | Azure Functions (Consumption plan) |
| **Trigger** | API Gateway `GET /files` | HTTP trigger `GET /api/files` |
| **Handler** | `list_handler.lambda_handler` | `list_function(req: func.HttpRequest)` |
| **List operation** | `s3_client.list_objects_v2(Bucket=..., MaxKeys=..., Prefix=...)` | `container_client.list_blobs(name_starts_with=prefix, include=['metadata'])` |
| **Metadata read** | `s3_client.head_object(Bucket, Key)` → `.Metadata` dict | `blob.metadata` dict (returned inline with `list_blobs(include=['metadata'])`) |
| **Tag read** | `s3_client.get_object_tagging(Bucket, Key)` → `TagSet` array | `blob.metadata` dict (tags migrated to metadata at upload time) |
| **View URL** | `s3_client.generate_presigned_url('get_object', Params, ExpiresIn)` | `generate_blob_sas(..., permission=BlobSasPermissions(read=True), ...)` |

**Migration notes:**
- `list_blobs(include=['metadata'])` returns metadata inline, eliminating the need for separate `head_object` calls — this is a performance improvement over the AWS implementation.
- The S3 `TagSet` (array of `{Key, Value}` objects) must be mapped to flat metadata keys at upload time. The list function can read from `blob.metadata` directly.

---

#### 1.3 GetViewUrlFunction

| Attribute | AWS | Azure |
|---|---|---|
| **Service** | AWS Lambda | Azure Functions (Consumption plan) |
| **Trigger** | API Gateway `GET /files/{fileId}/view-url` | HTTP trigger `GET /api/files/{fileId}/view-url` |
| **Handler** | `view_handler.lambda_handler` | `view_url_function(req: func.HttpRequest)` |
| **Route params** | `event['pathParameters']['fileId']` | `req.route_params.get('fileId')` |
| **List by prefix** | `s3_client.list_objects_v2(Bucket, Prefix=f"{file_id}/", MaxKeys=1)` | `list(container_client.list_blobs(name_starts_with=f"{file_id}/"))[:1]` |
| **View URL** | `s3_client.generate_presigned_url('get_object', {'Bucket': ..., 'Key': ...}, ExpiresIn)` | `generate_blob_sas(account_name, container_name, blob_name, permission=BlobSasPermissions(read=True), expiry=...)` |

---

#### 1.4 DeleteFileFunction

| Attribute | AWS | Azure |
|---|---|---|
| **Service** | AWS Lambda | Azure Functions (Consumption plan) |
| **Trigger** | API Gateway `DELETE /files/{fileId}` | HTTP trigger `DELETE /api/files/{fileId}` |
| **Handler** | `delete_handler.lambda_handler` | `delete_function(req: func.HttpRequest)` |
| **List by prefix** | `s3_client.list_objects_v2(Bucket, Prefix=f"{file_id}/")` | `container_client.list_blobs(name_starts_with=f"{file_id}/")` |
| **Delete operation** | `s3_client.delete_object(Bucket, Key)` (per-object loop) | `container_client.delete_blob(blob_name)` (per-blob loop) |
| **Batch delete** | `s3_client.delete_objects(Bucket, Delete={'Objects': [...]})` (not used in original) | `BlobBatchClient.delete_blobs(...)` (optional optimization) |

**Migration notes:**
- The original AWS code deletes objects one-by-one in a loop. The Azure implementation can use the same pattern with `container_client.delete_blob()`, or batch via `BlobBatchClient` for performance.

---

#### Common Lambda → Functions Differences

| Aspect | AWS Lambda | Azure Functions |
|---|---|---|
| **Programming model** | Single handler per file; `event`/`context` params | v2 model: `app = func.FunctionApp()`; decorator-based routes |
| **Dependency packaging** | `requirements.txt` in Lambda layer or package | `requirements.txt` in function app root; built at deploy time |
| **Cold start** | ~500ms–2s (Python, 256 MB) | ~500ms–3s (Python, Consumption) |
| **Max execution time** | 30 s (configured) | 230 s (Consumption plan max) |
| **Concurrent executions** | 1,000 (default account limit) | 200 (Consumption plan default) |
| **Logging** | `print()` → CloudWatch Logs | `logging.info()` → Application Insights |
| **Response format** | `{'statusCode': 200, 'headers': {...}, 'body': json.dumps(...)}` | `func.HttpResponse(body=..., status_code=200, mimetype='application/json')` |
| **CORS** | API Gateway CORS mock + Lambda header | `host.json` CORS config + `Access-Control-Allow-Origin` in response |

---

### 2. Amazon S3 (ImageBucket) → Azure Blob Storage

| Attribute | AWS S3 ImageBucket | Azure Blob Storage |
|---|---|---|
| **Service** | Amazon S3 | Azure Blob Storage (GPv2) |
| **Physical name** | `image-upload-imagebucket-t8isnbr8sswv` | `devimageuploadstorXXXX` (storage account) / `images` (container) |
| **Access model** | Private; accessed via presigned URLs | Private (`publicAccess: 'None'`); accessed via SAS tokens |
| **Encryption** | SSE-S3 (AES256, AWS-managed key) | SSE (AES256, Microsoft-managed key — default) |
| **Versioning** | Enabled | Blob versioning enabled + soft delete (7–30 days) |
| **CORS** | GET,PUT,POST,HEAD,DELETE from `*` | GET,PUT,POST,HEAD,DELETE from SWA origin (restricted in staging/prod) |
| **Lifecycle policies** | None | Lifecycle rule: move to Cool tier after 90 days (recommended) |
| **Object metadata** | S3 object tags (`x-amz-tagging`) + custom metadata (`x-amz-meta-*`) | Azure Blob metadata (key-value pairs, `x-ms-meta-*`) |
| **Max upload size** | 10 MB (presigned POST condition) | No server-side limit at Blob level (enforce client-side) |
| **URL pattern** | `https://{bucket}.s3.{region}.amazonaws.com/{key}?X-Amz-Signature=...` | `https://{account}.blob.core.windows.net/{container}/{blob}?sv=...&sig=...` |
| **Auth from compute** | IAM role (`LambdaExecutionRole`) with S3 inline policy | Managed Identity with `Storage Blob Data Contributor` RBAC |
| **Region** | ap-southeast-2 (Sydney) | australiaeast (Sydney) |
| **Monthly cost** | $2.00 | ~$1.80 (5 GB Hot LRS) |

**Migration notes:**
- S3 object tags (`TagSet: [{Key, Value}]`) have no direct equivalent in Azure Blob. The migration strategy is to store all tags as blob metadata key-value pairs at upload time. The `list_blobs(include=['metadata'])` call returns them inline.
- S3 versioning uses version IDs per object. Azure Blob versioning uses version timestamps. The access pattern (access current version only) is identical.
- S3 CORS is configured per-bucket. Azure Blob CORS is configured per-storage-account (applies to all containers). Restrict `AllowedOrigins` to the SWA URL in staging and prod.

---

### 3. Amazon S3 (WebsiteBucket) → Azure Static Web Apps

| Attribute | AWS S3 WebsiteBucket | Azure Static Web Apps |
|---|---|---|
| **Service** | Amazon S3 (static website hosting) | Azure Static Web Apps (Free tier) |
| **Physical name** | `image-upload-websitebucket-vd866vxtcs1z` | `dev-imageupload-swa-australiaeast` |
| **URL** | `http://image-upload-websitebucket-vd866vxtcs1z.s3-website-ap-southeast-2.amazonaws.com` | `https://{random}.azurestaticapps.net` |
| **Protocol** | HTTP only (S3 static website) | HTTPS enforced (automatic) |
| **CDN** | None (raw S3 website — add CloudFront for CDN) | Built-in global CDN |
| **Custom domain** | Requires Route 53 + CloudFront | Built-in (Free: 1 custom domain; Standard: unlimited) |
| **SSL/TLS** | Requires CloudFront for HTTPS | Automatic (Let's Encrypt) |
| **CI/CD** | Manual S3 sync / CodePipeline | Built-in GitHub Actions integration |
| **Index document** | `app.html` | `app.html` (configured in `staticwebapp.config.json`) |
| **Error document** | `error.html` | 404 fallback in `staticwebapp.config.json` |
| **Public access** | Public bucket policy `s3:GetObject for *` | Public by design (CDN); no bucket-level security exposure |
| **Monthly cost** | $0.50 | $0.00 (Free tier) |

**Frontend code changes required:**
- Replace AWS SigV4 signing code with MSAL.js Azure AD authentication
- Replace API endpoint URL (`https://4lrh2l7i86.execute-api.ap-southeast-2.amazonaws.com/dev`) with Azure Function App URL (`https://{funcApp}.azurewebsites.net/api`)
- Replace direct S3 upload logic with Blob SAS token PUT upload
- Add Azure AD App Registration client ID configuration

---

### 4. Amazon API Gateway → Azure Functions HTTP Triggers

| Attribute | AWS API Gateway | Azure Functions HTTP Triggers |
|---|---|---|
| **Service** | Amazon API Gateway (REST v1) | Azure Functions HTTP trigger (built-in routing) |
| **Type** | REST API (regional endpoint) | HTTP trigger with route prefix `/api` |
| **Authorization** | `AWS_IAM` (SigV4 request signing) | Azure AD Bearer token (via MSAL.js) or Function key |
| **Routes** | POST /upload, GET /files, GET /files/{fileId}/view-url, DELETE /files/{fileId} | Same routes under `/api/` prefix |
| **CORS** | OPTIONS mock integration on each resource | `host.json` cors configuration |
| **Tracing** | AWS X-Ray (enabled) | Azure Application Insights (distributed tracing) |
| **Logging** | CloudWatch Logs (INFO level, data trace) | Application Insights (automatic) |
| **Throttling** | Default: 10,000 RPS burst, 5,000 RPS steady | Consumption: scales to 200 concurrent instances |
| **Stage** | `dev` | No equivalent (use Function App slots for staging) |
| **Monthly cost** | $1.00 (~1,100 calls × $3.50/million) | $0.00 (included in Functions execution cost) |

**Migration notes:**
- AWS API Gateway acts as a separate service routing to Lambda. In Azure, Functions HTTP triggers handle routing directly — no separate gateway resource is needed or recommended (APIM is prohibited as primary router per this project's design constraints).
- `AWS_IAM` SigV4 authorization has no Azure equivalent. Replace with:
  - **Option A (recommended for production):** Azure AD Bearer token validation middleware in the Function App.
  - **Option B (demo/dev):** `AuthLevel.ANONYMOUS` — open access, rely on CORS and SWA to restrict origins.
  - **Option C:** Azure Function key (`AuthLevel.FUNCTION`) passed as `x-functions-key` header — comparable security to the original IAM key but still avoids client-side secrets.
- API Gateway stages (`dev`, `prod`) map to Azure Function App deployment slots or separate Function Apps per environment.

---

### 5. AWS IAM → Azure Managed Identity + Azure AD

#### 5.1 LambdaExecutionRole → System-Assigned Managed Identity

| Attribute | AWS | Azure |
|---|---|---|
| **Resource** | `image-upload-LambdaExecutionRole-2MhYmRQ3aAnA` | System-Assigned Managed Identity on Function App |
| **Principal** | `lambda.amazonaws.com` | Function App's managed identity principal ID |
| **S3 permission** | `s3:PutObject,PutObjectTagging,GetObject,GetObjectTagging,DeleteObject on bucket/*` + `ListBucket on bucket` | `Storage Blob Data Contributor` RBAC on Storage Account |
| **Logging permission** | `AWSLambdaBasicExecutionRole` (CloudWatch Logs) | Automatic — App Insights SDK handles telemetry |
| **Credential management** | AWS STS temporary credentials (automatic) | `DefaultAzureCredential()` (automatic token refresh) |

#### 5.2 ApiUser + ApiUserAccessKey → Azure AD App Registration (MSAL.js)

| Attribute | AWS | Azure |
|---|---|---|
| **Resource** | `image-upload-api-user` (IAM User) + `AKIAXZEFIIOD2OIWPRPK` (Access Key) | Azure AD App Registration `image-upload-app` |
| **Auth pattern** | Long-lived access key in browser JS → SigV4 signing of each request | Short-lived Bearer token via MSAL.js authorization code flow |
| **Token lifetime** | Permanent (until rotated) | 1 hour (auto-refreshed by MSAL.js) |
| **Scope** | `execute-api:Invoke` on all methods of API Gateway | Authenticated call to Function App (custom scope or anonymous) |
| **Security risk** | 🔴 CRITICAL — secret exposed in CloudFormation outputs, permanent key | ✅ No long-lived secrets; tokens expire automatically |
| **Remediation action** | Rotate `AKIAXZEFIIOD2OIWPRPK` immediately; delete user post-migration | Configure MSAL.js in `app.html` with App Registration client ID |

#### 5.3 ApiGatewayCloudWatchLogsRole → N/A

| Attribute | AWS | Azure |
|---|---|---|
| **Resource** | `image-upload-ApiGatewayCloudWatchLogsRole-YGFCwY9oRVqq` | Not required |
| **Notes** | Required for API Gateway to push execution logs to CloudWatch | Azure Functions automatically stream to Application Insights — no explicit role needed |

---

### 6. Amazon CloudWatch → Azure Monitor (Log Analytics + Application Insights)

| Attribute | AWS CloudWatch | Azure Monitor |
|---|---|---|
| **Service** | Amazon CloudWatch Logs + Metrics | Azure Log Analytics Workspace + Application Insights |
| **Log groups** | 5 log groups (4 Lambda + 1 API GW) | 1 Log Analytics Workspace (all resources stream here) |
| **Query language** | CloudWatch Insights (CWQL) | Kusto Query Language (KQL) |
| **Metrics** | Invocations, Errors, Duration, ConcurrentExecutions | Invocations, Failures, Duration, AvailabilityResults |
| **Tracing** | AWS X-Ray (sampling, trace maps) | Application Insights (distributed tracing, dependency maps) |
| **Retention** | None set (no expiry — potential cost risk) | 30 days (dev), 90 days (prod) — set explicitly |
| **Alerting** | CloudWatch Alarms → SNS | Azure Monitor Alerts → Action Groups (email, webhook) |
| **Dashboards** | CloudWatch Dashboards | Azure Monitor Workbooks |
| **Monthly cost** | ~$0.50 (estimated) | ~$0.20 (estimated) |

**Migration notes:**
- Set `APPLICATIONINSIGHTS_CONNECTION_STRING` in Function App configuration to enable automatic instrumentation. Azure Functions v2 with Python automatically sends invocation telemetry, exceptions, and dependencies to Application Insights.
- KQL equivalent of common CloudWatch Insights queries:
  - `filter @type = "REPORT"` → `traces | where message contains "Function completed"`
  - `stats count(*) by bin(@timestamp, 5m)` → `traces | summarize count() by bin(timestamp, 5m)`
- Log Analytics retention policies must be set explicitly — unlike AWS which had no retention (infinite, costly), Azure requires a configured value.

---

### 7. AWS CloudFormation → Azure Bicep

| Attribute | AWS CloudFormation | Azure Bicep |
|---|---|---|
| **Service** | AWS CloudFormation | Azure Bicep (transpiles to ARM) |
| **Template format** | YAML or JSON | Bicep DSL (`.bicep` files) |
| **Stack concept** | Single stack with all 31 resources | Root `main.bicep` + 5 modules |
| **Parameters** | `Parameters:` section | `param` keyword with `@description()` and `@allowed()` decorators |
| **Outputs** | `Outputs:` section | `output` keyword per module |
| **Resource naming** | `!Sub '${AWS::StackName}-resourcename'` | `'${environment}-${workload}-type-${location}'` pattern |
| **Validation** | `aws cloudformation validate-template` | `az bicep build` |
| **What-if** | `aws cloudformation deploy --no-execute-changeset` | `az deployment group what-if` |
| **Rollback** | Automatic rollback on failure | Incremental mode — redeploy prior version to rollback |
| **Secrets** | CloudFormation outputs (🔴 insecure — used in current stack) | Key Vault references (secure — never in template outputs) |
| **Modules** | Nested stacks | Bicep modules (`module` keyword) |

---

## Configuration Differences Summary

| Configuration Aspect | AWS | Azure | Action Required |
|---|---|---|---|
| Max upload size enforcement | S3 presigned POST `content-length-range` condition | Client-side validation | Add JS validation in `app.html` |
| CORS wildcard origin | S3 `AllowedOrigins: ['*']` | Blob Storage CORS per storage account | Restrict to SWA origin in staging/prod |
| Object tags vs metadata | S3 object tags (`TagSet`) | Blob metadata (`x-ms-meta-*`) | Store tags as metadata at upload; update list logic |
| Auth mechanism (client) | AWS SigV4 (IAM access key) | Azure AD Bearer token (MSAL.js) | Rewrite auth in `app.html` |
| URL signing algorithm | HMAC-SHA256 with AWS credentials | HMAC-SHA256 with storage account key (user delegation) | Use `generate_blob_sas` with `user_delegation_key` |
| Log retention | None (infinite) | Explicit policy required | Set 30d (dev) / 90d (prod) in Bicep |
| Cold start | Lambda ~500ms | Functions Consumption ~500ms–3s | Acceptable for demo; use Premium for production SLA |
| IAM user secret in CloudFormation output | 🔴 EXPOSED | N/A | Rotate key immediately; remove from stack outputs |

---

## SDK Migration Reference

| boto3 call | azure-sdk equivalent | Package |
|---|---|---|
| `boto3.client('s3')` | `BlobServiceClient(account_url, credential=DefaultAzureCredential())` | `azure-storage-blob`, `azure-identity` |
| `s3.generate_presigned_post(Bucket, Key, Fields, Conditions, ExpiresIn)` | `generate_blob_sas(account_name, container, blob, permission=BlobSasPermissions(write=True,create=True), expiry=..., user_delegation_key=...)` | `azure-storage-blob` |
| `s3.generate_presigned_url('get_object', {'Bucket':..,'Key':..}, ExpiresIn)` | `generate_blob_sas(..., permission=BlobSasPermissions(read=True), expiry=...)` | `azure-storage-blob` |
| `s3.list_objects_v2(Bucket, MaxKeys, Prefix)` | `container_client.list_blobs(name_starts_with=prefix, include=['metadata'])` | `azure-storage-blob` |
| `s3.head_object(Bucket, Key)` | `blob_client.get_blob_properties()` → `.metadata` | `azure-storage-blob` |
| `s3.get_object_tagging(Bucket, Key)` | `blob_client.get_blob_properties().metadata` (tags stored as metadata) | `azure-storage-blob` |
| `s3.delete_object(Bucket, Key)` | `container_client.delete_blob(name)` | `azure-storage-blob` |
| `s3.delete_objects(Bucket, Delete={'Objects':[...]})` | `BlobBatchClient.delete_blobs(*names)` | `azure-storage-blob` |
| `botocore.exceptions.ClientError` | `azure.core.exceptions.ResourceNotFoundError` | `azure-core` |
| `os.environ['BUCKET_NAME']` | `os.environ['STORAGE_ACCOUNT_NAME']` | — |
