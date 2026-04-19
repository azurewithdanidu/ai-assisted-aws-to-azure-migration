# AWS to Azure Service Mapping

**Report Date:** 2026-04-18  
**AWS Account:** 535002891143 (arinco-bootcamp-2025)  
**Source Stack:** image-upload (CloudFormation, ap-southeast-2)  
**Target:** Azure australiaeast  
**Prepared by:** Azure Architect Agent  

---

## Overview

Every AWS service and resource in the `image-upload` CloudFormation stack maps to a direct Azure equivalent. The migration is a lift-and-shift with SDK refactoring — no architectural pattern changes are required. All 4 Lambda functions migrate to a single Azure Functions App; the API Gateway REST API maps to Azure API Management; S3 image storage maps to Azure Blob Storage; S3 static website maps to Azure Static Web Apps.

---

## Compute: Lambda → Azure Functions

| AWS Resource | AWS Config | Azure Resource | Azure Config | Configuration Differences | Migration Considerations |
|---|---|---|---|---|---|
| `image-upload-UploadFunction-iIIJ7xiZECuB` | python3.11, 256 MB, 30 s timeout, handler: `upload_handler.lambda_handler` | `upload_image()` function in `img-upload-dev-func` Function App | Python 3.11, Consumption plan, HTTP trigger POST /upload | No separate memory config in Consumption plan; auto-scales; cold start ~1–3 s vs Lambda ~200–500 ms | Rewrite `upload_handler.py`: `boto3.client('s3') → BlobServiceClient(DefaultAzureCredential())`; `generate_presigned_post → generate_blob_sas(write)`; client must PUT to SAS URL instead of POST multipart |
| `image-upload-ListFilesFunction-Pb0dKq9dR0Is` | python3.11, 256 MB, 30 s timeout, handler: `list_handler.lambda_handler` | `list_files()` function in `img-upload-dev-func` | Python 3.11, Consumption plan, HTTP trigger GET /files | Same Consumption plan limitations as above | Rewrite `list_handler.py`: `list_objects_v2 → list_blobs`; `generate_presigned_url(GET) → generate_blob_sas(read)`; `get_object_tagging → get_blob_tags`; `head_object → get_blob_properties` |
| `image-upload-GetViewUrlFunction-yMGI9X8Us5Em` | python3.11, 256 MB, 30 s timeout, handler: `view_handler.lambda_handler` | `get_view_url()` function in `img-upload-dev-func` | Python 3.11, Consumption plan, HTTP trigger GET /files/{fileId}/view-url | Path parameter via `req.route_params.get('fileId')` vs Lambda `event['pathParameters']['fileId']` | Rewrite `view_handler.py`: same S3→Blob SDK translation as list; path param binding changes |
| `image-upload-DeleteFileFunction-EG7Cfj3m2P6f` | python3.11, 256 MB, 30 s timeout, handler: `delete_handler.lambda_handler` | `delete_file()` function in `img-upload-dev-func` | Python 3.11, Consumption plan, HTTP trigger DELETE /files/{fileId} | Same path parameter binding change | Rewrite `delete_handler.py`: `s3.delete_object → blob_client.delete_blob()`; `list_objects_v2 prefix search → list_blobs(name_starts_with)` |

**Environment Variable Mapping**

| AWS Env Var | Value | Azure App Setting | Value | Reason for Change |
|---|---|---|---|---|
| `BUCKET_NAME` | `image-upload-imagebucket-t8isnbr8sswv` | `BLOB_CONTAINER_NAME` | `images` | `CONTAINER_NAME` is **reserved** by Azure Functions host — forbidden variable name |
| `URL_EXPIRATION` | `3600` | `URL_EXPIRATION` | `3600` | No change |
| N/A | N/A | `AZURE_STORAGE_ACCOUNT_NAME` | `<storage account name>` | Required by `DefaultAzureCredential` to build `BlobServiceClient` account URL |
| N/A | N/A | `APPLICATIONINSIGHTS_CONNECTION_STRING` | From App Insights resource | Auto-instrumentation; no equivalent in Lambda (CloudWatch is implicit) |
| N/A | N/A | `FUNCTIONS_WORKER_RUNTIME` | `python` | Required by Azure Functions runtime |
| N/A | N/A | `FUNCTIONS_EXTENSION_VERSION` | `~4` | Functions v4 runtime |

**Python SDK Changes (all functions)**

| AWS SDK (boto3) | Import | Azure SDK (azure-storage-blob) | Import |
|---|---|---|---|
| `boto3` | `import boto3` | `azure-storage-blob` | `from azure.storage.blob import BlobServiceClient, ContainerClient, BlobClient, generate_blob_sas, BlobSasPermissions` |
| `botocore.exceptions.ClientError` | `from botocore.exceptions import ClientError` | `azure.core.exceptions.ResourceNotFoundError` | `from azure.core.exceptions import ResourceNotFoundError` |
| `botocore.config.Config` | `from botocore.config import Config` | N/A — not needed | — |
| N/A | — | `azure-identity` | `from azure.identity import DefaultAzureCredential` |
| `boto3.client('s3')` | — | `BlobServiceClient(f"https://{acct}.blob.core.windows.net", credential=DefaultAzureCredential())` | — |
| `s3.generate_presigned_post(Bucket, Key, Fields, Conditions, ExpiresIn)` | — | `generate_blob_sas(account_name, container, blob, permission=BlobSasPermissions(write=True, create=True), expiry=datetime.utcnow()+timedelta(seconds=TTL), user_delegation_key=udk)` | — |
| `s3.generate_presigned_url('get_object', Params={...}, ExpiresIn=TTL)` | — | `generate_blob_sas(..., permission=BlobSasPermissions(read=True), expiry=...) → f"https://{acct}.blob.core.windows.net/{container}/{blob}?{sas}"` | — |
| `s3.list_objects_v2(Bucket, Prefix, MaxKeys)` → `response['Contents']` | — | `container_client.list_blobs(name_starts_with=prefix)` → iterable of `BlobProperties` | — |
| `s3.head_object(Bucket, Key)` → `response['Metadata']` | — | `blob_client.get_blob_properties()` → `.metadata` dict | — |
| `s3.delete_object(Bucket, Key)` | — | `container_client.get_blob_client(blob_name).delete_blob()` | — |
| `s3.get_object_tagging(Bucket, Key)` → `TagSet` list | — | `blob_client.get_blob_tags()` → dict | — |
| Lambda `event['body']` | — | `req.get_body().decode()` | — |
| Lambda `event['queryStringParameters']` | — | `req.params` (dict) | — |
| Lambda `event['pathParameters']['fileId']` | — | `req.route_params.get('fileId')` | — |
| `return {'statusCode': 200, 'headers': {...}, 'body': json.dumps(...)}` | — | `return func.HttpResponse(json.dumps(...), status_code=200, headers={...}, mimetype='application/json')` | — |
| `@app.function_name('UploadFunction')` (SAM/CFn) | — | `@app.route(route="upload", methods=["POST"])` (Functions v2 model) | — |

---

## API Layer: API Gateway → Azure API Management

| AWS Resource | AWS Config | Azure Resource | Azure Config | Configuration Differences | Migration Considerations |
|---|---|---|---|---|---|
| `image-upload-api` (REST API) | Regional, AWS_IAM (SigV4), 4 routes + 4 OPTIONS CORS mocks, throttle: 5000 burst / 10000 rate, stage: `dev`, X-Ray tracing ON | `img-upload-dev-apim` (Consumption) | 4 operations, subscription key auth, CORS inbound policy, Application Insights diagnostics | No VPC/private endpoint on Consumption; no X-Ray equivalent (replaced by App Insights distributed tracing); subscription key header replaces SigV4 | CORS policy must be configured as APIM inbound policy XML; OPTIONS preflight handled by APIM automatically when CORS policy is set; frontend must remove AWS SDK SigV4 signing and add `Ocp-Apim-Subscription-Key` header |
| Route: `POST /upload` | Auth: AWS_IAM, backend: Lambda proxy | Operation: `POST /upload` | Backend: Function App URL + `/api/upload` | APIM set-backend-service policy routes to Function App hostname | Verify `/api/` prefix in Function App URL routing; Functions v2 default route prefix is `/api/` unless `routePrefix` is set to `""` in `host.json` |
| Route: `GET /files` | Auth: AWS_IAM | Operation: `GET /files` | Backend: Function App | Same as above | — |
| Route: `GET /files/{fileId}/view-url` | Path param: `fileId` | Operation: `GET /files/{fileId}/view-url` | Path template: `{fileId}` | APIM path template `{fileId}` passes via URL to Function; function reads via `req.route_params` | Ensure `host.json` does not strip path parameters |
| Route: `DELETE /files/{fileId}` | Path param: `fileId` | Operation: `DELETE /files/{fileId}` | Path template: `{fileId}` | Same | — |
| `OPTIONS` CORS mock (4 routes) | Auth: NONE, returns CORS headers | APIM CORS inbound policy | `<cors>...<allowed-origins><origin>*</origin>...</cors>` | APIM handles OPTIONS automatically; no separate mock needed | Remove the 4 OPTIONS mock integrations from any IaC — APIM CORS policy replaces them |

**Authentication Model Change**

| AWS | Azure | Notes |
|---|---|---|
| AWS SigV4 signed requests | APIM Subscription Key (`Ocp-Apim-Subscription-Key` header) | Frontend must remove `aws-sdk` SigV4 signing; add subscription key header. Key stored in Key Vault; not embedded in client-side source. |
| IAM User `image-upload-api-user` + access key `AKIAXZEFIIOD2OIWPRPK` | Azure APIM Subscription (auto-generated key) | IAM user must be deactivated and access key rotated/deleted post-migration |
| `execute-api:Invoke` IAM policy | Azure APIM subscription scope: all APIs | Simpler to manage; no IAM policy syntax |

---

## Storage: S3 Image Bucket → Azure Blob Storage

| AWS Resource | AWS Config | Azure Resource | Azure Config | Configuration Differences | Migration Considerations |
|---|---|---|---|---|---|
| `image-upload-imagebucket-t8isnbr8sswv` | Private, versioning ON, CORS: ALL methods + AllowedOrigins=*, public access block FULL, SSE-S3 encryption | `img-upload-dev-store` (storage account) + `images` container | Standard LRS, blob versioning ON, allowBlobPublicAccess=false, CORS rule: ALL methods + AllowedOrigins=*, Microsoft-managed encryption, TLS 1.2 | S3 uses "buckets" with flat key prefix; Azure uses "containers" with blob name hierarchy — both support `{uuid}/{filename}` key patterns identically | SAS token TTL (3600 s) matches `URL_EXPIRATION`. Upload handler returns SAS PUT URL instead of pre-signed POST form — frontend must use `fetch(url, {method: 'PUT', body: file})` instead of FormData POST. |
| S3 pre-signed POST (upload) | `generate_presigned_post` → returns URL + form fields dict; client POSTs multipart | Blob SAS write URL | `generate_blob_sas(write=True)` → single URL; client PUTs file bytes directly | Critical frontend change: from FormData multipart POST to direct PUT. Max-size enforcement moves to application logic (S3 had condition `content-length-range 0 10485760`). | Update `app.html` fetch call from `method: 'POST', body: FormData` to `method: 'PUT', body: fileObject` |
| S3 pre-signed GET URL (view/list) | `generate_presigned_url('get_object')` → HTTPS URL with SigV4 query params, expiry | Blob SAS read URL | `generate_blob_sas(read=True)` → SAS query string appended to blob URL | URL format differs (Azure uses `sv`, `se`, `sr`, `sp`, `sig` params vs AWS `X-Amz-*` params) — frontend does not parse SAS params, only uses URL, so transparent | No frontend change needed for displaying/downloading via SAS URL |
| S3 object metadata (`x-amz-meta-*`) | Custom metadata stored as object tags | Azure Blob metadata | `.metadata` dict on blob properties | Key format: AWS uses lowercase `x-amz-meta-` prefix stripped; Azure uses plain dict keys | Metadata keys unchanged (`uploaddate`, `originalfilename`, `description`) — ensure no case collisions |
| S3 object tags (`TagSet`) | List of `{Key, Value}` pairs | Azure Blob tags | Dict of `{key: value}` | AWS tags are `Key`/`Value` pairs; Azure blob tags are dict. Azure Blob user-defined tags have limits: 10 tags/blob, key ≤512 chars, value ≤256 chars | If tags are migrated, convert from list-of-pairs to dict format |
| S3 versioning | `Enabled` | Blob soft-delete + versioning | `isVersioningEnabled: true`, soft-delete 7-day retention | Azure versioning creates an immutable prior version on overwrite/delete. `delete_blob()` without snapshot param deletes current version only | Existing S3 object versions not migrated — migration is for new writes only. Set soft-delete retention in Bicep. |
| S3 public access block (full) | `BlockPublicAcls: true` × 4 settings | `allowBlobPublicAccess: false` | storage account property | Equivalent security posture — no anonymous read | Ensure Bicep storage module sets `allowBlobPublicAccess: false` |

---

## Storage: S3 Website Bucket → Azure Static Web Apps

| AWS Resource | AWS Config | Azure Resource | Azure Config | Configuration Differences | Migration Considerations |
|---|---|---|---|---|---|
| `image-upload-websitebucket-vd866vxtcs1z` | Public website, index: `app.html`, error: `error.html`, HTTP (no TLS), URL: `s3-website-ap-southeast-2.amazonaws.com` | `img-upload-dev-swa` (Azure Static Web Apps, Free) | HTTPS enforced, custom domain support, 100 GB bandwidth/mo free | Azure SWA defaults to `index.html` as root document — `app.html` must be configured via `staticwebapp.config.json` | Create `staticwebapp.config.json` alongside `app.html`: `{"routes":[{"route":"/","rewrite":"/app.html"}],"navigationFallback":{"rewrite":"/app.html"}}` |
| HTTP endpoint | `http://image-upload-websitebucket-vd866vxtcs1z.s3-website-ap-southeast-2.amazonaws.com` | HTTPS endpoint | `https://{generated}.azurestaticapps.net` | Azure SWA automatically provisions TLS (S3 website was HTTP only) | Update all bookmarks and documentation with new HTTPS URL |
| S3 request charges | Per-request charges for website hosting | Free tier | No per-request charges (Free tier: 100 GB/mo, global CDN) | Azure SWA includes global CDN distribution automatically | No configuration needed |

---

## Identity & Access: IAM → Azure RBAC + Managed Identity

| AWS Resource | AWS Config | Azure Resource | Azure Config | Configuration Differences | Migration Considerations |
|---|---|---|---|---|---|
| `image-upload-LambdaExecutionRole-2MhYmRQ3aAnA` | Trust: `lambda.amazonaws.com`; Managed: `AWSLambdaBasicExecutionRole`; Inline: `s3:PutObject, GetObject, DeleteObject, ListBucket on image-upload-imagebucket-*` | System-Assigned Managed Identity on `img-upload-dev-func` | RBAC: `Storage Blob Data Contributor` (role ID `ba92f5b4-2d11-453d-a403-e96b0029c9fe`) on `images` container | Azure RBAC role is at container scope (least privilege) vs IAM role at bucket level. Logging access is implicit (App Insights via connection string — no separate IAM policy needed). | Managed Identity is automatically provisioned when `identity: {type: 'SystemAssigned'}` is set in Bicep. RBAC assignment deployed via `Microsoft.Authorization/roleAssignments` resource. |
| `image-upload-ApiGatewayCloudWatchLogsRole-YGFCwY9oRVqq` | Trust: `apigateway.amazonaws.com`; Managed: `AmazonAPIGatewayPushToCloudWatchLogs` | N/A | Azure API Management sends diagnostics to Application Insights natively | No equivalent role needed — APIM Consumption connects to App Insights via an instrumentation key or connection string setting | No migration action required |
| `image-upload-api-user` (IAM User) | Access key: `AKIAXZEFIIOD2OIWPRPK`; Inline policy: `execute-api:Invoke` | APIM Subscription Key | Auto-generated key, stored in Azure Key Vault secret `apim-subscription-primary-key` | Long-lived static credential replaced by a rotatable API subscription key managed by APIM | **Security action:** Immediately rotate/delete AWS access key `AKIAXZEFIIOD2OIWPRPK` after migration. Do not embed APIM key in client-side source — inject at deploy time or load from environment. |

---

## Monitoring: CloudWatch → Azure Monitor

| AWS Resource | AWS Config | Azure Resource | Azure Config | Configuration Differences | Migration Considerations |
|---|---|---|---|---|---|
| CloudWatch Log Groups (4 Lambda) | `/aws/lambda/image-upload-*`, ~0 KB stored | Application Insights + Log Analytics | `img-upload-dev-ai` + `img-upload-dev-law`, 30-day retention | Azure Functions streams all stdout/stderr + `logging` module output to App Insights automatically via `APPLICATIONINSIGHTS_CONNECTION_STRING` | No code change needed — `print()` and `logging.info()` in Python functions will stream to App Insights automatically |
| CloudWatch Log Groups (API GW) | `API-Gateway-Execution-Logs_4lrh2l7i86/dev` | APIM Diagnostic Logs | Via `Microsoft.ApiManagement/service/diagnostics` resource (logger: App Insights) | APIM request/response logging configured at API level in Bicep | Configure APIM diagnostics in `apim.bicep` to write to the same App Insights instance |
| CloudWatch Metrics | Lambda invocation count, errors, duration | Application Insights Metrics | Request count, failed requests, server response time | Different metric names and granularity; KQL queries replace CloudWatch Insights queries | Build Log Analytics KQL queries: `requests | where cloud_RoleName == 'img-upload-dev-func'` |
| CloudWatch Alarms (AppStream legacy) | 2 stale alarms, INSUFFICIENT_DATA | N/A | Not migrated | Delete in AWS post-migration | AWS cleanup task — not relevant to Azure |
| AWS X-Ray | PassThrough on all 4 Lambda | Application Insights Distributed Tracing | Auto-enabled via App Insights SDK integration in Functions runtime | Azure App Insights provides distributed tracing, dependency tracking, and request correlation automatically | No code change needed |

---

## Infrastructure as Code: CloudFormation → Azure Bicep

| AWS Resource | AWS Config | Azure Resource | Azure Config | Configuration Differences | Migration Considerations |
|---|---|---|---|---|---|
| CloudFormation stack `image-upload` | 1 stack, `ap-southeast-2`, 13 managed resources, `CAPABILITY_NAMED_IAM`, parameter: `Environment=dev` | Azure Bicep `main.bicep` | 7 modules, `australiaeast`, resource group scoped, parameters: `environment`, `workloadName`, `location`, etc. | Bicep uses modular decomposition (separate file per service group) vs CFn's single template with resources section. Bicep supports `existing` resource references. | Bicep templates already drafted in `bicep-templates/`. Deploy with `az deployment group create --template-file main.bicep --parameters parameters/dev.bicepparam` |
| CloudFormation `Parameters` | `Environment: dev` | Bicep `parameters/*.bicepparam` | Per-environment parameter files | Bicep param files use `.bicepparam` extension with `using` statement | `dev.bicepparam`, `staging.bicepparam`, `prod.bicepparam` already exist in workspace |
| CloudFormation `Outputs` | `ApiUrl`, `BucketName`, `WebsiteUrl`, `WebsiteBucketName` | Bicep `output` declarations | `functionAppUrl`, `staticWebAppUrl`, `storageAccountName`, `apimGatewayUrl` | Bicep outputs available via `az deployment group show --query properties.outputs` | Use outputs in CI/CD pipelines to get resource URLs after deployment |
| CFn `DeletionPolicy` | Default (Delete) | Bicep resource `properties` | No native delete policy in Bicep — controlled by `az group delete` or individual `az resource delete` | Azure does not have per-resource deletion policies in Bicep; use Azure resource locks for delete protection | Add `Microsoft.Authorization/locks@2020-05-01` resource in Bicep for prod resources if needed |

---

## Services Confirmed NOT Present (no migration required)

The following AWS services were confirmed absent in the discovery and require no Azure equivalent:

EC2, ECS, EKS, Elastic Beanstalk, RDS, Aurora, DynamoDB, ElastiCache, Redshift, SQS, SNS, EventBridge, Kinesis, CloudFront, Route 53, ACM, Secrets Manager, CodePipeline, CodeBuild, CodeDeploy, Step Functions, Direct Connect, VPN, WAF, Shield, Cognito, AppSync.

---

## Migration Summary

| Phase | AWS Resources | Azure Resources | Effort (Days) |
|---|---|---|---|
| Phase 1: Infrastructure | S3 (image), S3 (website), IAM Role, CloudFormation | Blob Storage, Static Web Apps, Managed Identity, RBAC, Key Vault, Monitoring, Bicep | 2 |
| Phase 2: Code Refactor | 4 Lambda functions (boto3) | 4 Azure Functions (`azure-storage-blob`) | 3 |
| Phase 3: API Layer | API Gateway REST (AWS_IAM/SigV4) | Azure API Management (subscription key) + CORS | 2 |
| Phase 4: Validation & Cutover | — | End-to-end tests, SWA URL update, AWS decommission | 3 |
| **Total** | **13 active resources** | **~12 Azure resources** | **~10 days** |
# Azure Service Mapping — Image Upload Service

**AWS Account:** 535002891143  
**AWS Region:** ap-southeast-2 (Sydney)  
**Azure Region:** australiaeast (Sydney)  
**Generated:** 2026-04-14  

---

## Overview

This document provides a complete mapping of every AWS service and resource in the `image-upload` application to its Azure equivalent, including configuration differences and migration considerations.

---

## 1. Compute — Lambda → Azure Functions

### AWS Resource

| Property | Value |
|----------|-------|
| **Service** | AWS Lambda |
| **Functions** | 4 (UploadFunction, ListFilesFunction, GetViewUrlFunction, DeleteFileFunction) |
| **Runtime** | Python 3.11 |
| **Memory** | 256 MB each |
| **Timeout** | 30 seconds each |
| **Architecture** | x86_64 |
| **Package type** | Zip |
| **Ephemeral storage** | 512 MB |
| **Tracing** | PassThrough (no X-Ray) |
| **Billing model** | Pay-per-invocation + GB-seconds |

### Azure Equivalent

| Property | Value |
|----------|-------|
| **Service** | Azure Functions |
| **Resource type** | `Microsoft.Web/sites` (kind: `functionapp`) |
| **Plan** | Consumption (Serverless) — `Microsoft.Web/serverfarms` (Dynamic) |
| **Runtime** | Python 3.11 (exact match — no upgrade needed) |
| **Memory** | Up to 1.5 GB (Consumption) — 256 MB equivalent config via `FUNCTIONS_WORKER_PROCESS_COUNT` |
| **Timeout** | Default 5 min, configurable up to 10 min (Consumption) — 30s AWS timeout is well within limits |
| **Architecture** | x64 |
| **Package type** | Zip deploy or Azure Storage deployment package |
| **Temp storage** | 500 MB (Consumption) |
| **Tracing** | Application Insights (auto SDK integration — superior to AWS PassThrough) |
| **Billing model** | Pay-per-execution + GB-seconds (identical model, slightly cheaper per GB-s) |
| **Azure Resource Name** | `img-upload-func` |

### Function Name Mapping

| AWS Lambda | Azure Function | Handler Mapping |
|-----------|---------------|-----------------|
| `image-upload-UploadFunction-iIIJ7xiZECuB` | `upload_function` | `upload_handler.lambda_handler` → `upload_function/function_app.py` |
| `image-upload-ListFilesFunction-Pb0dKq9dR0Is` | `list_files_function` | `list_handler.lambda_handler` → `list_files_function/function_app.py` |
| `image-upload-GetViewUrlFunction-yMGI9X8Us5Em` | `get_view_url_function` | `view_handler.lambda_handler` → `get_view_url_function/function_app.py` |
| `image-upload-DeleteFileFunction-EG7Cfj3m2P6f` | `delete_file_function` | `delete_handler.lambda_handler` → `delete_file_function/function_app.py` |

### Configuration Differences

| Aspect | AWS Lambda | Azure Functions |
|--------|-----------|-----------------|
| Environment variables | `BUCKET_NAME`, `URL_EXPIRATION` | `STORAGE_ACCOUNT_NAME`, `CONTAINER_NAME`, `URL_EXPIRATION_SECONDS` |
| Execution role | IAM Role (explicit ARN) | System-Assigned Managed Identity (automatic) |
| Cold start | Yes (~200–800ms Python) | Yes (~300–600ms Python — comparable) |
| Concurrency | 1000 default (account limit) | 200 default per Function App (adjustable) |
| Triggers | API Gateway → Lambda (event proxy) | APIM → Function HTTP trigger (direct HTTP) |

### Code Changes Required

```python
# AWS (boto3) — BEFORE
import boto3
s3 = boto3.client('s3', region_name='ap-southeast-2')
url = s3.generate_presigned_url('put_object',
    Params={'Bucket': os.environ['BUCKET_NAME'], 'Key': key},
    ExpiresIn=3600)

# Azure (azure-storage-blob) — AFTER
from azure.storage.blob import BlobServiceClient, generate_blob_sas, BlobSasPermissions
from datetime import datetime, timedelta, timezone

sas_token = generate_blob_sas(
    account_name=os.environ['STORAGE_ACCOUNT_NAME'],
    container_name=os.environ['CONTAINER_NAME'],
    blob_name=key,
    account_key=os.environ['STORAGE_ACCOUNT_KEY'],  # or use Managed Identity via DefaultAzureCredential
    permission=BlobSasPermissions(write=True),
    expiry=datetime.now(timezone.utc) + timedelta(seconds=int(os.environ['URL_EXPIRATION_SECONDS']))
)
url = f"https://{os.environ['STORAGE_ACCOUNT_NAME']}.blob.core.windows.net/{os.environ['CONTAINER_NAME']}/{key}?{sas_token}"
```

```python
# AWS (boto3) — list objects BEFORE
response = s3.list_objects_v2(Bucket=bucket, Prefix=prefix)
files = [obj['Key'] for obj in response.get('Contents', [])]

# Azure — list blobs AFTER
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient
credential = DefaultAzureCredential()
blob_service = BlobServiceClient(account_url=f"https://{account}.blob.core.windows.net", credential=credential)
container_client = blob_service.get_container_client(container)
files = [blob.name for blob in container_client.list_blobs(name_starts_with=prefix)]
```

---

## 2. API Gateway → Azure API Management

### AWS Resource

| Property | Value |
|----------|-------|
| **Service** | Amazon API Gateway (REST) |
| **API ID** | `4lrh2l7i86` |
| **Name** | `image-upload-api` |
| **Type** | Regional REST API |
| **Stage** | `dev` |
| **Endpoint** | `https://4lrh2l7i86.execute-api.ap-southeast-2.amazonaws.com/dev` |
| **Auth** | `AWS_IAM` (SigV4 signed requests) |
| **Security policy** | TLS_1_0 |
| **Tracing** | X-Ray enabled (API stage) |
| **Logging** | INFO level, data trace enabled, metrics enabled |
| **Throttling** | 5000 burst, 10000 requests/sec |
| **CORS** | OPTIONS mock integration on all routes |

### Azure Equivalent

| Property | Value |
|----------|-------|
| **Service** | Azure API Management |
| **Tier** | Consumption (serverless, pay-per-call) |
| **Resource type** | `Microsoft.ApiManagement/service` |
| **Resource name** | `img-upload-apim` |
| **Endpoint** | `https://img-upload-apim.azure-api.net` |
| **Auth** | Subscription key (`Ocp-Apim-Subscription-Key` header) or Entra ID JWT |
| **Security policy** | TLS 1.2+ (enforced by default — upgrade from TLS 1.0) |
| **Tracing** | Application Insights (built-in APIM diagnostic policy) |
| **Logging** | All operations → Application Insights → Log Analytics |
| **Throttling** | `rate-limit-by-key` policy + `quota-by-key` policy |
| **CORS** | APIM `cors` policy element |

### Route Mapping

| AWS Path | HTTP Method | AWS Auth | Azure Path | Azure Auth | Azure Backend |
|----------|------------|---------|-----------|-----------|---------------|
| `/upload` | POST | AWS_IAM | `/upload` | Subscription Key | `img-upload-func/upload_function` |
| `/files` | GET | AWS_IAM | `/files` | Subscription Key | `img-upload-func/list_files_function` |
| `/files/{fileId}/view-url` | GET | AWS_IAM | `/files/{fileId}/view-url` | Subscription Key | `img-upload-func/get_view_url_function` |
| `/files/{fileId}` | DELETE | AWS_IAM | `/files/{fileId}` | Subscription Key | `img-upload-func/delete_file_function` |
| `/upload` (CORS) | OPTIONS | NONE | *(handled by APIM cors policy)* | NONE | Mock |
| `/files` (CORS) | OPTIONS | NONE | *(handled by APIM cors policy)* | NONE | Mock |
| `/files/{fileId}/view-url` (CORS) | OPTIONS | NONE | *(handled by APIM cors policy)* | NONE | Mock |
| `/files/{fileId}` (CORS) | OPTIONS | NONE | *(handled by APIM cors policy)* | NONE | Mock |

### Configuration Differences

| Aspect | AWS API Gateway | Azure APIM |
|--------|----------------|-----------|
| Auth mechanism | AWS SigV4 (IAM) | Subscription key or Entra ID JWT |
| Frontend changes | SigV4 signing library required | Add `Ocp-Apim-Subscription-Key` header |
| CORS handling | Manual OPTIONS mock methods per route | Single `cors` policy at API level |
| TLS | TLS 1.0 (insecure) | TLS 1.2+ (secure by default) |
| Caching | Per-method TTL | Per-operation cache policy |
| Rate limiting | Account/stage throttle | Flexible: per-subscription, per-IP, per-user |
| WAF | Requires separate WAF/Shield | Integrates with Azure Front Door WAF |

### APIM CORS Policy

```xml
<cors allow-credentials="false">
    <allowed-origins>
        <origin>*</origin>
        <!-- Recommended: restrict to SWA origin in production -->
        <!-- <origin>https://img-upload-swa.azurestaticapps.net</origin> -->
    </allowed-origins>
    <allowed-methods>
        <method>GET</method>
        <method>POST</method>
        <method>DELETE</method>
        <method>OPTIONS</method>
    </allowed-methods>
    <allowed-headers>
        <header>content-type</header>
        <header>ocp-apim-subscription-key</header>
        <header>authorization</header>
    </allowed-headers>
    <expose-headers>
        <header>ETag</header>
        <header>Content-Type</header>
    </expose-headers>
</cors>
```

---

## 3. S3 (Image Store) → Azure Blob Storage

### AWS Resource

| Property | Value |
|----------|-------|
| **Service** | Amazon S3 |
| **Bucket** | `image-upload-imagebucket-t8isnbr8sswv` |
| **Region** | ap-southeast-2 |
| **Access** | Private (all public access blocked) |
| **Versioning** | Enabled |
| **CORS** | Enabled — all methods, `*` origins, 3000s max-age |
| **Encryption** | SSE-S3 (AES-256, default) |
| **Lifecycle** | Not configured |

### Azure Equivalent

| Property | Value |
|----------|-------|
| **Service** | Azure Blob Storage |
| **Resource type** | `Microsoft.Storage/storageAccounts` |
| **Storage account name** | `imguploadstore<unique>` |
| **Container name** | `images` |
| **Account kind** | StorageV2 (General Purpose v2) |
| **Access tier** | Hot |
| **Replication** | LRS (dev) / ZRS (production recommended) |
| **Access** | No public blob access (`allowBlobPublicAccess: false`) |
| **Versioning** | Enabled (`isVersioningEnabled: true`) |
| **Soft delete** | 7 days (blobs + containers) |
| **CORS** | Configured on Blob service — mirrors AWS CORS config |
| **Encryption** | Microsoft-managed keys (equivalent to SSE-S3); optional CMK via Key Vault |
| **Lifecycle** | Hot → Cool (90 days) → Archive (365 days) |
| **TLS** | Minimum TLS 1.2 |

### CORS Configuration

| Property | AWS Value | Azure Value |
|----------|----------|------------|
| Allowed methods | GET, PUT, POST, HEAD, DELETE | GET, PUT, POST, HEAD, DELETE |
| Allowed origins | `*` | `*` (restrict to SWA URL in production) |
| Allowed headers | `*` | `*` |
| Exposed headers | ETag, Content-Type, x-amz-* | ETag, Content-Type (x-amz-* not applicable) |
| Max age (seconds) | 3000 | 3000 |

### Pre-signed URL → SAS Token Mapping

| AWS Concept | Azure Equivalent |
|-------------|-----------------|
| `generate_presigned_url('put_object')` | `generate_blob_sas(permission=BlobSasPermissions(write=True))` |
| `generate_presigned_url('get_object')` | `generate_blob_sas(permission=BlobSasPermissions(read=True))` |
| `ExpiresIn=3600` | `expiry=datetime.now(utc) + timedelta(seconds=3600)` |
| S3 Object Key | Blob Name |
| S3 Bucket | Blob Container |

### Data Migration Command

```bash
# Using AzCopy from S3 to Azure Blob Storage
azcopy copy \
  "https://image-upload-imagebucket-t8isnbr8sswv.s3.ap-southeast-2.amazonaws.com" \
  "https://imguploadstore.blob.core.windows.net/images" \
  --recursive \
  --s2s-preserve-access-tier=false
```

---

## 4. S3 Static Website → Azure Static Web Apps

### AWS Resource

| Property | Value |
|----------|-------|
| **Service** | Amazon S3 Static Website Hosting |
| **Bucket** | `image-upload-websitebucket-vd866vxtcs1z` |
| **Index document** | `app.html` |
| **Error document** | `error.html` |
| **Public access** | Enabled (bucket policy: public read on `s3:GetObject`) |
| **HTTPS** | Not enforced (HTTP endpoint) |
| **CDN** | None |

### Azure Equivalent

| Property | Value |
|----------|-------|
| **Service** | Azure Static Web Apps |
| **Resource type** | `Microsoft.Web/staticSites` |
| **Resource name** | `img-upload-swa` |
| **Tier** | Free tier (custom domain, SSL, CDN included) |
| **Index document** | `app.html` |
| **Error document** | `error.html` (configured via `staticwebapp.config.json`) |
| **Public access** | HTTPS only (enforced) |
| **HTTPS** | Built-in SSL certificate (auto-managed) |
| **CDN** | Azure CDN included at no extra cost |
| **Custom domain** | Supported (free SSL) |
| **Deployment** | GitHub Actions, Azure DevOps, or `az staticwebapp deploy` |

### Configuration Differences

| Aspect | AWS S3 Website | Azure Static Web Apps |
|--------|---------------|----------------------|
| HTTP support | HTTP + HTTPS | HTTPS only (secure by default) |
| CDN | Requires CloudFront | Built-in (global CDN) |
| SSL certificate | Requires ACM + CloudFront | Built-in, auto-renewed |
| Custom domain | Route 53 + CloudFront required | Direct in Azure portal |
| Cost | $0.023/GB storage + data transfer | Free tier (100GB bandwidth/month) |
| CORS | N/A (static files) | `staticwebapp.config.json` headers |

### staticwebapp.config.json

```json
{
  "routes": [
    { "route": "/", "rewrite": "/app.html" },
    { "route": "/*", "rewrite": "/app.html" }
  ],
  "responseOverrides": {
    "404": { "rewrite": "/error.html", "statusCode": 404 }
  },
  "globalHeaders": {
    "content-security-policy": "default-src https: 'self'; script-src 'self' 'unsafe-inline'",
    "x-frame-options": "SAMEORIGIN",
    "x-content-type-options": "nosniff"
  }
}
```

---

## 5. IAM Role → Azure Managed Identity + RBAC

### AWS Resource

| Property | Value |
|----------|-------|
| **Service** | AWS IAM |
| **Role name** | `image-upload-LambdaExecutionRole-2MhYmRQ3aAnA` |
| **Trusted principal** | `lambda.amazonaws.com` |
| **Managed policies** | `AWSLambdaBasicExecutionRole` (CloudWatch Logs write) |
| **Inline policy** | S3Access: `s3:PutObject`, `s3:GetObject`, `s3:DeleteObject`, `s3:ListBucket` on ImageBucket |

### Azure Equivalent

| Property | Value |
|----------|-------|
| **Service** | Azure Managed Identity + Azure RBAC |
| **Identity type** | System-Assigned Managed Identity (on Function App) |
| **Logging permissions** | Built-in — Application Insights handles all Function telemetry |
| **Storage permissions** | `Storage Blob Data Contributor` role on `images` container |
| **Scope** | Container-level (not entire storage account — principle of least privilege) |
| **Credentials** | None required — automatic token exchange via Azure AD |

### IAM User → Entra ID App Registration

| Property | AWS | Azure |
|----------|-----|-------|
| **Service** | IAM User | Entra ID App Registration |
| **Resource** | `image-upload-api-user` | `img-upload-app-registration` |
| **Auth method** | Long-lived Access Key + Secret Key | Client Secret or Certificate (short-lived) |
| **Token lifetime** | Permanent (until rotated) | 1 hour (auto-refreshed) |
| **Usage** | SigV4 signing for API Gateway | Bearer token for APIM |
| **Security improvement** | N/A | Eliminates long-lived credential risk |

### Permission Mapping

| AWS IAM Permission | Azure RBAC Role | Scope |
|-------------------|----------------|-------|
| `s3:PutObject` + `s3:GetObject` + `s3:DeleteObject` | `Storage Blob Data Contributor` | `images` container |
| `s3:ListBucket` | `Storage Blob Data Reader` (subset of above) | `images` container |
| `logs:CreateLogGroup` + `logs:PutLogEvents` | Built-in via Application Insights (no role needed) | Function App telemetry |
| `execute-api:Invoke` | APIM Subscription Key or Entra ID scope | APIM product |

---

## 6. CloudWatch → Azure Monitor + Application Insights

### AWS Resources

| Property | Value |
|----------|-------|
| **Service** | Amazon CloudWatch |
| **Log groups** | 8 (4 Lambda + 2 API GW active + 2 legacy) |
| **Alarms** | 2 (AppStream remnants — INSUFFICIENT_DATA, not relevant to app) |
| **X-Ray** | Enabled on API Gateway stage |
| **Metrics** | Default Lambda + API GW metrics |

### Azure Equivalent

| AWS Resource | Azure Equivalent | Notes |
|-------------|-----------------|-------|
| CloudWatch Logs (Lambda) | Application Insights — Traces table | Automatic via Function App host configuration |
| CloudWatch Logs (API GW execution) | APIM Diagnostic Policy → App Insights | Config: `<log-to-eventhub>` or App Insights direct |
| CloudWatch Metrics | Azure Monitor Metrics | Auto-populated for all Azure resources |
| X-Ray traces | Application Insights — Dependencies + Requests | End-to-end distributed tracing |
| CloudWatch Alarms | Azure Monitor Alerts | Action groups → email/Teams/webhook |
| CloudWatch Dashboards | Azure Monitor Workbooks | KQL-based interactive dashboards |

### Azure Observability Stack

| Component | Resource Name | Purpose |
|-----------|--------------|---------|
| Log Analytics Workspace | `img-upload-law` | Central log store for all resources |
| Application Insights | `img-upload-appins` | APM — requests, dependencies, failures, tracing |
| Azure Monitor Alerts | (via LAW) | Error rate, latency, availability alerts |

### Recommended Alerts

```
Alert 1: Function Error Rate
  Condition: exceptions/count > 5 in 5 minutes
  Severity: 2 (Warning)

Alert 2: APIM 5xx Errors
  Condition: ApiManagementRequests (ResponseCode≥500) > 5 in 1 minute
  Severity: 1 (Error)

Alert 3: Storage Latency
  Condition: SuccessE2ELatency > 2000ms average over 5 minutes
  Severity: 3 (Informational)
```

---

## 7. KMS → Azure Key Vault

### AWS Resource

| Property | Value |
|----------|-------|
| **Service** | AWS KMS |
| **Key ID** | `6c852b32-93c4-4049-91fe-050814d33c10` |
| **Usage** | Likely AppStream-related (not used by image-upload app directly) |

### Azure Equivalent

| Property | Value |
|----------|-------|
| **Service** | Azure Key Vault |
| **Resource type** | `Microsoft.KeyVault/vaults` |
| **Resource name** | `img-upload-kv` |
| **SKU** | Standard |
| **Soft delete** | Enabled (90 days) |
| **Purge protection** | Enabled |
| **Access policy** | RBAC (Key Vault Secrets User for Function App Managed Identity) |

### Secrets Stored in Key Vault

| Secret Name | Value Source | Used By |
|------------|-------------|---------|
| `storage-account-key` | Storage Account key | Functions (SAS generation fallback) |
| `apim-subscription-key` | APIM subscription | Frontend / test clients |
| `app-registration-client-secret` | Entra ID App Reg | API consumers |

---

## 8. CloudFormation → Bicep

### AWS Resource

| Property | Value |
|----------|-------|
| **Service** | AWS CloudFormation |
| **Stack name** | `image-upload` |
| **Status** | CREATE_COMPLETE |
| **Template size** | ~18,954 bytes |
| **Resources managed** | ~20 resources |

### Azure Equivalent

| Property | Value |
|----------|-------|
| **Service** | Azure Resource Manager (Bicep) |
| **Main template** | `main.bicep` |
| **Modules** | 6 (storage, functions, apim, staticweb, keyvault, monitoring) |
| **Parameters** | `environment` (dev/staging/prod), `location`, `uniqueSuffix` |
| **Deployment** | `az deployment group create` or GitHub Actions |

### CloudFormation → Bicep Parameter Mapping

| CloudFormation Parameter | Bicep Parameter | Type | Default |
|-------------------------|----------------|------|---------|
| `Environment` (dev/staging/prod) | `environment` | string | `'dev'` |
| `AWS::Region` (implicit) | `location` | string | `resourceGroup().location` |
| `AWS::StackName` (implicit for naming) | `appName` | string | `'img-upload'` |
| `AWS::AccountId` (implicit) | N/A (Bicep uses subscription ID) | — | — |

### Bicep Module Structure

```
bicep-templates/
├── main.bicep                    # Orchestrates all modules
├── parameters/
│   ├── dev.bicepparam            # Dev environment params
│   ├── staging.bicepparam        # Staging params
│   └── prod.bicepparam           # Production params
└── modules/
    ├── storage.bicep             # Replaces: ImageBucket + versioning + CORS + lifecycle
    ├── functions.bicep           # Replaces: 4x Lambda + LambdaExecutionRole + permissions
    ├── apim.bicep                # Replaces: ImageUploadApi + all routes/methods/stage/auth
    ├── staticweb.bicep           # Replaces: WebsiteBucket + WebsiteBucketPolicy
    ├── keyvault.bicep            # Replaces: KMS key (partially)
    └── monitoring.bicep          # Replaces: CloudWatch log groups + alarms
```

---

## 9. Services Not Migrated (No Azure Equivalent Needed)

| AWS Resource | Reason |
|-------------|--------|
| AppStream 2.0 buckets, IAM roles, CW alarms | Service decommissioned — delete from AWS, no Azure equivalent required |
| AWS Organizations service-linked role | Account-level AWS construct — no migration needed |
| AWS Resource Explorer service-linked role | AWS-specific service — no equivalent required |
| AWS Trusted Advisor / Support roles | AWS-specific managed services — no migration needed |
| API Gateway CloudWatch logging role | Not needed in Azure — APIM diagnostics use built-in integration |
| IAM Access Key for API User | Eliminated entirely — replaced with short-lived Entra ID tokens |

---

## 10. Security Improvement Summary

| # | AWS Weakness | Azure Improvement | Priority |
|---|-------------|------------------|----------|
| 1 | IAM User + long-lived access key for API auth | Entra ID Service Principal with client secret (1hr tokens) | **HIGH** |
| 2 | TLS 1.0 security policy on API Gateway | TLS 1.2+ enforced by default on APIM | **HIGH** |
| 3 | CORS `*` wildcard on ImageBucket (`AllowedOrigins: *`) | Restrict to SWA endpoint URL only | **MEDIUM** |
| 4 | No WAF on API Gateway | Azure APIM with Azure Front Door WAF (optional, low cost) | **MEDIUM** |
| 5 | Static website S3 bucket with public read policy | Azure Static Web Apps — HTTPS enforced, no public bucket | **MEDIUM** |
| 6 | Lambda functions not in VPC | Azure Functions can be VNet-integrated (optional for dev) | **LOW** |
| 7 | No soft-delete on S3 | Azure Blob soft delete (7 days) enabled by default | **LOW** |
| 8 | No lifecycle policy on S3 | Azure Blob lifecycle: Hot→Cool→Archive | **LOW** |

---

## Azure Resource Naming Convention

| Resource | Name | Pattern |
|----------|------|---------|
| Resource Group | `img-upload-rg` | `{app}-{env}-rg` |
| Storage Account | `imguploadstore{uid}` | `{app}store{uniqueSuffix}` (max 24 chars, lowercase) |
| Function App | `img-upload-func-{uid}` | `{app}-func-{uniqueSuffix}` |
| App Service Plan | `img-upload-asp` | `{app}-asp` |
| API Management | `img-upload-apim` | `{app}-apim` |
| Static Web App | `img-upload-swa` | `{app}-swa` |
| Key Vault | `img-upload-kv` | `{app}-kv` |
| Log Analytics WS | `img-upload-law` | `{app}-law` |
| Application Insights | `img-upload-appins` | `{app}-appins` |
| User-Assigned MI | `img-upload-mi` | `{app}-mi` |

---

## Migration Checklist Summary

| Step | AWS Resource | Azure Target | Status |
|------|-------------|-------------|--------|
| 1 | S3 `imagebucket` | Azure Blob Storage `imguploadstore/images` | ☐ |
| 2 | S3 `websitebucket` | Azure Static Web Apps `img-upload-swa` | ☐ |
| 3 | Lambda `UploadFunction` (Python) | Azure Function `upload_function` | ☐ |
| 4 | Lambda `ListFilesFunction` (Python) | Azure Function `list_files_function` | ☐ |
| 5 | Lambda `GetViewUrlFunction` (Python) | Azure Function `get_view_url_function` | ☐ |
| 6 | Lambda `DeleteFileFunction` (Python) | Azure Function `delete_file_function` | ☐ |
| 7 | API Gateway `image-upload-api` | Azure APIM `img-upload-apim` | ☐ |
| 8 | IAM Role `LambdaExecutionRole` | System-Assigned Managed Identity + RBAC | ☐ |
| 9 | IAM User `image-upload-api-user` | Entra ID App Registration | ☐ |
| 10 | KMS Key | Azure Key Vault `img-upload-kv` | ☐ |
| 11 | CloudWatch Logs | Application Insights + Log Analytics | ☐ |
| 12 | CloudFormation stack | Bicep templates | ☐ |
| 13 | AppStream remnants | DELETE (no migration) | ☐ |

---

*Generated by: Azure Architect Agent | Source: Live AWS API discovery of account 535002891143*
