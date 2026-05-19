# AWS to Azure Service Mapping — Image Upload Photo Gallery

**Project:** image-upload CloudFormation Stack (ap-southeast-2 → australiaeast)  
**Prepared by:** Azure Architect Agent  
**Date:** 2026-05-19  
**Source:** aws-inventory.json, dependency-matrix.csv, migration-assessment.md  

---

## Summary

| AWS Service | Count | Azure Equivalent | Migration Complexity | Effort (Days) |
|---|---|---|---|---|
| AWS Lambda (Python 3.11) | 4 functions | Azure Functions v2 (Python 3.11, Consumption Y1) | LOW | 3 |
| Amazon API Gateway REST | 1 API, 4 routes | Azure Functions HTTP triggers (built-in) | LOW | 0.5 (no separate service) |
| Amazon S3 (image storage) | 1 bucket | Azure Blob Storage (Standard LRS, Hot) | LOW | 1 |
| Amazon S3 (static website) | 1 bucket | Azure Static Web Apps (Free tier) | LOW | 1 |
| IAM Role (Lambda execution) | 1 role | System-assigned Managed Identity + RBAC | LOW | 0.5 |
| IAM User + Access Key (SPA auth) | 1 user | Azure Functions key (`x-functions-key`) | MEDIUM | 1.5 |
| AWS CloudFormation | 1 stack | Azure Bicep | LOW | 2 |
| Amazon CloudWatch Logs | 3 log groups | Application Insights + Log Analytics | LOW | 0.5 |
| **Total** | **14 resources** | **6 Azure service types** | **LOW** | **~9–10 days** |

---

## Detailed Service Mappings

### 1. AWS Lambda → Azure Functions

| Attribute | AWS Lambda | Azure Functions |
|---|---|---|
| **Service** | AWS Lambda | Azure Functions v2 |
| **Hosting model** | Managed, per-invocation billing | Consumption plan (Y1), per-invocation billing |
| **Runtime** | Python 3.11, x86_64 | Python 3.11, Linux |
| **Memory** | 256 MB per function | Configurable (default 1.5 GB on Consumption; no static allocation) |
| **Timeout** | 30 seconds | 5 minutes default (Consumption); up to 10 minutes configurable |
| **Cold start** | Typically 200–800 ms | Similar range (200 ms–2 s); acceptable for this traffic profile |
| **Pricing** | $0.20/1M requests + $0.0000166667/GB-s | $0.20/1M requests + $0.000016/GB-s; **first 1M free + 400K GB-s** |
| **Concurrency** | Per-function reserved concurrency | Automatic scaling; throttle via host.json |
| **Deployment unit** | Individual ZIP per function | Single Function App containing all 4 functions (Python v2 model) |
| **Function discovery** | `handler` field in CloudFormation | Decorator-based: `@app.route(route=..., methods=[...])` |
| **Auth** | API Gateway → Lambda (no direct auth on Lambda) | Function-level key (`authLevel="function"`) or anonymous |
| **Monitoring** | CloudWatch Logs (log group per function) | Application Insights + Log Analytics (single workspace) |

**Migration steps:**
1. Create single Function App (Python 3.11, Consumption Y1, Australia East)
2. Replace `lambda_handler(event, context)` entry points with `@app.route(...)` decorated functions in `function_app.py`
3. Replace `event['body']`, `event['pathParameters']`, `event['queryStringParameters']` with `req.get_json()`, `req.route_params`, `req.params`
4. Replace `boto3` with `azure-storage-blob` + `azure-identity` (see Section 3)
5. Return `func.HttpResponse(body, status_code=..., mimetype='application/json')` instead of `{'statusCode': ..., 'body': ...}` dict

**Function mapping:**

| AWS Lambda Function | Logical ID | Azure Function Name | Route |
|---|---|---|---|
| image-upload-UploadFunction-iIIJ7xiZECuB | UploadFunction | `upload_image` | `POST /api/upload` |
| image-upload-ListFilesFunction-Pb0dKq9dR0Is | ListFilesFunction | `list_images` | `GET /api/files` |
| image-upload-GetViewUrlFunction-yMGI9X8Us5Em | GetViewUrlFunction | `get_view_url` | `GET /api/files/{fileId}/view-url` |
| image-upload-DeleteFileFunction-EG7Cfj3m2P6f | DeleteFileFunction | `delete_image` | `DELETE /api/files/{fileId}` |

---

### 2. Amazon API Gateway REST → Azure Functions HTTP Triggers

| Attribute | AWS API Gateway REST | Azure Functions HTTP Trigger |
|---|---|---|
| **Service** | Amazon API Gateway (separate managed service) | Built into Azure Functions (no separate resource) |
| **Endpoint type** | REGIONAL | Built-in per-Function App |
| **Base URL** | `https://4lrh2l7i86.execute-api.ap-southeast-2.amazonaws.com/dev` | `https://photo-gallery-func.azurewebsites.net/api` |
| **Route prefix** | Stage: `/dev` | Configurable via `host.json` `routePrefix` (default `api`) |
| **Auth model** | AWS_IAM (SigV4) on all business endpoints | Function key (`x-functions-key` header) |
| **CORS** | Mock OPTIONS integrations per resource | Single `cors` block in `siteConfig` (Bicep) or `host.json` |
| **Integration type** | AWS_PROXY (Lambda proxy) | Native HTTP trigger (no proxy layer) |
| **Cost** | $3.50/million REST calls (ap-southeast-2) | Included in Function App Consumption pricing |
| **Separate resource?** | YES — API Gateway is a separate billable service | NO — HTTP trigger is part of Function App, no separate cost |

**Route mapping:**

| AWS Route | Method | Auth | Azure Route | Auth |
|---|---|---|---|---|
| `/upload` | POST | AWS_IAM | `/api/upload` | `x-functions-key` header |
| `/files` | GET | AWS_IAM | `/api/files` | `x-functions-key` header |
| `/files/{fileId}/view-url` | GET | AWS_IAM | `/api/files/{fileId}/view-url` | `x-functions-key` header |
| `/files/{fileId}` | DELETE | AWS_IAM | `/api/files/{fileId}` | `x-functions-key` header |
| `OPTIONS /*` | OPTIONS | NONE (mock) | Handled by built-in CORS support | N/A |

**Migration considerations:**
- No AWS API Gateway → Azure APIM mapping — APIM is **explicitly forbidden** per architecture constraints
- SPA JavaScript must change: remove AWS SDK SigV4 signing; add `headers: {'x-functions-key': '<key>'}` to all `fetch()` calls
- Function App default key is available via `az functionapp keys list --resource-group ... --name ...`

---

### 3. Amazon S3 (ImageBucket) → Azure Blob Storage

| Attribute | AWS S3 (ImageBucket) | Azure Blob Storage |
|---|---|---|
| **Service** | Amazon S3 | Azure Blob Storage (StorageV2) |
| **Account/Bucket** | `image-upload-imagebucket-t8isnbr8sswv` | Storage Account `photogallerysto`, container `images` |
| **Storage class** | S3 Standard (Hot equivalent) | Hot tier |
| **Redundancy** | S3 SLA 99.999999999% (11 9s) | Standard LRS (3 copies in one datacenter); GRS in prod |
| **Versioning** | Enabled | Configurable; disabled for dev, enabled for prod |
| **Encryption** | SSE-S3 (default) | Azure Storage Service Encryption (AES-256, default, Microsoft-managed keys) |
| **Public access** | ALL BLOCKED | `allowBlobPublicAccess: false` |
| **CORS** | AllowedOrigins: [`*`], All methods, 3000s | CORS rules on blobService resource; restricted to SWA origin in prod |
| **Max object size** | 10 MB enforced via presigned POST policy | Configured in SAS token policy; up to 5 TB supported by service |
| **Object key pattern** | `{uuid4}/{original_filename}` | Blob name: `{uuid4}/{original_filename}` (identical) |
| **Metadata** | `x-amz-meta-uploaddate`, `x-amz-meta-originalfilename`, `x-amz-meta-description` | `blob.metadata['uploaddate']`, `['originalfilename']`, `['description']` |
| **Tags** | S3 object tags (key-value) | Azure Blob Index tags (key-value, searchable) |
| **Pre-signed URLs** | `generate_presigned_post()` (multipart POST form) | `generate_blob_sas(BlobSasPermissions(write=True))` → PUT URL |
| **Pre-signed GET URLs** | `generate_presigned_url('get_object', ExpiresIn=3600)` | `generate_blob_sas(BlobSasPermissions(read=True))` + construct URL |
| **List objects** | `list_objects_v2(Bucket, Prefix, MaxKeys)` | `container_client.list_blobs(name_starts_with=prefix)` |
| **Delete** | `delete_objects(Bucket, Delete={'Objects': [...]})` | Per-blob: `container_client.delete_blob(blob_name)` |

**Critical migration change — upload flow:**
- **AWS:** SPA calls Function → gets `url` + `fields` dict → does `FormData` multipart POST to S3
- **Azure:** SPA calls Function → gets single `sas_url` → does `fetch(sasUrl, {method:'PUT', headers:{'x-ms-blob-type':'BlockBlob'}, body:fileBlob})`
- SPA JavaScript must be updated accordingly

**SDK change summary:**

| boto3 call | azure-storage-blob equivalent |
|---|---|
| `boto3.client('s3')` | `BlobServiceClient(account_url, DefaultAzureCredential())` |
| `s3.generate_presigned_post(Bucket, Key, ExpiresIn, Conditions)` | `generate_blob_sas(account, container, blob, permission=BlobSasPermissions(write=True, create=True), expiry=...)` |
| `s3.generate_presigned_url('get_object', {'Bucket': b, 'Key': k}, ExpiresIn=t)` | `generate_blob_sas(account, container, blob, permission=BlobSasPermissions(read=True), expiry=...)` |
| `s3.list_objects_v2(Bucket=b, Prefix=p, MaxKeys=n)` | `container_client.list_blobs(name_starts_with=p, results_per_page=n)` |
| `response['Contents'][i]['Key']` | `blob.name` |
| `response['Contents'][i]['Size']` | `blob.size` |
| `s3.head_object(Bucket, Key)['Metadata']` | `blob_client.get_blob_properties().metadata` |
| `s3.delete_object(Bucket, Key)` | `container_client.delete_blob(blob_name)` |
| `ClientError` (botocore) | `ResourceNotFoundError` (azure.core.exceptions) |

---

### 4. Amazon S3 (WebsiteBucket) → Azure Static Web Apps

| Attribute | AWS S3 Static Website | Azure Static Web Apps |
|---|---|---|
| **Service** | Amazon S3 (website hosting) | Azure Static Web Apps |
| **Pricing** | ~$0.10/month (storage + minimal requests) | **Free** (Free tier) |
| **CDN** | None (direct S3 endpoint) | Built-in global CDN |
| **Custom domain** | Requires Route 53 + CloudFront setup | Built-in, included in Free tier (2 custom domains) |
| **HTTPS** | No (S3 website endpoint is HTTP only) | **HTTPS enforced by default** |
| **Index document** | `app.html` | `index.html` — must rename |
| **Error document** | `error.html` | Configurable via `staticwebapp.config.json` |
| **URL** | `http://image-upload-websitebucket-vd866vxtcs1z.s3-website-ap-southeast-2.amazonaws.com` | `https://<unique>.azurestaticapps.net` |
| **Public access** | Public read bucket policy | Publicly accessible by default |
| **Deployment** | Manual `aws s3 cp` or CloudFormation | GitHub Actions CI/CD (azure/static-web-apps-deploy@v1) |
| **Preview environments** | Not supported | Supported (staging environments per PR) |

**Migration steps:**
1. Create Static Web App resource (Free tier, Australia East)
2. Rename `app.html` → `index.html` (SWA requirement)
3. Update SPA JavaScript: replace `API_URL` with `https://photo-gallery-func.azurewebsites.net/api`
4. Replace AWS SDK imports and SigV4 signing with simple `fetch()` + `x-functions-key` header
5. Remove hard-coded IAM access key (`AKIAXZEFIIOD2OIWPRPK`) — **critical security step**
6. Deploy via GitHub Actions workflow using SWA deployment token

---

### 5. IAM Role (LambdaExecutionRole) → System-assigned Managed Identity + RBAC

| Attribute | AWS IAM Role | Azure Managed Identity |
|---|---|---|
| **Service** | AWS IAM | Azure Managed Identities (Azure AD) |
| **Type** | Role assumed by Lambda service principal | System-assigned to Function App |
| **Scope** | `arn:aws:iam::535002891143:role/image-upload-LambdaExecutionRole-2MhYmRQ3aAnA` | System-assigned MI on `photo-gallery-func` |
| **Policies** | AWSLambdaBasicExecutionRole (managed) + S3Access (inline: PutObject, GetObject, DeleteObject, ListBucket on ImageBucket) | No policies; uses RBAC role assignments |
| **RBAC equivalent** | N/A | `Storage Blob Data Contributor` (ID: ba92f5b4-2d11-453d-a403-e96b0029c9fe) on Storage Account |
| **Credentials** | Temporary STS tokens (auto-rotated) | Managed by Azure AD (no credentials to manage) |
| **Logging permission** | AWSLambdaBasicExecutionRole → CloudWatch | Application Insights auto-wired via app setting |
| **Code change** | `boto3.client('s3')` uses implicit role creds | `BlobServiceClient(..., DefaultAzureCredential())` resolves MI |

**Bicep resource:**
```bicep
// In rbac.bicep:
var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccountId, principalId, storageBlobDataContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalId: principalId  // Function App MI principal ID
    principalType: 'ServicePrincipal'
  }
}
```

---

### 6. IAM User + Access Key (SPA auth) → Function App Key

| Attribute | AWS IAM User | Azure Functions Key |
|---|---|---|
| **Resource** | `image-upload-api-user` (ARN: `arn:aws:iam::535002891143:user/image-upload-api-user`) | Function App default key |
| **Access key** | `AKIAXZEFIIOD2OIWPRPK` (**CRITICAL: hard-coded in SPA browser code**) | Function App default key (not hard-coded; injected at deploy time) |
| **Auth mechanism** | SigV4 signature on all API requests | `x-functions-key: <key>` HTTP header |
| **Permission** | `execute-api:Invoke` on `image-upload-api/*` | Function-level `authLevel="function"` |
| **Risk** | **CRITICAL** — static key in browser code is visible to any user who inspects the page | MEDIUM — function key in SPA config; visible to browser but easier to rotate |
| **Rotation** | Manual key rotation; requires SPA rebuild | `az functionapp keys renew` + SPA config update (automate via CI/CD) |
| **Future upgrade path** | N/A (deprecated) | Azure AD B2C / Entra External ID for per-user identity |

**Security improvement:** This migration eliminates the critical security vulnerability of a static IAM access key (AKIAXZEFIIOD2OIWPRPK) embedded in client-side JavaScript. While the Function App key is still a shared secret, it:
1. Is not an IAM principal with broad AWS permissions
2. Can be rotated without infrastructure changes
3. Has no ability to access Azure resources directly (only invokes the function)
4. Can be migrated to Azure AD authentication in a future sprint

---

### 7. AWS CloudFormation → Azure Bicep

| Attribute | AWS CloudFormation | Azure Bicep |
|---|---|---|
| **Language** | YAML / JSON (CloudFormation template) | Bicep (domain-specific language for ARM) |
| **Deployment scope** | Stack (ap-southeast-2, account 535002891143) | Resource Group (`rg-photo-gallery-<env>`) |
| **State management** | CloudFormation managed | Azure Resource Manager managed |
| **Modularisation** | Nested stacks / CloudFormation modules | Bicep modules (`module` keyword) |
| **Parameters** | `Parameters` section in template | `param` declarations in module; `.bicepparam` files |
| **Outputs** | `Outputs` section | `output` declarations |
| **Conditional resources** | `Condition` + `Fn::If` | `if` expressions or `?:` ternary |
| **CLI command** | `aws cloudformation deploy` | `az deployment group create` |
| **Template file** | `source-app/app-code/template.yaml` | `outputs/bicep-templates/main.bicep` |

**CloudFormation → Bicep resource mapping:**

| CloudFormation Logical ID | Resource Type | Bicep Module | Bicep Resource Type |
|---|---|---|---|
| `ImageBucket` | `AWS::S3::Bucket` | `storage.bicep` | `Microsoft.Storage/storageAccounts` + `/blobServices/containers` |
| `WebsiteBucket` | `AWS::S3::Bucket` | `staticWebApp.bicep` | `Microsoft.Web/staticSites` |
| `ImageUploadApi` | `AWS::Serverless::Api` | N/A (built into Functions) | — |
| `UploadFunction` + 3 others | `AWS::Serverless::Function` | `functionApp.bicep` | `Microsoft.Web/sites` (kind: functionapp,linux) |
| `LambdaExecutionRole` | `AWS::IAM::Role` | `identity.bicep` + `rbac.bicep` | System-assigned MI + `Microsoft.Authorization/roleAssignments` |
| `ApiGatewayCloudWatchLogsRole` | `AWS::IAM::Role` | N/A — not needed in Azure | — |
| (implicit) CloudWatch log groups | `AWS::Logs::LogGroup` | `monitoring.bicep` | `Microsoft.OperationalInsights/workspaces` + `Microsoft.Insights/components` |

---

### 8. Amazon CloudWatch Logs → Application Insights + Log Analytics

| Attribute | AWS CloudWatch | Azure Monitor |
|---|---|---|
| **Log storage** | CloudWatch Log Groups | Log Analytics Workspace |
| **Log agents** | Lambda runtime (automatic) | Application Insights SDK (automatic via app setting) |
| **Query language** | CloudWatch Logs Insights (SQL-like) | Kusto Query Language (KQL) |
| **Distributed tracing** | X-Ray (PassThrough mode — disabled) | Application Insights (enabled by default) |
| **Metrics** | CloudWatch Metrics | Azure Monitor Metrics |
| **Alarms** | CloudWatch Alarms | Azure Monitor Metric Alerts |
| **Cost** | ~$0.50/month (ingestion + storage) | **$0.00/month** (within 5 GB free tier) |
| **Setup required** | Automatic (Lambda auto-creates log groups) | Set `APPLICATIONINSIGHTS_CONNECTION_STRING` app setting |

**KQL equivalents for common CloudWatch queries:**

| CloudWatch Insights Query | Azure KQL Equivalent |
|---|---|
| `fields @timestamp, @message \| sort @timestamp desc \| limit 20` | `traces \| order by timestamp desc \| take 20` |
| `filter @message like /ERROR/` | `traces \| where message contains "ERROR"` |
| `stats count(*) by bin(5m)` | `requests \| summarize count() by bin(timestamp, 5m)` |
| `filter @duration > 5000` | `requests \| where duration > 5000` |

---

## Out-of-Scope Resources (Not Migrated)

| AWS Resource | Reason |
|---|---|
| `appstream-app-settings-ap-southeast-2-535002891143-ar2b5jb0` | AWS AppStream 2.0 managed bucket — not part of application |
| `appstream2-36fb080bb8-ap-southeast-2-535002891143-hwzroy6c` | AWS AppStream 2.0 managed bucket — not part of application |
| 2× CloudWatch AppStream alarms | AppStream managed — no Azure equivalent needed |
| 11× EventBridge SSMOpsItems rules | AWS Systems Manager defaults — not application infrastructure |
| 6× Orphaned CloudWatch log groups (v1/v2) | From deleted stacks — decommission on AWS side only |
| 4× Human IAM users (Arinco team) | Personnel accounts — no Azure migration required; manage via Entra ID separately |
| `image-upload-ApiGatewayCloudWatchLogsRole-YGFCwY9oRVqq` | API GW logging role — not needed; Application Insights handles this in Azure |

---

## Migration Risk Summary

| AWS Service | Risk Level | Risk Description | Mitigation |
|---|---|---|---|
| Lambda → Functions | LOW | Handler signature change; boto3 → azure SDK | Direct SDK swap; well-documented APIs |
| API Gateway → HTTP triggers | LOW | No separate service needed; route prefix changes | Simple URL update in SPA |
| S3 (images) → Blob | LOW-MEDIUM | Presigned POST → SAS PUT; SPA upload flow changes | SPA JS update required; test thoroughly |
| S3 (website) → SWA | LOW | Rename app.html → index.html; HTTPS-only | Trivial file rename |
| IAM Role → MI | LOW | DefaultAzureCredential() is a drop-in; Bicep handles RBAC | Well-understood pattern |
| IAM User → Function key | MEDIUM | SPA must be refactored to remove AWS SDK; auth flow changes | **Do not go live until key is removed** |
| CloudFormation → Bicep | LOW | Different syntax; same concepts | Template rewrite is straightforward for this scope |
| CloudWatch → Application Insights | LOW | KQL vs CloudWatch Insights; no code changes needed | App setting wires telemetry automatically |
