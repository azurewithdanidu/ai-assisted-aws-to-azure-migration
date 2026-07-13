# Azure Architecture Design Document — Image Upload Service

## 1. Executive Summary

This document defines the target Azure architecture for migrating the AWS **image-upload** application from **ap-southeast-2** to **australiasoutheast**. The source workload is a small serverless image upload service composed of four Python 3.11 Lambda functions, one private versioned S3 bucket for images, one public S3 website bucket for the SPA, one regional API Gateway REST API, IAM-based access, CloudWatch Logs, and X-Ray tracing.

The target design keeps the workload serverless and low-cost for the dev environment:

- **Azure Functions (Consumption Y1, Python 3.11)** for the API backend
- **Azure Blob Storage (StorageV2, LRS, Hot)** with private container `images`
- **Azure Static Web Apps (Free)** for the SPA frontend
- **Azure Monitor + Application Insights + Log Analytics** for telemetry
- **System-assigned Managed Identity** on the Function App for storage access
- **Azure Key Vault** as an optional but recommended secret store

### Key decisions

1. **Do not deploy API Management for dev.** Functions HTTP triggers are exposed directly to minimize cost and moving parts. APIM is deferred for production.
2. **Replace AWS_IAM + long-lived ApiUser keys with Microsoft Entra ID.** The frontend must stop using embedded AWS access keys and instead request Entra access tokens with MSAL.
3. **Replace S3 presigned POST with Azure Blob SAS upload PUT.** The upload contract changes from form POST fields to a SAS URL plus required headers.
4. **Keep the solution single-region.** No multi-region requirement was identified in the source assessment.

### Source-to-target cost intent

Current AWS spend is approximately **$4.80/month**. The Azure dev target should stay in a similar low range by using:

- Functions Consumption instead of Premium
- Static Web Apps Free
- Storage LRS Hot
- No APIM in dev

Telemetry ingestion volume must be capped to prevent Application Insights from becoming the largest cost driver.

## 2. Source AWS Baseline

### 2.1 Source inventory

| AWS component | Count | Current configuration | Migration relevance |
|---|---:|---|---|
| Lambda | 4 | Python 3.11, 256 MB, 30 sec | Directly maps to Azure Functions |
| S3 bucket (images) | 1 | Private, versioned, CORS, SSE-S3/AES256 | Maps to Blob Storage private container with versioning |
| S3 bucket (website) | 1 | Static website hosting for SPA | Maps to Static Web Apps |
| API Gateway REST API | 1 | Regional, stage `dev`, 4 routes, `AWS_IAM` auth | Maps to Function HTTP endpoints |
| IAM Role | 1 | LambdaExecutionRole | Maps to managed identity + RBAC |
| IAM User | 1 | ApiUser with long-lived key | Must be removed and replaced |
| CloudWatch Log Groups | 5 | Function/API logs | Maps to Azure Monitor / Log Analytics |
| X-Ray | 1 | API Gateway tracing only | Maps to Application Insights |
| CloudFormation stack | 1 | `image-upload` | Replaced by Bicep |

### 2.2 Current API surface

| Route | Source function | Behavior |
|---|---|---|
| `POST /upload` | `UploadFunction` | Generates S3 presigned POST for client upload |
| `GET /files` | `ListFilesFunction` | Lists objects, metadata, tags, presigned GET URLs |
| `GET /files/{fileId}/view-url` | `GetViewUrlFunction` | Finds blob by prefix and returns presigned GET URL |
| `DELETE /files/{fileId}` | `DeleteFileFunction` | Deletes one or more objects under prefix |

### 2.3 Current runtime behavior that must be preserved

- File IDs are UUID-based and used as the leading object key prefix.
- Metadata currently persisted:
  - `uploaddate`
  - `originalfilename`
  - `description` (optional)
- Tags are stored per object and returned by the list API.
- Upload expiry is currently controlled by `URL_EXPIRATION`, default `3600`.
- Maximum upload size enforced by the upload flow is **10 MB**.

### 2.4 Migration risk carried from source

The main source risk is the SPA’s current use of **AWS access key ID + secret access key** and SigV4 signing in the browser. This pattern must not be recreated in Azure. The target frontend must authenticate interactively with Entra ID and call the Function App with bearer tokens.

## 3. Target Azure Architecture

### 3.1 Target resource layout

| Azure resource | Planned name | SKU / tier | Purpose |
|---|---|---|---|
| Resource Group | `rg-image-upload` | n/a | Deployment boundary |
| Storage Account | `imguploaddevase` | StorageV2 / Standard_LRS / Hot | Function runtime storage + image blob container |
| Blob Container | `images` | Private | Image payloads |
| Function App | `img-upload-func-dev-ase` | Consumption Y1 / Python 3.11 | HTTP API |
| App Service Plan | `img-upload-plan-dev-ase` | Y1 | Functions hosting plan |
| Log Analytics Workspace | `img-upload-law-dev-ase` | PerGB2018 | Central logs |
| Application Insights | `img-upload-ai-dev-ase` | Workspace-based | App telemetry and tracing |
| Static Web App | `img-upload-swa-dev-ase` | Free | SPA hosting |
| Key Vault (optional) | `img-upload-kv-dev-ase` | Standard | Runtime secret references |

### 3.2 High-level flow

1. User opens the SPA hosted on **Azure Static Web Apps**.
2. SPA signs in with **Microsoft Entra ID** using MSAL.js.
3. SPA calls **Azure Functions** endpoints at `/api/...` with bearer tokens.
4. Functions use **system-assigned managed identity** to access **Blob Storage**.
5. Functions generate **user delegation SAS** URLs for upload/read access.
6. Browser uploads files directly to Blob Storage and reads images through SAS URLs.
7. Logs, requests, dependencies, and exceptions flow to **Application Insights** and **Log Analytics**.

### 3.3 Explicit architecture decision

**Chosen ingress:** direct Azure Functions HTTP triggers  
**Rejected for dev:** Azure API Management Consumption

Reason:

- lowest cost for the target workload
- simpler deployment and troubleshooting
- no need for policy routing or subscription keys in dev
- preserves the existing 4-route shape with minimal moving parts

Production extension:

- APIM can later front the Function App for JWT policy enforcement, centralized throttling, custom domains, and productization.

### 3.4 Non-functional targets

| Concern | Target design choice |
|---|---|
| Security | Entra auth for users, managed identity for service-to-service, private blob container, no embedded credentials |
| Reliability | Single-region serverless design, blob versioning enabled, soft-delete retention, App Insights monitoring |
| Cost | Consumption plan, LRS storage, SWA Free, no APIM in dev |
| Operational excellence | Full Bicep deployment, GitHub Actions with OIDC, centralized telemetry |
| Performance | Direct blob upload/download via SAS avoids proxying file bodies through Functions |

## 4. Azure Service Mapping and Design Decisions

| AWS service | Azure service | Final decision | Notes |
|---|---|---|---|
| Lambda | Azure Functions | **Adopt** | 4 HTTP-triggered Python functions on Consumption |
| S3 (private image bucket) | Azure Blob Storage | **Adopt** | Private container `images`, blob versioning, CORS, SSE at rest |
| S3 static website | Azure Static Web Apps | **Adopt** | Better HTTPS/CDN experience than Blob static website |
| API Gateway REST API | Functions HTTP endpoints | **Adopt** | No APIM in dev; preserve route structure |
| IAM role for Lambda | Managed Identity + RBAC | **Adopt** | Function App MI gets Storage Blob Data Contributor |
| IAM user with access key | Entra ID app registrations | **Replace** | Browser must use OAuth2/OIDC instead of stored secrets |
| CloudWatch Logs | Azure Monitor Logs | **Adopt** | Workspace-based telemetry |
| X-Ray | Application Insights | **Adopt** | Request/dependency tracing |
| CloudFormation | Bicep | **Adopt** | Modularized under `main.bicep` and `modules/` |

### 4.1 Design trade-offs

| Decision | Benefit | Trade-off |
|---|---|---|
| Functions-only ingress | Lowest cost, simplest dev topology | Fewer gateway policies and less central throttling |
| Static Web Apps Free | No-cost SPA hosting with HTTPS | No enterprise edge features in dev |
| Single storage account | Cheapest and simplest | Runtime and app data share one account |
| User delegation SAS | No storage keys in code | Requires managed identity and SAS generation logic |
| Entra auth on Function App | Removes long-lived secrets | Frontend rewrite required |

### 4.2 Consulted project guidance

- `.github/instructions/azure-architecture.instructions.md`
- `.github/skills/agents/azure-architect/architecture-design.md`
- `.github/skills/agents/shared/aws-to-azure-mapping.md`
- `.github/skills/agents/code-refactor/lambda-to-functions.md`
- `.github/skills/agents/pipeline-builder/github-actions-oidc.md`

No service-specific `/.github/skills/azure-architecture/<service>/SKILL.md` files were present in the repository at design time, so the design relies on the project-level architecture and mapping guidance above.

## 5. Infrastructure as Code Design (Bicep)

### 5.1 Required Bicep files

1. `modules/storage.bicep`
2. `modules/function-app.bicep`
3. `modules/monitoring.bicep`
4. `modules/static-web-app.bicep`
5. `modules/rbac.bicep`
6. `main.bicep`

### 5.2 Root orchestration responsibilities

`main.bicep` must:

- deploy monitoring first
- deploy storage before function runtime configuration
- deploy the Function App with system-assigned managed identity
- deploy RBAC after the Function App principal ID exists
- deploy the Static Web App
- output the values needed by downstream workflows

### 5.3 Root parameter table (`main.bicep`)

| Parameter | Type | Example / default | Required | Notes |
|---|---|---|---|---|
| `environment` | string | `dev` | Yes | Allowed: `dev`, `staging`, `prod` |
| `location` | string | `australiasoutheast` | Yes | Region mapped from AWS `ap-southeast-2` |
| `resourcePrefix` | string | `img-upload` | Yes | Human-readable prefix |
| `storageAccountName` | string | `imguploaddevase` | Yes | Lowercase only, 3-24 chars |
| `storageContainerName` | string | `images` | Yes | Private blob container |
| `functionAppName` | string | `img-upload-func-dev-ase` | Yes | Direct API host |
| `appServicePlanName` | string | `img-upload-plan-dev-ase` | Yes | Consumption Y1 |
| `staticWebAppName` | string | `img-upload-swa-dev-ase` | Yes | SPA host |
| `logAnalyticsWorkspaceName` | string | `img-upload-law-dev-ase` | Yes | Workspace-based monitoring |
| `applicationInsightsName` | string | `img-upload-ai-dev-ase` | Yes | Linked to workspace |
| `keyVaultName` | string | `img-upload-kv-dev-ase` | No | Used when `enableKeyVault = true` |
| `enableKeyVault` | bool | `true` | No | Recommended even for dev |
| `sasExpirationSeconds` | int | `3600` | Yes | Replaces `URL_EXPIRATION` |
| `maxUploadBytes` | int | `10485760` | Yes | 10 MB |
| `corsAllowedOrigins` | array | `['https://<swa-host>', 'http://localhost:3000']` | Yes | Blob + Function App CORS |
| `tags` | object | workload metadata | Yes | Cost and ownership tags |

### 5.4 Module responsibilities and key outputs

| Module | Must create | Key outputs |
|---|---|---|
| `modules/storage.bicep` | Storage account, blob service settings, `images` container, blob CORS, versioning, soft delete | `storageAccountId`, `storageAccountName`, `blobEndpoint`, `imagesContainerName` |
| `modules/function-app.bicep` | Y1 plan, Linux Function App, app settings, system MI, optional Key Vault, auth config | `functionAppId`, `functionAppName`, `functionHostname`, `principalId`, `keyVaultUri` |
| `modules/monitoring.bicep` | Log Analytics workspace, Application Insights | `workspaceId`, `appInsightsConnectionString`, `appInsightsInstrumentationKey` |
| `modules/static-web-app.bicep` | Static Web App resource | `staticWebAppId`, `staticWebAppName`, `defaultHostname` |
| `modules/rbac.bicep` | Role assignments | `storageBlobDataContributorAssignmentId`, `keyVaultSecretsUserAssignmentId` |

### 5.5 Module-level implementation notes

#### `modules/storage.bicep`

- SKU: `Standard_LRS`
- Kind: `StorageV2`
- Access tier: `Hot`
- Public blob access: disabled
- Minimum TLS: `TLS1_2`
- Blob versioning: enabled
- Delete retention: 7 days
- Container: `images` with access type `None`
- CORS methods:
  - `GET`
  - `PUT`
  - `DELETE`
  - `HEAD`
  - `OPTIONS`
- CORS allowed headers: `*`
- CORS exposed headers: `ETag`, `x-ms-request-id`, `x-ms-version`, `Content-Type`

#### `modules/function-app.bicep`

- OS: Linux
- Runtime: Python 3.11
- Plan SKU: `Y1`
- Authentication:
  - enable App Service Authentication
  - identity provider: Microsoft Entra ID
  - unauthenticated requests: reject
- App settings must include:
  - `FUNCTIONS_WORKER_RUNTIME=python`
  - `FUNCTIONS_EXTENSION_VERSION=~4`
  - `WEBSITE_RUN_FROM_PACKAGE=1`
  - `SAS_EXPIRATION_SECONDS=3600`
  - `MAX_UPLOAD_BYTES=10485760`
  - `IMAGES_CONTAINER_NAME=images`
  - `AZURE_STORAGE_ACCOUNT_NAME=<storage account>`
  - `AZURE_STORAGE_BLOB_ENDPOINT=https://<storage>.blob.core.windows.net`
  - `APPLICATIONINSIGHTS_CONNECTION_STRING=<from monitoring module>`
- If `enableKeyVault=true`, store `AzureWebJobsStorage` and optional app secrets in Key Vault and reference them from app settings.

#### `modules/monitoring.bicep`

- Workspace-based Application Insights only
- Daily cap recommended for dev
- Sampling enabled in Functions host config

#### `modules/static-web-app.bicep`

- Tier: Free
- Output default hostname for:
  - Function App CORS
  - Blob CORS
  - frontend runtime API base URL configuration

#### `modules/rbac.bicep`

Create at minimum:

1. **Function App MI → Storage Blob Data Contributor** on the storage account  
   Role definition ID: `ba92f5b4-2d11-453d-a403-e96b0029c9fe`

2. **Function App MI → Key Vault Secrets User** on Key Vault when Key Vault is enabled  
   Role definition ID: `4633458b-17de-408a-b874-0445c86b69e6`

### 5.6 Deployment dependency order

1. `monitoring.bicep`
2. `storage.bicep`
3. `function-app.bicep`
4. `rbac.bicep`
5. `static-web-app.bicep`

## 6. Function Rewrite Specification

### 6.1 Common rewrite rules

- Keep Python **3.11**
- Use Azure Functions v2 programming model decorators
- Use `DefaultAzureCredential`
- Do not use `boto3`
- Do not proxy file bytes through Functions
- Preserve current response semantics where practical

### 6.2 SDK method mapping (`boto3` → `azure-storage-blob`)

| AWS SDK usage | Azure SDK replacement | Exact Azure method / pattern |
|---|---|---|
| `boto3.client('s3')` | `BlobServiceClient` | `BlobServiceClient(account_url, credential=DefaultAzureCredential())` |
| `generate_presigned_post(...)` | user delegation SAS for upload | `get_user_delegation_key(...)` + `generate_blob_sas(..., permission=BlobSasPermissions(create=True, write=True))` |
| `list_objects_v2(...)` | list blobs | `ContainerClient.list_blobs(name_starts_with=prefix).by_page(results_per_page=max_keys)` |
| `head_object(...)` | blob properties | `BlobClient.get_blob_properties()` |
| `get_object_tagging(...)` | blob tags | `BlobClient.get_blob_tags()` |
| `generate_presigned_url('get_object', ...)` | read SAS | `generate_blob_sas(..., permission=BlobSasPermissions(read=True))` |
| `delete_object(...)` | blob delete | `BlobClient.delete_blob(delete_snapshots='include')` |

### 6.3 Route-by-route rewrite plan

#### `upload_handler.py` → `upload_function`

| Item | Target |
|---|---|
| Azure Function name | `upload_function` |
| Route | `POST /api/upload` |
| Trigger | `@app.route(route="upload", methods=["POST"], auth_level=func.AuthLevel.ANONYMOUS)` |
| Upstream auth | Enforced by Function App Authentication (Entra), not by function key |
| Storage action | Generate **upload SAS URL** for blob `images/{fileId}/{fileName}` |

Implementation detail:

- Parse JSON body fields:
  - `fileName` (required)
  - `fileType` (default `image/jpeg`)
  - `description` (optional)
  - `tags` (optional array)
- Generate `fileId = uuid.uuid4()`
- Generate `blobName = f"{fileId}/{fileName}"`
- Generate user delegation SAS with:
  - permissions: `create`, `write`
  - expiry: `SAS_EXPIRATION_SECONDS`
- Return:
  - `uploadUrl`
  - `fileId`
  - `blobName`
  - `expiresIn`
  - `requiredHeaders`
  - `metadata`

Required headers returned to frontend:

- `x-ms-blob-type: BlockBlob`
- `x-ms-blob-content-type: <fileType>`
- `x-ms-meta-uploaddate: <utc iso timestamp>`
- `x-ms-meta-originalfilename: <fileName>`
- `x-ms-meta-description: <description>` when provided
- `x-ms-tags: tag0=<value>&tag1=<value>...` when tags exist

#### `list_handler.py` → `list_function`

| Item | Target |
|---|---|
| Azure Function name | `list_function` |
| Route | `GET /api/files` |
| Trigger | `@app.route(route="files", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)` |
| Query parameters | `prefix`, `maxKeys` |
| Storage action | List blobs, read properties/tags, generate read SAS |

Implementation detail:

- Read `prefix` and `maxKeys`, default `50`
- Use `list_blobs(name_starts_with=prefix)`
- For each blob:
  - call `get_blob_properties()`
  - call `get_blob_tags()`
  - create read SAS
- Preserve response shape:
  - `files`
  - `count`
  - `isTruncated`

Field mapping:

| Output field | Azure source |
|---|---|
| `fileId` | first segment of `blob.name` |
| `s3Key` | renamed semantic equivalent: blob name |
| `fileName` | metadata `originalfilename` or last path segment |
| `fileType` | `properties.content_settings.content_type` |
| `size` | `blob.size` |
| `lastModified` | `blob.last_modified.isoformat()` |
| `uploadDate` | metadata `uploaddate` or `last_modified` |
| `description` | metadata `description` |
| `tags` | values from `get_blob_tags()` |
| `viewUrl` | read SAS URL |

#### `view_handler.py` → `view_function`

| Item | Target |
|---|---|
| Azure Function name | `view_function` |
| Route | `GET /api/files/{fileId}/view-url` |
| Trigger | `@app.route(route="files/{fileId}/view-url", methods=["GET"], auth_level=func.AuthLevel.ANONYMOUS)` |
| Storage action | Find first blob under `{fileId}/`, return read SAS |

Implementation detail:

- Validate `fileId`
- List first blob with prefix `f"{fileId}/"`
- Return 404 if none found
- Read blob properties
- Generate read SAS
- Preserve response fields:
  - `fileId`
  - `blobName`/semantic equivalent of `s3Key`
  - `fileName`
  - `fileType`
  - `description`
  - `uploadDate`
  - `size`
  - `viewUrl`
  - `expiresIn`

#### `delete_handler.py` → `delete_function`

| Item | Target |
|---|---|
| Azure Function name | `delete_function` |
| Route | `DELETE /api/files/{fileId}` |
| Trigger | `@app.route(route="files/{fileId}", methods=["DELETE"], auth_level=func.AuthLevel.ANONYMOUS)` |
| Storage action | List blobs under prefix, delete each blob |

Implementation detail:

- Validate `fileId`
- List blobs with prefix `f"{fileId}/"`
- Return 404 if none found
- Delete each blob with `delete_blob(delete_snapshots='include')`
- Return:
  - `message`
  - `fileId`
  - `deletedKeys`

### 6.4 Frontend contract change

The SPA must change from:

- signed API requests using AWS SigV4
- multipart/form-data POST to S3 presigned POST URL

To:

- bearer-token API calls to Azure Functions
- direct HTTPS `PUT` of file bytes to a Blob SAS URL using returned headers

This is the single biggest application rewrite impact.

## 7. Configuration, Identity, Secrets, and RBAC

### 7.1 Environment variable mapping

| Source variable / concept | Azure replacement | Where used |
|---|---|---|
| `BUCKET_NAME` | `IMAGES_CONTAINER_NAME=images` | Function code |
| `URL_EXPIRATION` | `SAS_EXPIRATION_SECONDS=3600` | Function code |
| S3 bucket endpoint | `AZURE_STORAGE_BLOB_ENDPOINT=https://<storage>.blob.core.windows.net` | Function code |
| AWS region | `AZURE_REGION=australiasoutheast` | Optional app setting / telemetry enrichment |
| Lambda runtime storage | `AzureWebJobsStorage` | Function host runtime |
| CloudWatch/X-Ray config | `APPLICATIONINSIGHTS_CONNECTION_STRING` | Function host/app telemetry |
| IAM credentials | `DefaultAzureCredential` | Function code auth |

### 7.2 Required Function App app settings

| Setting | Value source |
|---|---|
| `FUNCTIONS_WORKER_RUNTIME` | `python` |
| `FUNCTIONS_EXTENSION_VERSION` | `~4` |
| `WEBSITE_RUN_FROM_PACKAGE` | `1` |
| `AzureWebJobsStorage` | Key Vault secret reference or direct deployment setting |
| `IMAGES_CONTAINER_NAME` | Bicep parameter |
| `AZURE_STORAGE_ACCOUNT_NAME` | Storage module output |
| `AZURE_STORAGE_BLOB_ENDPOINT` | Storage module output |
| `SAS_EXPIRATION_SECONDS` | Root parameter |
| `MAX_UPLOAD_BYTES` | Root parameter |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | Monitoring module output |
| `CORS_ALLOWED_ORIGINS` | Comma-separated origins |
| `ENTRA_API_AUDIENCE` | API App Registration audience / client ID URI |

### 7.3 User authentication design

Replace `AWS_IAM` with **Microsoft Entra ID + Function App Authentication**:

1. Create an **App Registration** for the SPA.
2. Create an **App Registration** for the Function App API.
3. Expose API scope, for example: `api://img-upload-func-dev-ase/access_as_user`
4. Configure the SPA to request that scope using **MSAL.js**.
5. Enable Function App Authentication and require authenticated requests.

Result:

- no long-lived credentials in the browser
- no function keys embedded in the SPA
- no storage account keys in application code

### 7.4 RBAC assignments

| Principal | Scope | Role | Why |
|---|---|---|---|
| Function App system-assigned MI | Storage account | Storage Blob Data Contributor | Create SAS inputs, read metadata/tags, delete blobs |
| Function App system-assigned MI | Key Vault | Key Vault Secrets User | Read runtime secrets when Key Vault is enabled |
| GitHub OIDC service principal | Resource group `rg-image-upload` | Contributor | Deploy infrastructure and app resources |
| GitHub OIDC service principal | Resource group `rg-image-upload` | User Access Administrator | Required because Bicep creates RBAC assignments |

### 7.5 Secret handling

- **Preferred:** store `AzureWebJobsStorage` in Key Vault and reference it from app settings.
- **Not permitted:** storage account keys in source code or GitHub repository files.
- **Acceptable for CI/CD:** OIDC short-lived federated login; no Azure client secret.

## 8. Security, Networking, Observability, and Cost Controls

### 8.1 Security controls

- HTTPS only on all public endpoints
- Blob container remains private
- Blob access only via short-lived SAS
- Managed identity used for service-to-service access
- Entra ID used for end-user auth
- No recreation of AWS ApiUser-style long-lived credentials

### 8.2 Networking posture

This dev design intentionally uses **public Azure service endpoints** for the Function App, Static Web App, and Blob service because:

- Functions Consumption is the selected low-cost hosting model
- Static Web Apps are internet-facing by design
- browser direct uploads/downloads require the blob public endpoint, while the container itself stays private

Compensating controls:

- private blob container
- strict CORS
- Entra auth on the API
- short SAS lifetimes
- TLS 1.2 minimum

For production, upgrade path:

- Function App Premium plan
- APIM or Front Door as edge
- private endpoints for storage and vault where feasible

### 8.3 Observability design

| Need | Azure service | Implementation |
|---|---|---|
| Function logs | Application Insights + Log Analytics | Automatic host integration |
| Request tracing | Application Insights | Capture API request duration and failures |
| Dependency tracing | Application Insights | Storage SDK dependencies |
| Alerting | Azure Monitor alerts | 5xx count, exception spikes, latency |
| Log retention | Log Analytics | Dev-appropriate retention, e.g. 30 days |

Recommended alerts:

- HTTP 5xx count > 5 in 5 minutes
- Function execution failures > 3 in 5 minutes
- Average response time > 2 seconds for 15 minutes
- Storage availability failures > 0 in 5 minutes

### 8.4 Cost controls

- Consumption plan only
- Static Web Apps Free
- LRS storage
- App Insights daily cap enabled
- keep SAS expiry at 1 hour, not days
- no APIM in dev

## 9. Deployment and Cutover Plan

### 9.1 Infrastructure deployment order

1. Deploy `main.bicep`
2. Verify outputs:
   - storage account name
   - blob endpoint
   - Function App hostname
   - Static Web App hostname
   - Application Insights connection string
3. Apply RBAC assignments
4. Wait for RBAC propagation
5. Deploy Azure Functions code
6. Deploy Static Web App frontend
7. Run smoke tests

### 9.2 Application migration sequence

1. **Provision infrastructure**
2. **Refactor Functions code**
3. **Refactor frontend auth and upload flow**
4. **Deploy backend**
5. **Deploy frontend**
6. **Validate upload, list, view, delete**
7. **Optionally backfill existing S3 objects to Blob**
8. **Cut over DNS / user entry point**

### 9.3 Data migration note

If the existing S3 image objects must be preserved, copy them to Blob before go-live while maintaining the same logical naming pattern:

- S3 key: `fileId/fileName`
- Blob name: `fileId/fileName`

Preserve:

- content type
- metadata (`uploaddate`, `originalfilename`, `description`)
- tags where feasible

### 9.4 Rollback plan

If validation fails after release:

1. leave AWS stack running until Azure validation is complete
2. revert SPA endpoint configuration to AWS
3. stop promoting Azure as primary entry point
4. fix Function or frontend issues and redeploy

Do not destroy the AWS stack until the Azure path passes the full checklist in Section 10.

## 10. Validation Checklist

### 10.1 Infrastructure validation

- [ ] Resource group `rg-image-upload` exists in `australiasoutheast`
- [ ] Storage account deployed as StorageV2 / LRS / Hot
- [ ] Blob container `images` exists and is private
- [ ] Blob versioning is enabled
- [ ] Function App deployed on Consumption Y1 with Python 3.11
- [ ] System-assigned managed identity enabled on Function App
- [ ] Application Insights linked to Log Analytics
- [ ] Static Web App deployed successfully
- [ ] RBAC assignments created successfully

### 10.2 Security validation

- [ ] Function App rejects unauthenticated requests
- [ ] SPA authenticates via Entra ID
- [ ] No AWS access key / secret key fields remain in the frontend
- [ ] No storage account key is referenced in application code
- [ ] SAS tokens expire after the configured interval
- [ ] Blob container does not allow anonymous listing or reads
- [ ] CORS only allows the SWA hostname and localhost dev origin

### 10.3 Functional validation

- [ ] `POST /api/upload` returns valid upload SAS URL and headers
- [ ] Browser can upload a file directly to Blob with the returned SAS
- [ ] Uploaded blob contains expected metadata and tags
- [ ] `GET /api/files` returns file list with read SAS URLs
- [ ] `GET /api/files/{fileId}/view-url` returns 404 for missing IDs and 200 for valid IDs
- [ ] `DELETE /api/files/{fileId}` removes the blob(s)
- [ ] Upload limit of 10 MB is enforced

### 10.4 Observability validation

- [ ] Requests appear in Application Insights
- [ ] Exceptions are queryable in Log Analytics
- [ ] Dependency calls to Blob Storage are visible
- [ ] Alert rules are deployed or documented

### 10.5 Frontend-specific validation

- [ ] Static Web App artifact contains `index.html` as the default document
- [ ] Current `app.html`-only packaging is corrected before SWA deployment
- [ ] SPA uses bearer tokens instead of SigV4
- [ ] SPA performs Blob upload with HTTP PUT, not S3 form POST

## 11. CI/CD Pipeline Specification

### 11.1 Workflow files

1. `.github/workflows/deploy-infra.yml`
2. `.github/workflows/deploy-functions.yml`
3. `.github/workflows/deploy-static-web.yml`

Optional but recommended later: `validate-pr.yml`

### 11.2 GitHub Actions authentication model

Use **Workload Identity Federation (OIDC)** only.

Required repository secrets:

| Secret | Purpose |
|---|---|
| `AZURE_CLIENT_ID` | App registration used by workflows |
| `AZURE_TENANT_ID` | Azure tenant |
| `AZURE_SUBSCRIPTION_ID` | Azure subscription |

Recommended repository variables:

| Variable | Value |
|---|---|
| `RESOURCE_GROUP_NAME` | `rg-image-upload` |
| `LOCATION` | `australiasoutheast` |
| `ENVIRONMENT` | `dev` |
| `RESOURCE_PREFIX` | `img-upload` |
| `FUNCTION_APP_NAME` | `img-upload-func-dev-ase` |
| `STATIC_WEB_APP_NAME` | `img-upload-swa-dev-ase` |
| `BICEP_TEMPLATE` | `outputs/bicep-templates/main.bicep` |
| `BICEP_PARAMETERS` | `outputs/bicep-templates/parameters/dev.bicepparam` |

All deploy workflows must include:

```yaml
permissions:
  id-token: write
  contents: read
```

Login step:

```yaml
- name: Azure Login (OIDC)
  uses: azure/login@v2
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
```

### 11.3 `deploy-infra.yml`

Purpose: deploy Bicep infrastructure.

Trigger recommendation:

- `push` to `main` when `outputs/bicep-templates/**` or the workflow file changes
- `workflow_dispatch` for manual reruns

Jobs:

1. **validate**
   - checkout
   - Azure login via OIDC
   - `az bicep build --file outputs/bicep-templates/main.bicep`
   - `az deployment group what-if --resource-group rg-image-upload --template-file outputs/bicep-templates/main.bicep --parameters outputs/bicep-templates/parameters/dev.bicepparam`

2. **deploy**
   - depends on validate
   - `az deployment group create ...`
   - capture outputs for downstream jobs/workflows

Critical deployment outputs to publish:

- function app name
- function hostname
- storage account name
- blob endpoint
- static web app name
- static web app default hostname

### 11.4 `deploy-functions.yml`

Purpose: build and deploy the Azure Functions application from `outputs/azure-functions/`.

Trigger recommendation:

- `push` to `main` when `outputs/azure-functions/**` or the workflow file changes
- `workflow_dispatch`

Required steps:

1. checkout
2. setup Python 3.11
3. install dependencies from `outputs/azure-functions/requirements.txt`
4. optional packaging validation
5. Azure login via OIDC
6. deploy with `Azure/functions-action@v1`
7. post-deploy smoke tests against:
   - `POST /api/upload`
   - `GET /api/files`

Deployment target:

- Function App name from repo variable `FUNCTION_APP_NAME`

### 11.5 `deploy-static-web.yml`

Purpose: deploy the frontend SPA.

Trigger recommendation:

- `push` to `main` when frontend artifact or workflow changes
- `workflow_dispatch`

Required preconditions:

- frontend output must contain `index.html`
- API base URL must point to the Function App hostname
- MSAL / Entra configuration must be injected into the frontend

Deployment approach:

1. checkout
2. Azure login via OIDC
3. fetch the current SWA deployment token at runtime using Azure CLI
4. deploy with `Azure/static-web-apps-deploy@v1`

Runtime token retrieval avoids storing a long-lived SWA deployment token in GitHub.

### 11.6 OIDC RBAC requirements for the deployment identity

The federated deployment principal needs:

- **Contributor** on `rg-image-upload`
- **User Access Administrator** on `rg-image-upload`

`User Access Administrator` is required because the Bicep deployment creates role assignments for the Function App managed identity.

### 11.7 CI/CD quality gates

Minimum gates before merge or release:

- Bicep build succeeds
- Bicep what-if succeeds
- Functions package installs successfully on Python 3.11
- Frontend artifact contains `index.html`
- Smoke tests pass after deployment

### 11.8 Downstream agent handoff requirements

This design document is the contract for downstream agents:

- **iac-transformation** consumes Section 5 and Section 9
- **code-refactor** consumes Section 6 and Section 7
- **pipeline-builder-agent** consumes Section 11
- **deployment-validation** consumes Section 10

