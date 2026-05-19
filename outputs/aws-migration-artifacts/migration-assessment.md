# AWS to Azure Migration Assessment — Image Upload Photo Gallery

**Assessment Date:** 2026-05-19  
**AWS Account:** 535002891143  
**Primary Region:** ap-southeast-2 (Sydney, Australia)  
**Discovery Method:** Live AWS API discovery (AWS CLI) + CloudFormation template analysis  
**Stack Name:** `image-upload` (CREATE_COMPLETE)  
**Assessed By:** AWS Discovery Agent (aws-discovery mode)  

---

## Executive Summary

The workload is a **serverless photo gallery application** deployed entirely on AWS managed services with no EC2 instances, no databases, and no message queuing. The architecture is simple and well-suited for a direct lift-and-shift to equivalent Azure serverless services.

| Attribute | Value |
|---|---|
| **Total Resources (in scope)** | 14 |
| **Services in scope** | 4 (Lambda, API Gateway, S3 ×2, IAM) |
| **Architecture Pattern** | Serverless — API-first with S3 pre-signed URLs |
| **Complexity** | **LOW** |
| **Estimated Effort** | **2–3 weeks** for 1–2 engineers |
| **Estimated Azure Monthly Cost** | ~$3–6 USD (Consumption plan, <1M requests/month) |
| **Recommended Approach** | Direct migration (AWS→Azure SDK swap + IaC rewrite) |
| **Critical Blocker** | IAM user with static key embedded in SPA must be replaced |

---

## Discovered Resource Inventory

### In-Scope Application Resources (14)

| Resource Name | Type | ARN / ID | Criticality |
|---|---|---|---|
| image-upload-UploadFunction-iIIJ7xiZECuB | Lambda (Python 3.11) | arn:aws:lambda:ap-southeast-2:535002891143:function:image-upload-UploadFunction-iIIJ7xiZECuB | HIGH |
| image-upload-ListFilesFunction-Pb0dKq9dR0Is | Lambda (Python 3.11) | arn:aws:lambda:ap-southeast-2:535002891143:function:image-upload-ListFilesFunction-Pb0dKq9dR0Is | HIGH |
| image-upload-GetViewUrlFunction-yMGI9X8Us5Em | Lambda (Python 3.11) | arn:aws:lambda:ap-southeast-2:535002891143:function:image-upload-GetViewUrlFunction-yMGI9X8Us5Em | MEDIUM |
| image-upload-DeleteFileFunction-EG7Cfj3m2P6f | Lambda (Python 3.11) | arn:aws:lambda:ap-southeast-2:535002891143:function:image-upload-DeleteFileFunction-EG7Cfj3m2P6f | HIGH |
| image-upload-imagebucket-t8isnbr8sswv | S3 Bucket (image store) | arn:aws:s3:::image-upload-imagebucket-t8isnbr8sswv | CRITICAL |
| image-upload-websitebucket-vd866vxtcs1z | S3 Bucket (static website) | arn:aws:s3:::image-upload-websitebucket-vd866vxtcs1z | MEDIUM |
| image-upload-api (4lrh2l7i86) | API Gateway REST (REGIONAL) | arn:aws:apigateway:ap-southeast-2::/restapis/4lrh2l7i86 | CRITICAL |
| image-upload-LambdaExecutionRole-2MhYmRQ3aAnA | IAM Role | arn:aws:iam::535002891143:role/image-upload-LambdaExecutionRole-2MhYmRQ3aAnA | CRITICAL |
| image-upload-ApiGatewayCloudWatchLogsRole-YGFCwY9oRVqq | IAM Role | arn:aws:iam::535002891143:role/image-upload-ApiGatewayCloudWatchLogsRole-YGFCwY9oRVqq | LOW |
| image-upload-api-user | IAM User | arn:aws:iam::535002891143:user/image-upload-api-user | CRITICAL |
| image-upload | CloudFormation Stack | arn:aws:cloudformation:ap-southeast-2:535002891143:stack/image-upload | HIGH |
| /aws/lambda/image-upload-UploadFunction-* | CloudWatch Log Group | — | MEDIUM |
| /aws/lambda/image-upload-ListFilesFunction-* | CloudWatch Log Group | — | MEDIUM |
| API-Gateway-Execution-Logs_4lrh2l7i86/dev | CloudWatch Log Group | — | LOW |

### Out-of-Scope Resources (not migrated)

| Resource | Reason |
|---|---|
| appstream-app-settings-ap-southeast-2-535002891143-ar2b5jb0 | AWS AppStream 2.0 managed bucket |
| appstream2-36fb080bb8-ap-southeast-2-535002891143-hwzroy6c | AWS AppStream 2.0 managed bucket |
| 2× CloudWatch AppStream alarms | AppStream managed, not application |
| 11× EventBridge SSMOpsItems rules | AWS Systems Manager default rules |
| 6× Remnant CloudWatch log groups (v1/v2) | Orphaned from deleted stacks |
| 4× Human IAM users | Arinco team members — no Azure equivalents needed |

---

## Service Complexity Matrix

| AWS Service | Resource Count | Complexity | Effort (Days) | Azure Equivalent | Key Differences |
|---|---|---|---|---|---|
| **Lambda (Python 3.11)** | 4 | **LOW** | 3 | Azure Functions (Python, Consumption) | boto3 → azure-storage-blob SDK swap; event dict shape compatible; pre-signed URL API differs |
| **API Gateway REST** | 1 (4 endpoints) | **LOW** | 1 | Azure Functions HTTP Triggers (built-in) | No separate API GW service needed; HTTP trigger replaces each method; CORS config differs |
| **S3 (image storage)** | 1 | **LOW** | 1 | Azure Blob Storage (container) | Key pattern `{uuid}/{filename}` preserved; CORS config minor diff; SAS replaces pre-signed URL |
| **S3 (static website)** | 1 | **LOW** | 1 | Azure Static Web Apps or Blob static hosting | Azure Static Web Apps adds free CDN + CI/CD; `app.html` index doc needs `index.html` rename |
| **IAM Roles** | 2 | **LOW** | 0.5 | Azure Managed Identity + RBAC role assignments | System-assigned MI on Function App; `Storage Blob Data Contributor` replaces IAM S3 policy |
| **IAM User + Access Key** | 1 | **MEDIUM** | 1.5 | Azure AD App Registration or API key | **Security refactor required** — static key must be replaced; SPA auth model must change |
| **CloudFormation** | 1 stack | **LOW** | 2 | Azure Bicep | Template rewrite; outputs map to Bicep outputs; same parameter concept |
| **CloudWatch Logs** | 3 log groups | **LOW** | 0.5 | Azure Monitor + Application Insights | Built-in with Azure Functions; no explicit config needed |
| **Total** | **14** | **LOW** | **~9–10 days** | — | 2 weeks with testing |

---

## API Endpoints Inventory

| AWS Endpoint | Method | Auth | Lambda Function | Azure Equivalent |
|---|---|---|---|---|
| `POST /upload` | POST | AWS_IAM | UploadFunction | `POST /api/upload` — HTTP Trigger |
| `GET /files` | GET | AWS_IAM | ListFilesFunction | `GET /api/files` — HTTP Trigger |
| `GET /files/{fileId}/view-url` | GET | AWS_IAM | GetViewUrlFunction | `GET /api/files/{fileId}/view-url` — HTTP Trigger |
| `DELETE /files/{fileId}` | DELETE | AWS_IAM | DeleteFileFunction | `DELETE /api/files/{fileId}` — HTTP Trigger |
| `OPTIONS /*` | OPTIONS | NONE | MOCK integration | Built-in CORS in Azure Functions host.json |

**Current Auth:** AWS_IAM (SigV4 Signature v4) using static IAM user credentials embedded in the SPA.  
**Azure Auth Recommendation:** Replace with Azure AD B2C or Function-level API key passed via header. For a demo/internal tool, a shared Function App key (x-functions-key) is simplest.

---

## Application Architecture Analysis

### Data Flow (Current AWS)
```
Browser → S3 Website (app.html)
Browser → API Gateway (SigV4 signed) → Lambda → S3 (list/generate URL/delete)
Browser → S3 ImageBucket (presigned POST URL for direct upload)
```

### Data Flow (Target Azure)
```
Browser → Azure Static Web Apps (or Blob static hosting)
Browser → Azure Functions HTTP API (function key or Azure AD auth) → Function → Blob Storage
Browser → Azure Blob Storage (SAS URL for direct upload)
```

### Key Technical Observations
1. **S3 Pre-signed POST → Azure SAS Token**: The `upload_handler.py` uses `generate_presigned_post()` which returns a URL + form fields dictionary. Azure equivalent is `generate_blob_sas()` returning a SAS URL. The SPA upload flow must change from multipart POST to direct PUT with SAS URL.
2. **Object Key Pattern**: Files stored as `{uuid4}/{original_filename}` — preserved on Azure as blob name with same pattern.
3. **Metadata**: Stored in `x-amz-meta-*` headers on S3 → Azure stores custom metadata in `blob.metadata` dict. Field names are compatible after stripping the `x-amz-meta-` prefix.
4. **CORS**: Both AWS (S3 + API Gateway) and Azure (Blob + Functions host.json) support permissive CORS. Origin restriction should be tightened in production.
5. **URL Expiration**: Hardcoded `URL_EXPIRATION=3600` (1 hour) applies to both presigned URLs and SAS tokens; compatible.
6. **No State / No DB**: The application is stateless with S3/Blob as the only persistence layer. This eliminates database migration complexity entirely.

---

## Critical Path Analysis

### Phase 1: Infrastructure Setup (Days 1–2)
- Provision Azure Resource Group (ap-southeast-2 equivalent: Australia East)
- Create Azure Storage Account + blob container (`images`)
- Create Azure Function App (Python 3.11, Consumption plan)
- Assign system-assigned Managed Identity + `Storage Blob Data Contributor` role
- Create Application Insights workspace
- **Dependency**: Must complete before Phase 2

### Phase 2: Code Refactor (Days 3–5)
- Install `azure-functions`, `azure-storage-blob`, `azure-identity` packages
- Replace `boto3` S3 calls with `azure-storage-blob` in all 4 handlers
- Update `lambda_handler(event, context)` → `main(req: func.HttpRequest)`
- Replace `generate_presigned_post` → `generate_blob_sas` + SAS URL
- Replace `list_objects_v2` → `list_blobs(name_starts_with=...)`
- Replace `generate_presigned_url` → `generate_blob_sas(permission=read)`
- Replace `delete_objects` → loop `BlobClient.delete_blob()`
- **Dependency**: Phase 1 storage account URL/connection needed for env vars

### Phase 3: Static Front-End Migration (Day 6)
- Create Azure Static Web Apps resource (free tier)
- Update SPA config: replace API URL, remove AWS credentials
- Replace SigV4 signing with Function App key header (`x-functions-key`)
- Rename `app.html` → `index.html` for Static Web Apps compatibility
- Deploy static files
- **Dependency**: Azure Functions endpoint URL from Phase 2

### Phase 4: IaC & Deployment Pipeline (Days 7–8)
- Write `main.bicep` with modules for Storage, Function App, Static Web App, RBAC
- Create dev/staging/prod parameter files
- Write GitHub Actions CI/CD workflow
- **Dependency**: Phases 1–3 validated

### Phase 5: Testing & Cutover (Days 9–10)
- Functional smoke tests: upload, list, view, delete
- Performance test: cold start latency (Consumption plan)
- DNS / URL cutover (if custom domain)
- Decommission AWS stack

---

## Risk Assessment

### High Risk Items

| Risk | Impact | Mitigation |
|---|---|---|
| **IAM User static key in SPA** — AKIAXZEFIIOD2OIWPRPK hardcoded in browser code; CloudFormation output exposes secret key | **CRITICAL security** | Replace with Azure AD token or Function App key before going live; do not preserve current auth pattern |
| **S3 pre-signed POST → Azure SAS PUT** — The upload flow must change from multipart POST (form fields) to direct PUT; SPA JavaScript must be refactored | HIGH functional | Careful SPA testing; SAS URL expiry logic must match |

### Medium Risk Items

| Risk | Impact | Mitigation |
|---|---|---|
| **CORS wildcard** — `AllowedOrigins: ['*']` on both S3 and API Gateway | MEDIUM security | Restrict to known domain in production Azure deployment |
| **Cold start latency** — Consumption plan has cold starts; current Lambda 256 MB with 30 s timeout may behave differently on Azure Consumption plan | MEDIUM perf | Monitor Application Insights; consider Premium plan if cold starts > acceptable |
| **URL signing differences** — Azure SAS token format and expiry behaviour differ subtly from S3 presigned | MEDIUM functional | Thorough testing of upload and view flows |

### Low Risk Items

- S3 versioning enabled on ImageBucket — Azure Blob Storage supports versioning; configure if required
- CloudWatch log format — Application Insights equivalent queries must be rewritten in KQL (straightforward)
- Region change: ap-southeast-2 (Sydney) → Australia East — <10 ms latency change for Australian users; acceptable

---

## Azure Service Mapping

| AWS Service | Azure Equivalent | Notes |
|---|---|---|
| AWS Lambda (Python 3.11) | Azure Functions v2 (Python 3.11, Consumption plan) | Direct equivalent; same programming model |
| Amazon API Gateway REST | Azure Functions HTTP Triggers (built-in routing) | No separate API Management needed for this workload |
| Amazon S3 (image storage) | Azure Blob Storage (Standard LRS, Hot tier) | Container `images`; same `{uuid}/{name}` key pattern |
| Amazon S3 (static website) | Azure Static Web Apps (Free tier) | Free CDN included; CI/CD via GitHub Actions |
| IAM Role (Lambda execution) | System-assigned Managed Identity + RBAC | `Storage Blob Data Contributor` on Storage Account |
| IAM User + Access Key (SPA auth) | Azure AD App Registration OR Function App key | Requires SPA code change |
| AWS CloudFormation | Azure Bicep | Template rewrite (~1 day); same declarative model |
| Amazon CloudWatch Logs | Azure Monitor (Application Insights + Log Analytics) | Built-in with Function App; no explicit setup |
| Amazon CloudWatch Alarms | Azure Monitor Metric Alerts | Optional; recreate if needed |

---

## Cost Comparison

| Service | AWS Current (est.) | Azure Target (est.) |
|---|---|---|
| Lambda / Functions | ~$0.30/month | ~$0.00–0.20/month (first 1M free) |
| API Gateway | ~$0.35/month | Included in Functions HTTP trigger |
| S3 ImageBucket | ~$1.50/month | ~$1.00/month (LRS, Hot) |
| S3 WebsiteBucket | ~$0.10/month | **Free** (Static Web Apps free tier) |
| CloudWatch Logs | ~$0.50/month | ~$0.20/month (Log Analytics) |
| IAM/Security | ~$0.00 | ~$0.00 |
| **Total (estimated)** | **~$2.75–3.50/month** | **~$1.40–2.00/month** |

*Estimates based on low traffic (<100K requests/month, <1 GB stored). Actual costs vary.*

---

## Dependency Groups

### Cannot Migrate in Parallel (Sequential)
1. **Storage** (Azure Blob Storage) — foundational; needed before Functions can be configured
2. **Identity** (Managed Identity + RBAC) — blocks Functions from accessing storage
3. **Compute** (Azure Functions) — depends on storage connection string / MI
4. **Front-End** (Static Web Apps) — depends on Functions endpoint URL

### Can Migrate in Parallel
- All four Function handlers can be refactored simultaneously (independent code files)
- Bicep templates can be written while code is being refactored
- Tests can be developed alongside refactoring

---

## Migration Order (Resource Level)

| Order | Resource | Phase | Notes |
|---|---|---|---|
| 1 | Azure Resource Group | Phase 1 | Foundation |
| 1 | Azure Storage Account + container | Phase 1 | Must exist before Functions |
| 1 | System-assigned Managed Identity | Phase 1 | Created with Function App |
| 1 | Storage Blob Data Contributor role assignment | Phase 1 | Blocks code |
| 2 | Azure Functions (all 4 handlers) | Phase 2 | After storage |
| 2 | Application Insights | Phase 2 | Optional for dev |
| 3 | Azure Static Web Apps | Phase 3 | After Functions URL known |
| 3 | SPA JavaScript config update | Phase 3 | API URL + auth |
| 4 | Bicep IaC | Phase 4 | Automates all above |
| 4 | GitHub Actions CI/CD | Phase 4 | Optional |
| 5 | DNS/URL cutover + AWS decommission | Phase 5 | Final |

---

## Security Recommendations for Azure Migration

1. **Replace IAM user static key with Managed Identity**: The `image-upload-api-user` (AKIAXZEFIIOD2OIWPRPK) is a critical security risk. Long-lived access keys in browser code are easily extracted. On Azure, use MSAL + Azure AD for end-user authentication or Function App keys (stored in Key Vault, not in SPA source).
2. **Restrict CORS origins**: Move from `AllowedOrigins: ['*']` to the specific Static Web Apps domain.
3. **Enable Blob versioning**: If audit trail of image modifications is required, enable Azure Blob versioning (equivalent to current S3 versioning).
4. **Key Vault for connection strings**: Store the Azure Storage connection string or account key in Azure Key Vault; reference via Managed Identity from Function App app settings.
5. **Enable Application Insights**: Turn on distributed tracing (replaces X-Ray PassThrough mode).

---

## Next Steps

1. **✅ Discovery Complete** — This assessment provides full inventory and migration plan
2. **Phase 2 — Architecture Design**: Review Azure service mapping; finalize Azure region (Australia East recommended for ap-southeast-2 parity)
3. **Phase 3a — IaC Transformation**: Generate `main.bicep` for all Azure resources
4. **Phase 3b — Code Refactor**: AWS SDK → Azure SDK swap in all 4 handlers
5. **Phase 4 — Validation**: Deploy to dev slot, run smoke tests, validate pre-signed URL flow
6. **Phase 5 — Cutover**: Point DNS to Azure Static Web Apps; keep AWS stack 2 weeks for rollback

---

## Appendix: Live Discovered Resource IDs

| Resource | Live ARN / ID |
|---|---|
| UploadFunction | `arn:aws:lambda:ap-southeast-2:535002891143:function:image-upload-UploadFunction-iIIJ7xiZECuB` |
| ListFilesFunction | `arn:aws:lambda:ap-southeast-2:535002891143:function:image-upload-ListFilesFunction-Pb0dKq9dR0Is` |
| GetViewUrlFunction | `arn:aws:lambda:ap-southeast-2:535002891143:function:image-upload-GetViewUrlFunction-yMGI9X8Us5Em` |
| DeleteFileFunction | `arn:aws:lambda:ap-southeast-2:535002891143:function:image-upload-DeleteFileFunction-EG7Cfj3m2P6f` |
| ImageBucket | `image-upload-imagebucket-t8isnbr8sswv` |
| WebsiteBucket | `image-upload-websitebucket-vd866vxtcs1z` |
| API Gateway | `4lrh2l7i86` / `image-upload-api` |
| API URL | `https://4lrh2l7i86.execute-api.ap-southeast-2.amazonaws.com/dev` |
| Website URL | `http://image-upload-websitebucket-vd866vxtcs1z.s3-website-ap-southeast-2.amazonaws.com` |
| Lambda Execution Role | `image-upload-LambdaExecutionRole-2MhYmRQ3aAnA` |
| API GW Logs Role | `image-upload-ApiGatewayCloudWatchLogsRole-YGFCwY9oRVqq` |
| API IAM User | `image-upload-api-user` / `AKIAXZEFIIOD2OIWPRPK` |
| CloudFormation Stack | `image-upload` (ap-southeast-2, CREATE_COMPLETE) |

---

**Prepared by:** AWS Discovery Agent (aws-discovery mode)  
**Confidence Level:** High — all resource IDs verified against live AWS account 535002891143  
**Validation Required:** Human architect review before Phase 2 execution  
