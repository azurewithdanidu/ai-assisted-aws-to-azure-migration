# AWS → Azure Service Mapping

**Workload:** Image Upload Service (single SAM stack)
**Source region:** ap-southeast-2 (Sydney)
**Target region:** Australia East (closest paired region, lowest egress latency)
**Design priority:** Cost optimization (default to Consumption / Free tiers; APIM explicitly excluded)

## 1. Service-by-Service Mapping

| # | AWS Service | AWS Configuration | Azure Equivalent | Azure Configuration | Migration Notes |
|---|---|---|---|---|---|
| 1 | **API Gateway REST** (1 API, 4 routes, IAM SigV4) | Regional, INFO logging, X-Ray on | **Azure Functions HTTP Trigger** (Consumption Y1) — *NOT APIM* | `authLevel: function`, route prefix `api`, function keys for client auth | API Gateway features used (proxy integration + IAM auth) map cleanly to native Functions HTTP triggers. APIM would add ~$50+/mo for zero feature gain. |
| 2 | **Lambda — UploadFunction** | Python 3.11, 256 MB, 30 s | **Azure Function — Upload** | Same runtime; Consumption plan; HTTP trigger `POST /api/upload` | Rewrite `boto3.client('s3').generate_presigned_url('put_object')` → `generate_blob_sas` with User Delegation Key |
| 3 | **Lambda — ListFilesFunction** | Python 3.11, 256 MB, 30 s | **Azure Function — ListFiles** | Same; HTTP trigger `GET /api/files` | Rewrite `list_objects_v2` → `container_client.list_blobs()` |
| 4 | **Lambda — GetViewUrlFunction** | Python 3.11, 256 MB, 30 s | **Azure Function — GetViewUrl** | Same; HTTP trigger `GET /api/files/{fileId}/view-url` | Rewrite presigned GET → User Delegation SAS read |
| 5 | **Lambda — DeleteFileFunction** | Python 3.11, 256 MB, 30 s | **Azure Function — DeleteFile** | Same; HTTP trigger `DELETE /api/files/{fileId}` | Rewrite `delete_object` → `blob_client.delete_blob` |
| 6 | **S3 ImageBucket** | SSE-S3 AES256, versioning ON, public access blocked, CORS `*` | **Azure Blob Storage container `images`** | Storage Account `Standard_LRS`, StorageV2, MS-managed encryption, blob versioning ON, soft delete 7d, CORS restricted to SWA origin | 1:1 mapping; tighten CORS post-cutover |
| 7 | **S3 WebsiteBucket** | Static website hosting, public read | **Azure Static Web Apps (Free SKU)** | Auto-HTTPS, global CDN, GitHub Actions integration | Free SKU sufficient; provides TLS+CDN that S3 lacked |
| 8 | **IAM LambdaExecutionRole** | Trust `lambda.amazonaws.com`; S3 inline policy | **User-Assigned Managed Identity** | Role assignments: `Storage Blob Data Contributor` on container, `Storage Blob Delegator` on account, `Key Vault Secrets User` on KV | Identity-based; no secrets |
| 9 | **IAM ApiUser + Access Key** | Long-lived static SigV4 key | **Function host key** (default) or **Entra ID Easy Auth** (optional upgrade) | Function key passed in `x-functions-key` header | Eliminates long-lived static AWS keys. Future: Entra ID app reg for B2B scenarios |
| 10 | **IAM ApiGatewayCloudWatchLogsRole** | API GW → CW Logs | **N/A** — Functions ship telemetry natively via App Insights binding | — | No equivalent role needed |
| 11 | **CloudWatch Logs (4 groups)** | Never expire | **Application Insights + Log Analytics workspace** | LAW SKU `PerGB2018`, retention **30 days** (cost control) | App Insights connected to Function App via `APPLICATIONINSIGHTS_CONNECTION_STRING` |
| 12 | **X-Ray** | API GW tracing | **Application Insights distributed tracing** | Auto-instrumented by Functions Python worker | Sampling at 100% for dev, 5% for prod |
| 13 | **CloudFormation stack** | SAM template `image-upload` | **Bicep modules + main.bicep** | Subscription-scope deployment; modular (storage / functions / monitoring / identity / swa / keyvault) | Source SAM template available for reference |

## 2. Configuration Differences

### Authentication
- **AWS:** SigV4 signing of every request using long-lived IAM access key embedded in the browser SPA.
- **Azure:** Function host key sent as `x-functions-key` header. Key is stored in Key Vault and surfaced to the SWA build via a GitHub Actions environment variable.

### Presigned URLs
- **AWS:** `boto3.client('s3').generate_presigned_url(...)` — single-call, signed with the caller's IAM credentials.
- **Azure:** Two-step pattern — (1) `BlobServiceClient.get_user_delegation_key(...)` then (2) `generate_blob_sas(user_delegation_key=...)`. The delegation key is valid up to 7 days and is cached in the Function host (module-level singleton with TTL).

### Storage Account Naming
- Azure Storage Account names must be **3-24 chars, lowercase, alphanumeric only**. Use `stimgupload<env>` (e.g. `stimguploaddev`).

### Region Mapping
- `ap-southeast-2` (Sydney AWS) → `australiaeast` (Sydney Azure) — geographically co-located, lowest data-transfer cost.

## 3. Number of Instances / Resources

| Azure Resource | Count per Environment | Total (dev + staging + prod) |
|---|---|---|
| Resource Group | 1 | 3 |
| Storage Account | 1 | 3 |
| Blob Container `images` | 1 | 3 |
| Function App (Consumption Y1) | 1 | 3 |
| Static Web App | 1 | 3 |
| User-Assigned Managed Identity | 1 | 3 |
| Key Vault | 1 | 3 |
| Application Insights | 1 | 3 |
| Log Analytics Workspace | 1 | 3 |

## 4. Migration Considerations

1. **Data migration:** Use `azcopy sync` from S3 → Blob container in two passes (initial + cutover delta).
2. **CORS tightening:** Post-deploy, restrict storage account CORS to the SWA hostname (was `*` in AWS).
3. **Log retention:** AWS log groups had `Never expire`. Default Azure to 30 days to control cost; bump per environment as required.
4. **Auth model upgrade path:** Function keys are pragmatic for dev parity. For production, recommend a follow-up to Easy Auth + Entra ID app registration (out of scope for this migration).
5. **SAS expiration:** Match the AWS `URL_EXPIRATION=3600` (1 h) for parity.
6. **Cold start:** Consumption Y1 has cold starts (1-3 s for Python). Acceptable for this low-traffic image service. Premium plan is unnecessary and explicitly avoided per cost-first design.
