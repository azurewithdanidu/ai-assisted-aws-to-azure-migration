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
