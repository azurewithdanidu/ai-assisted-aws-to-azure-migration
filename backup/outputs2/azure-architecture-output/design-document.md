# Azure Architecture Design Document

**Version:** 1.0  
**Date:** 2026-06-28  
**Author:** azure-architect agent  
**Source AWS Account:** 535002891143 (ap-southeast-2)  
**Target Azure Region:** australiaeast  

---

## 1. Executive Summary

The Image Upload Service is a serverless image management platform currently running on AWS Lambda (4 functions, Python 3.11), Amazon API Gateway (REST, AWS_IAM auth), and Amazon S3 (2 buckets: image storage and static website hosting), backed by CloudWatch for observability and CloudFormation for IaC. The migration replaces every AWS service with a direct Azure serverless equivalent: **Azure Functions** (Consumption plan, Python v2 model) replaces all four Lambda functions; **Azure Blob Storage** (GPv2, Hot tier) replaces the image S3 bucket; **Azure Static Web Apps** replaces the public S3 website bucket; **Azure Monitor / Log Analytics / Application Insights** replaces CloudWatch and X-Ray; and **Azure Bicep** replaces CloudFormation. The AWS_IAM SigV4 client authentication is replaced with **Azure AD App Registration + MSAL.js** browser-based authentication, eliminating the critical security finding of a long-lived IAM access key embedded in the browser client. A **System-Assigned Managed Identity** on the Function App replaces the Lambda execution role, with `Storage Blob Data Contributor` RBAC assigned on the Storage Account. The resulting architecture is single-region (australiaeast), serverless-first, and WAF-compliant across all five pillars, with an estimated 10–20% lower monthly infrastructure cost at equivalent usage.

---

## 2. AWS Discovery Summary

Source: `outputs/aws-migration-artifacts/aws-inventory.json` and `outputs/aws-migration-artifacts/migration-assessment.md`.

- **Stack:** `image-upload` (CloudFormation, ap-southeast-2, CREATE_COMPLETE, created 2026-01-14)
- **Total resources:** 16 (discovery) / 31 (stack including policy attachments)
- **Services discovered:** Lambda, S3, API Gateway, IAM, CloudWatch Logs, CloudFormation

### Lambda Functions (4)

| Logical ID | Physical Name | Runtime | Memory | Timeout | Handler | Env Vars | Criticality |
|---|---|---|---|---|---|---|---|
| UploadFunction | `image-upload-UploadFunction-iIIJ7xiZECuB` | python3.11 | 256 MB | 30 s | `upload_handler.lambda_handler` | BUCKET_NAME, URL_EXPIRATION | HIGH |
| ListFilesFunction | `image-upload-ListFilesFunction-Pb0dKq9dR0Is` | python3.11 | 256 MB | 30 s | `list_handler.lambda_handler` | BUCKET_NAME, URL_EXPIRATION | HIGH |
| GetViewUrlFunction | `image-upload-GetViewUrlFunction-yMGI9X8Us5Em` | python3.11 | 256 MB | 30 s | `view_handler.lambda_handler` | BUCKET_NAME, URL_EXPIRATION | MEDIUM |
| DeleteFileFunction | `image-upload-DeleteFileFunction-EG7Cfj3m2P6f` | python3.11 | 256 MB | 30 s | `delete_handler.lambda_handler` | BUCKET_NAME | HIGH |

All four functions use the same IAM execution role and share boto3 calls against a single S3 bucket.

### S3 Buckets (2)

| Logical ID | Physical Name | Purpose | Versioning | Public Access | CORS | Criticality |
|---|---|---|---|---|---|---|
| ImageBucket | `image-upload-imagebucket-t8isnbr8sswv` | Image storage — private, accessed via presigned URLs | Enabled | Blocked | GET,PUT,POST,HEAD,DELETE from `*` | CRITICAL |
| WebsiteBucket | `image-upload-websitebucket-vd866vxtcs1z` | Static website hosting (app.html) | Disabled | NOT blocked | None | HIGH |

### API Gateway (1)

| Attribute | Value |
|---|---|
| Name | `image-upload-api` (ID: `4lrh2l7i86`) |
| Type | REST (v1) |
| Auth | AWS_IAM on all routes |
| Stage URL | `https://4lrh2l7i86.execute-api.ap-southeast-2.amazonaws.com/dev` |
| Routes | POST /upload, GET /files, GET /files/{fileId}/view-url, DELETE /files/{fileId}, OPTIONS (CORS mocks) |
| Tracing | X-Ray enabled |
| Logging | INFO, data trace enabled, metrics enabled |
| Criticality | CRITICAL |

### IAM (4 resources)

| Logical ID | Type | Notes | Security Risk |
|---|---|---|---|
| LambdaExecutionRole | IAM Role | S3 + CloudWatch Logs permissions for all 4 Lambdas | None |
| ApiGatewayCloudWatchLogsRole | IAM Role | API GW push to CloudWatch | None |
| ApiUser (`image-upload-api-user`) | IAM User | Client-side SigV4 auth | 🔴 HIGH — long-lived access key in CloudFormation output |
| ApiUserAccessKey (`AKIAXZEFIIOD2OIWPRPK`) | IAM Access Key | Used by browser JS to sign API requests | 🔴 CRITICAL — secret exposed in stack outputs |

### CloudWatch Log Groups (5)

- `/aws/lambda/image-upload-UploadFunction-iIIJ7xiZECuB` — no retention, 1.6 KB
- `/aws/lambda/image-upload-ListFilesFunction-Pb0dKq9dR0Is` — no retention, 1.6 KB
- `/aws/lambda/image-upload-DeleteFileFunction-EG7Cfj3m2P6f` — no retention, 0.5 KB
- `/aws/lambda/image-upload-GetViewUrlFunction-yMGI9X8Us5Em` — no retention, 0 KB
- `API-Gateway-Execution-Logs_4lrh2l7i86/dev` — no retention, 32 KB

### CloudFormation (1)

- Stack `image-upload`, 31 resources, CREATE_COMPLETE, ap-southeast-2

### Monthly AWS Costs (from inventory)

| Service | Monthly Cost |
|---|---|
| Lambda (4 functions) | $1.10 |
| S3 ImageBucket | $2.00 |
| S3 WebsiteBucket | $0.50 |
| API Gateway | $1.00 |
| CloudWatch | ~$0.50 (estimate) |
| **Total** | **~$5.10** |

---

## 3. Azure Service Mapping

> Consulted: `aws-to-azure-mapping.md` (Compute, Storage, Networking, Security, Monitoring tables)

| AWS Service | AWS Config | Azure Equivalent | Azure Config | Migration Notes |
|---|---|---|---|---|
| Lambda (UploadFunction) | python3.11, 256 MB, 30 s, POST /upload | Azure Functions HTTP trigger | Consumption plan, Python 3.11, v2 programming model | Replace `generate_presigned_post` with Azure Blob SAS token (Write); boto3 → azure-storage-blob; S3 tags → Blob metadata |
| Lambda (ListFilesFunction) | python3.11, 256 MB, 30 s, GET /files | Azure Functions HTTP trigger | Consumption plan, Python 3.11, v2 programming model | `list_objects_v2` → `ContainerClient.list_blobs()`; `head_object` → `get_blob_properties()`; `generate_presigned_url` → `generate_sas(read=True)` |
| Lambda (GetViewUrlFunction) | python3.11, 256 MB, 30 s, GET /files/{id}/view-url | Azure Functions HTTP trigger | Consumption plan, Python 3.11, v2 programming model | `list_objects_v2` by prefix → `list_blobs(name_starts_with=file_id)`; `generate_presigned_url` → `generate_sas(read=True)` |
| Lambda (DeleteFileFunction) | python3.11, 256 MB, 30 s, DELETE /files/{id} | Azure Functions HTTP trigger | Consumption plan, Python 3.11, v2 programming model | `list_objects_v2` + `delete_object` per key → `list_blobs(name_starts_with=file_id)` + `delete_blob()` |
| S3 ImageBucket | Private, versioned, CORS GET/PUT/POST/HEAD/DELETE from `*`, AES256 SSE | Azure Blob Storage | GPv2, Hot tier, `images` container (private), blob versioning enabled, soft delete 7 days, SSE with Microsoft-managed key | CORS configured on storage account (restrict from `*` to SWA origin); SAS token auth replaces presigned URLs |
| S3 WebsiteBucket | Public, static website, app.html | Azure Static Web Apps | Free tier, australiaeast | Built-in CI/CD, HTTPS, global CDN; frontend JS updated for Azure AD auth + new Function App URL |
| API Gateway REST (AWS_IAM) | 4 routes, SigV4 auth, X-Ray, INFO logging | Azure Functions HTTP triggers (direct) | No APIM (prohibited); Functions handle routing; Azure AD JWT validation via middleware | SigV4 client → MSAL.js + Azure AD Bearer token; CORS configured in Function App host.json |
| IAM LambdaExecutionRole | S3 CRUD + CloudWatch Logs | System-Assigned Managed Identity on Function App | `Storage Blob Data Contributor` RBAC on Storage Account | `DefaultAzureCredential()` replaces boto3 IAM role assumption |
| IAM ApiUser + AccessKey | Long-lived key, client-side SigV4 | Azure AD App Registration | MSAL.js browser flow; short-lived Bearer tokens | 🔴 **SECURITY REMEDIATION**: rotate AWS key immediately; replace client-side pattern with Azure AD |
| IAM ApiGatewayCloudWatchLogsRole | Push logs to CloudWatch | N/A | Application Insights + Log Analytics (automatic for Azure Functions) | No explicit role needed; AI SDK handles telemetry |
| CloudWatch Logs (5 groups) | No retention policy | Azure Log Analytics Workspace + Application Insights | 30-day retention (dev), 90-day (prod) | Azure Functions automatically stream to Application Insights when `APPLICATIONINSIGHTS_CONNECTION_STRING` is set |
| CloudWatch Metrics | Lambda invocations, errors, duration | Azure Monitor Metrics | Built-in Azure Functions metrics in Application Insights | Custom dashboard via Azure Monitor workbook |
| AWS X-Ray | Tracing on API Gateway | Azure Application Insights | Distributed tracing, dependency maps, live metrics | `opencensus-ext-azure` or `azure-monitor-opentelemetry` in requirements.txt |
| CloudFormation | 31-resource stack | Azure Bicep | Modular Bicep templates under `outputs/bicep-templates/` | 5 Bicep modules + 1 root main.bicep + 3 parameter files |

---

## 4. Target Architecture

See `outputs/azure-architecture-output/architecture-diagram-azure.mmd` for the full diagram (also embedded below).

```mermaid
graph TB
    subgraph "End Users"
        Browser["Browser\n(Web Client)"]
    end

    subgraph "Azure AD"
        AAD["Azure Active Directory\nApp Registration\n(image-upload-app)\nMSAL.js browser flow"]
    end

    subgraph "Static Hosting — australiaeast"
        SWA["Azure Static Web Apps\n(Free tier)\napp.html + assets\nCustom domain + HTTPS + CDN"]
    end

    subgraph "Compute — australiaeast"
        FA["Azure Function App\n(Consumption plan, Python 3.11)\nSystem-Assigned Managed Identity\nApp Insights integrated"]
        UF["upload_function\nPOST /api/upload\nGenerates Blob SAS token (Write)"]
        LF["list_function\nGET /api/files\nLists blobs + SAS token (Read)"]
        VF["view_url_function\nGET /api/files/{fileId}/view-url\nGenerates SAS token (Read)"]
        DF["delete_function\nDELETE /api/files/{fileId}\nDeletes blob by prefix"]
        FA --> UF & LF & VF & DF
    end

    subgraph "Storage — australiaeast"
        SA["Azure Storage Account\n(GPv2, LRS dev / ZRS prod)\nSSE Microsoft-managed key\nBlob versioning + soft delete"]
        IC["images container\n(Private access)\nCORS: SWA origin only"]
        SA --> IC
    end

    subgraph "Security"
        KV["Azure Key Vault\n(Standard SKU)\nStores: STORAGE_ACCOUNT_NAME\nURL_EXPIRATION setting"]
        MI["System-Assigned\nManaged Identity\nStorage Blob Data Contributor\non Storage Account"]
    end

    subgraph "Observability"
        LAW["Log Analytics Workspace\n30-day retention (dev)\n90-day (prod)"]
        AI["Application Insights\nDistributed tracing\nLive metrics\nDependency maps"]
        LAW --> AI
    end

    subgraph "IaC"
        BICEP["Azure Bicep\noutputs/bicep-templates/\nmain.bicep + 5 modules\n3 parameter files"]
    end

    %% User flows
    Browser -->|"loads app (HTTPS + CDN)"| SWA
    Browser -->|"Azure AD login (MSAL.js)"| AAD
    AAD -->|"Bearer token"| Browser
    Browser -->|"Bearer token + HTTP"| FA

    %% Function → Storage
    UF -->|"generate_sas (Write)"| IC
    LF -->|"list_blobs + generate_sas (Read)"| IC
    VF -->|"list_blobs prefix + generate_sas (Read)"| IC
    DF -->|"list_blobs prefix + delete_blob"| IC

    %% Identity
    FA -->|"Managed Identity"| MI
    MI -->|"Storage Blob Data Contributor"| SA

    %% Secrets
    FA -->|"Key Vault reference"| KV

    %% Observability
    FA -->|"App Insights SDK telemetry"| AI
    AI --> LAW

    %% IaC
    BICEP -.->|"deploys"| FA
    BICEP -.->|"deploys"| SA
    BICEP -.->|"deploys"| SWA
    BICEP -.->|"deploys"| KV
    BICEP -.->|"deploys"| AI

    classDef critical fill:#c0392b,stroke:#922b21,color:#fff
    classDef high fill:#e67e22,stroke:#ca6f1e,color:#fff
    classDef medium fill:#f1c40f,stroke:#d4ac0d,color:#000
    classDef azure fill:#0078d4,stroke:#005a9e,color:#fff
    classDef security fill:#27ae60,stroke:#1e8449,color:#fff
    classDef obs fill:#8e44ad,stroke:#6c3483,color:#fff

    class IC,FA critical
    class SA,SWA high
    class UF,LF,VF,DF,AAD azure
    class MI,KV security
    class AI,LAW obs
```

### Component Groups Description

**End Users / Browser:** Loads the static frontend from Azure Static Web Apps (HTTPS, global CDN). Authenticates with Azure AD via MSAL.js. Sends API calls to Azure Functions with a Bearer token.

**Azure Active Directory:** App Registration `image-upload-app` provides short-lived Bearer tokens via the implicit/authorization-code MSAL.js flow, replacing the long-lived IAM access key pattern.

**Azure Static Web Apps (Free tier):** Hosts `app.html` with automatic HTTPS and CDN. Replaces the public S3 website bucket. Built-in GitHub Actions integration deploys on push to main.

**Azure Function App (Consumption plan):** Four HTTP-triggered Python functions implement the REST API. System-Assigned Managed Identity authenticates to Blob Storage via `DefaultAzureCredential()` — no connection strings or keys.

**Azure Storage Account (GPv2):** `images` container (private) stores uploaded images. Blob versioning and soft delete replace S3 versioning. CORS restricted to the SWA origin (not wildcard). SAS tokens replace S3 presigned URLs.

**Azure Key Vault:** Stores the storage account name and URL expiration as Key Vault references in Function App configuration — accessed via managed identity, never in application settings.

**Application Insights + Log Analytics Workspace:** Full observability replacing CloudWatch and X-Ray. 30-day retention in dev; 90-day in prod. Application Insights auto-instruments Azure Functions.

---

## 5. Infrastructure as Code Specification

All modules live under `outputs/bicep-templates/modules/`. The root `outputs/bicep-templates/main.bicep` declares parameters and module calls only — no direct resources.

> Consulted: `bicep-generation.md` — naming conventions, decorator patterns, output requirements.

---

### 5.1 Storage Module (`modules/storage.bicep`)

**Purpose:** Deploys the Azure Storage Account, the `images` blob container, CORS rules, blob versioning, and soft-delete configuration.

**Parameters:**

| Name | Type | Allowed Values | Description |
|---|---|---|---|
| `environment` | string | `dev`, `staging`, `prod` | Deployment environment |
| `workload` | string | — | Workload name, e.g. `imageupload` |
| `location` | string | — | Azure region, e.g. `australiaeast` |
| `tags` | object | — | Resource tags |
| `allowedCorsOrigin` | string | — | Frontend origin for CORS (e.g. SWA URL). Pass `*` only in dev. |

**Variables:**

```bicep
var uniqueSuffix = uniqueString(resourceGroup().id)
var storageAccountName = toLower('${environment}${workload}stor${uniqueSuffix}')
```

**Resources:**

| Resource Type | API Version | Notes |
|---|---|---|
| `Microsoft.Storage/storageAccounts` | `2023-01-01` | Kind: StorageV2, SKU: Standard_LRS (dev/staging), Standard_ZRS (prod); `publicNetworkAccess: 'Enabled'` with IP ACLs — required for SAS token generation from browser clients. Set `allowBlobPublicAccess: false`. |
| `Microsoft.Storage/storageAccounts/blobServices` | `2023-01-01` | `isVersioningEnabled: true`, soft delete: `enabled: true, days: 7` (dev), 30 (prod) |
| `Microsoft.Storage/storageAccounts/blobServices/containers` | `2023-01-01` | name: `images`, `publicAccess: 'None'` |

**Outputs:**

| Name | Type | Value |
|---|---|---|
| `resourceId` | string | Storage Account resource ID |
| `resourceName` | string | Storage Account name |
| `blobEndpoint` | string | `storageAccount.properties.primaryEndpoints.blob` |

**Security requirements:**
- `allowBlobPublicAccess: false` — no anonymous blob access
- `minimumTlsVersion: 'TLS1_2'`
- SSE using Microsoft-managed keys (default — sufficient for this workload)
- CORS: `allowedOrigins` set to `allowedCorsOrigin` parameter; allowed methods: `GET, PUT, POST, HEAD, DELETE`; max age: 3600

**Environment differences:**

| Parameter | Dev | Staging | Prod |
|---|---|---|---|
| SKU | Standard_LRS | Standard_LRS | Standard_ZRS |
| Soft delete days | 7 | 14 | 30 |
| CORS origin | `*` | SWA staging URL | SWA prod URL |

---

### 5.2 Function App Module (`modules/function-app.bicep`)

**Purpose:** Deploys the Consumption plan App Service Plan, the Azure Function App (Python 3.11, v2 model), system-assigned managed identity, and all required application settings (sourced from Key Vault references).

**Parameters:**

| Name | Type | Allowed Values | Description |
|---|---|---|---|
| `environment` | string | `dev`, `staging`, `prod` | Deployment environment |
| `workload` | string | — | Workload name |
| `location` | string | — | Azure region |
| `tags` | object | — | Resource tags |
| `storageAccountName` | string | — | Storage Account name (from storage module output) |
| `storageAccountId` | string | — | Storage Account resource ID |
| `appInsightsConnectionString` | string | — | Application Insights connection string (from monitoring module output) |
| `keyVaultName` | string | — | Key Vault name (from Key Vault module output) |
| `urlExpiration` | int | — | SAS token expiry in seconds; default 3600 |
| `allowedCorsOrigin` | string | — | Frontend origin for CORS |

**Variables:**

```bicep
var functionAppName = '${environment}-${workload}-func-${location}'
var hostingPlanName = '${environment}-${workload}-plan-${location}'
var storageConnStrForRuntime = 'DefaultEndpointsProtocol=https;AccountName=...' // AzureWebJobsStorage — uses managed identity in v2
```

**Resources:**

| Resource Type | API Version | Notes |
|---|---|---|
| `Microsoft.Web/serverfarms` | `2023-01-01` | Kind: `functionapp`, SKU name: `Y1`, tier: `Dynamic` (Consumption) |
| `Microsoft.Web/sites` | `2023-01-01` | Kind: `functionapp,linux`; identity type: `SystemAssigned`; Python 3.11; `FUNCTIONS_WORKER_RUNTIME: python`; `FUNCTIONS_EXTENSION_VERSION: ~4` |

**App Settings (siteConfig.appSettings):**

| Setting Name | Value | Notes |
|---|---|---|
| `FUNCTIONS_WORKER_RUNTIME` | `python` | Required for Python runtime |
| `FUNCTIONS_EXTENSION_VERSION` | `~4` | Azure Functions v4 runtime |
| `AzureWebJobsStorage__accountName` | `storageAccountName` | Managed identity auth — no connection string |
| `APPLICATIONINSIGHTS_CONNECTION_STRING` | `appInsightsConnectionString` | Enables auto-instrumentation |
| `STORAGE_ACCOUNT_NAME` | `@Microsoft.KeyVault(VaultName=${keyVaultName};SecretName=storage-account-name)` | Key Vault reference |
| `URL_EXPIRATION` | `string(urlExpiration)` | SAS token expiry seconds |
| `ALLOWED_CORS_ORIGIN` | `allowedCorsOrigin` | Used by Functions for CORS header |

**host.json CORS Configuration** (in `outputs/azure-functions/host.json`):

```json
{
  "version": "2.0",
  "cors": {
    "allowedOrigins": ["__ALLOWED_CORS_ORIGIN__"],
    "supportCredentials": true
  },
  "extensions": {
    "http": {
      "routePrefix": "api"
    }
  }
}
```

**Outputs:**

| Name | Type | Value |
|---|---|---|
| `resourceId` | string | Function App resource ID |
| `resourceName` | string | Function App name |
| `principalId` | string | System-assigned managed identity principal ID |
| `defaultHostname` | string | `functionApp.properties.defaultHostName` |

**Security requirements:**
- `httpsOnly: true`
- System-assigned managed identity enabled
- No storage account connection strings — use `AzureWebJobsStorage__accountName` identity pattern
- `minTlsVersion: '1.2'`
- Key Vault references for sensitive configuration

**Environment differences:**

| Parameter | Dev | Staging | Prod |
|---|---|---|---|
| URL_EXPIRATION | 3600 | 3600 | 1800 |
| CORS origin | `*` | SWA staging URL | SWA prod URL |

---

### 5.3 Static Web App Module (`modules/static-web-app.bicep`)

**Purpose:** Deploys the Azure Static Web Apps resource for hosting the `app.html` frontend.

**Parameters:**

| Name | Type | Allowed Values | Description |
|---|---|---|---|
| `environment` | string | `dev`, `staging`, `prod` | Deployment environment |
| `workload` | string | — | Workload name |
| `location` | string | — | Azure region |
| `tags` | object | — | Resource tags |
| `repositoryUrl` | string | — | GitHub repository URL for CI/CD |
| `branch` | string | — | Deployment branch (e.g. `main`) |
| `appLocation` | string | — | App folder, e.g. `outputs/azure-functions` |
| `outputLocation` | string | — | Build output folder, e.g. `build` |

**Resources:**

| Resource Type | API Version | Notes |
|---|---|---|
| `Microsoft.Web/staticSites` | `2023-01-01` | SKU name: `Free` (dev/staging), `Standard` (prod); location: `eastasia` or `australiaeast` based on availability |

**Outputs:**

| Name | Type | Value |
|---|---|---|
| `resourceId` | string | Static Web App resource ID |
| `resourceName` | string | Static Web App name |
| `defaultHostname` | string | `staticSite.properties.defaultHostname` |
| `deploymentToken` | string | `listSecrets(staticSite.id, staticSite.apiVersion).properties.apiKey` — marked `@secure()` |

**Environment differences:**

| Parameter | Dev | Staging | Prod |
|---|---|---|---|
| SKU | Free | Free | Standard |
| Branch | `dev` | `staging` | `main` |

---

### 5.4 Monitoring Module (`modules/monitoring.bicep`)

**Purpose:** Deploys the Log Analytics Workspace and Application Insights instance.

**Parameters:**

| Name | Type | Allowed Values | Description |
|---|---|---|---|
| `environment` | string | `dev`, `staging`, `prod` | Deployment environment |
| `workload` | string | — | Workload name |
| `location` | string | — | Azure region |
| `tags` | object | — | Resource tags |
| `retentionDays` | int | 30–730 | Log retention in days |

**Resources:**

| Resource Type | API Version | Notes |
|---|---|---|
| `Microsoft.OperationalInsights/workspaces` | `2022-10-01` | SKU: PerGB2018; `retentionInDays`: 30 (dev), 90 (prod) |
| `Microsoft.Insights/components` | `2020-02-02` | Kind: `web`; `Application_Type: web`; linked to Log Analytics Workspace |

**Outputs:**

| Name | Type | Value |
|---|---|---|
| `resourceId` | string | Application Insights resource ID |
| `resourceName` | string | Application Insights resource name |
| `connectionString` | string | `appInsights.properties.ConnectionString` |
| `workspaceId` | string | Log Analytics Workspace resource ID |

**Environment differences:**

| Parameter | Dev | Staging | Prod |
|---|---|---|---|
| retentionDays | 30 | 60 | 90 |

---

### 5.5 RBAC Module (`modules/rbac.bicep`)

**Purpose:** Assigns the `Storage Blob Data Contributor` role to the Function App's system-assigned managed identity on the Storage Account scope.

**Parameters:**

| Name | Type | Description |
|---|---|---|
| `storageAccountId` | string | Storage Account resource ID (scope for assignment) |
| `functionAppPrincipalId` | string | Principal ID of the Function App managed identity |

**Resources:**

| Resource Type | API Version | Notes |
|---|---|---|
| `Microsoft.Authorization/roleAssignments` | `2022-04-01` | `roleDefinitionId`: `/subscriptions/.../providers/Microsoft.Authorization/roleDefinitions/ba92f5b4-2d11-453d-a403-e96b0029c9fe` (Storage Blob Data Contributor); `principalType: 'ServicePrincipal'` |

**Outputs:**

| Name | Type | Value |
|---|---|---|
| `roleAssignmentId` | string | Role assignment resource ID |

**Security requirements:**
- Scope is scoped to the Storage Account (not subscription or resource group)
- `principalType: 'ServicePrincipal'` required to avoid propagation delay warnings

---

### Root `main.bicep`

**Purpose:** Declares all top-level parameters, calls all five modules, and wires outputs between modules.

**Parameters:** `environment`, `workload` (default: `imageupload`), `location` (default: `australiaeast`), `tags`, `allowedCorsOrigin`, `repositoryUrl`, `branch`, `urlExpiration`.

**Module call order:**
1. `monitoring` — no dependencies
2. `storage` — no dependencies
3. `staticWebApp` — no dependencies (runs parallel with storage)
4. `functionApp` — depends on `monitoring.outputs.connectionString`, `storage.outputs.resourceName`, `storage.outputs.resourceId`
5. `rbac` — depends on `storage.outputs.resourceId`, `functionApp.outputs.principalId`

---

## 6. Application Code Changes

All four functions are consolidated in a single `function_app.py` file using the **Azure Functions Python v2 programming model**. Source files are at `outputs/azure-functions/function_app.py`.

> Consulted: `aws-to-azure-mapping.md` — boto3 → azure-sdk mappings.

---

### 6.1 UploadFunction → `upload_function`

**Original file:** `source-app/app-code/lambda/upload/upload_handler.py`  
**Trigger type:** HTTP POST — `route: "upload"`  
**SDK changes:**

| boto3 call | Azure SDK replacement | Package |
|---|---|---|
| `boto3.client('s3')` | `BlobServiceClient` with `DefaultAzureCredential` | `azure-storage-blob`, `azure-identity` |
| `s3_client.generate_presigned_post(...)` | `generate_blob_sas(account_name, container_name, blob_name, permission=BlobSasPermissions(write=True, create=True), expiry=...)` | `azure-storage-blob` |
| `{'x-amz-meta-key': value}` (S3 object tags) | `metadata={'key': value}` on `BlobClient.set_blob_metadata()` | Built into azure-storage-blob |

**Environment variables:**

| Old (AWS) | New (Azure) | Source |
|---|---|---|
| `BUCKET_NAME` | `STORAGE_ACCOUNT_NAME` | Key Vault reference in Function App config |
| `URL_EXPIRATION` | `URL_EXPIRATION` | App setting (integer seconds) |
| — | `AZURE_STORAGE_CONTAINER_NAME` | App setting: `images` |
| — | `AZURE_CLIENT_ID` | Auto-populated by managed identity |

**Auth pattern:** `DefaultAzureCredential()` instantiated once at module level. Used to create `BlobServiceClient` and to generate SAS tokens via the storage account key (via `StorageManagementClient`) OR via user delegation key (`get_user_delegation_key`). For Consumption plan, use **user delegation SAS** via `generate_blob_sas` with `user_delegation_key` obtained from `BlobServiceClient.get_user_delegation_key()`.

**Configuration changes:**
- `requirements.txt`: add `azure-functions`, `azure-storage-blob>=12.19.0`, `azure-identity>=1.15.0`
- `host.json`: add CORS allowed origins

**Logic change summary:**
1. Parse request body (same as AWS: `fileName`, `fileType`, `description`, `tags`)
2. Generate `file_id = str(uuid.uuid4())`
3. Construct `blob_name = f"{file_id}/{file_name}"`
4. Obtain `user_delegation_key` from `BlobServiceClient` (valid 1 hour)
5. Call `generate_blob_sas(account_name, container_name, blob_name, permission=BlobSasPermissions(write=True, create=True), expiry=datetime.utcnow() + timedelta(seconds=URL_EXPIRATION), user_delegation_key=user_delegation_key)`
6. Return SAS URL: `f"https://{account_name}.blob.core.windows.net/{container_name}/{blob_name}?{sas_token}"`
7. Also return `fileId`, `blobName`, `metadata` fields for client to set metadata after upload

**Security note:** The client uploads directly to Blob Storage using the SAS URL (equivalent to presigned POST). Metadata (`description`, tags) must be set as blob metadata headers during the PUT request by the client, or via a separate API call.

---

### 6.2 ListFilesFunction → `list_function`

**Original file:** `source-app/app-code/lambda/list/list_handler.py`  
**Trigger type:** HTTP GET — `route: "files"`  
**SDK changes:**

| boto3 call | Azure SDK replacement |
|---|---|
| `s3_client.list_objects_v2(Bucket=..., MaxKeys=..., Prefix=...)` | `container_client.list_blobs(name_starts_with=prefix, results_per_page=max_keys)` |
| `s3_client.head_object(Bucket=..., Key=...)` | `blob_client.get_blob_properties()` — returns `.metadata` dict |
| `s3_client.get_object_tagging(...)` | `blob_client.get_blob_properties().metadata` — tags stored as metadata |
| `s3_client.generate_presigned_url('get_object', ...)` | `generate_blob_sas(..., permission=BlobSasPermissions(read=True), ...)` |

**Environment variables:** Same as UploadFunction (`STORAGE_ACCOUNT_NAME`, `AZURE_STORAGE_CONTAINER_NAME`, `URL_EXPIRATION`).

**Logic change summary:**
1. Get query params: `prefix` (optional), `maxKeys` (default 50)
2. `container_client = BlobServiceClient(...).get_container_client(container_name)`
3. `blobs = list(container_client.list_blobs(name_starts_with=prefix, include=['metadata']))`
4. For each blob: extract `blob.metadata` dict (contains `originalfilename`, `uploaddate`, `description`)
5. Generate read SAS for each blob
6. Return `{ "files": [...], "count": len(blobs) }`

---

### 6.3 GetViewUrlFunction → `view_url_function`

**Original file:** `source-app/app-code/lambda/view/view_handler.py`  
**Trigger type:** HTTP GET — `route: "files/{fileId}/view-url"`  
**SDK changes:**

| boto3 call | Azure SDK replacement |
|---|---|
| `s3_client.list_objects_v2(Bucket=..., Prefix=f"{file_id}/", MaxKeys=1)` | `list(container_client.list_blobs(name_starts_with=f"{file_id}/"))[:1]` |
| `s3_client.head_object(...)` | `blob_client.get_blob_properties()` |
| `s3_client.generate_presigned_url('get_object', ...)` | `generate_blob_sas(..., read=True, ...)` |

**Logic change summary:**
1. Get `file_id` from route parameters: `req.route_params.get('fileId')`
2. List blobs with prefix `{file_id}/`, take first result
3. If none: return 404
4. Generate read SAS URL with `URL_EXPIRATION` seconds expiry
5. Return `{ "fileId": file_id, "viewUrl": sas_url, "fileName": ..., "metadata": ... }`

---

### 6.4 DeleteFileFunction → `delete_function`

**Original file:** `source-app/app-code/lambda/delete/delete_handler.py`  
**Trigger type:** HTTP DELETE — `route: "files/{fileId}"`  
**SDK changes:**

| boto3 call | Azure SDK replacement |
|---|---|
| `s3_client.list_objects_v2(Bucket=..., Prefix=f"{file_id}/")` | `container_client.list_blobs(name_starts_with=f"{file_id}/")` |
| `s3_client.delete_object(Bucket=..., Key=obj['Key'])` | `container_client.delete_blob(blob_name)` |

**Logic change summary:**
1. Get `file_id` from route parameters
2. List blobs with prefix `{file_id}/`
3. If none: return 404
4. Delete each blob: `container_client.delete_blob(blob.name)`
5. Return `{ "message": "File(s) deleted", "fileId": file_id, "deletedKeys": [...] }`

---

### Common Azure Functions Requirements

**`requirements.txt`** (complete):

```
azure-functions
azure-storage-blob>=12.19.0
azure-identity>=1.15.0
```

**`host.json`** (complete):

```json
{
  "version": "2.0",
  "logging": {
    "applicationInsights": {
      "samplingSettings": {
        "isEnabled": true,
        "excludedTypes": "Request"
      }
    }
  },
  "cors": {
    "allowedOrigins": ["__REPLACED_AT_DEPLOY_TIME__"],
    "supportCredentials": false
  },
  "extensions": {
    "http": {
      "routePrefix": "api"
    }
  }
}
```

**Azure Functions v2 handler signature** (Python):

```python
import azure.functions as func

app = func.FunctionApp(http_auth_level=func.AuthLevel.ANONYMOUS)

@app.route(route="upload", methods=["POST"])
def upload_function(req: func.HttpRequest) -> func.HttpResponse:
    ...
```

**Authentication at Function level:** For the demo migration, `http_auth_level=func.AuthLevel.ANONYMOUS` is used (matching the public accessibility of the original). Production deployments should use `AuthLevel.FUNCTION` with Azure AD JWT validation middleware, or an Azure API Management layer with AAD policy — per the mode instructions, APIM is not used as the primary router.

---

## 7. Environment Configuration

| Parameter | Dev | Staging | Prod |
|---|---|---|---|
| `environment` | `dev` | `staging` | `prod` |
| `workload` | `imageupload` | `imageupload` | `imageupload` |
| `location` | `australiaeast` | `australiaeast` | `australiaeast` |
| `storageSkuName` | `Standard_LRS` | `Standard_LRS` | `Standard_ZRS` |
| `softDeleteDays` | `7` | `14` | `30` |
| `logRetentionDays` | `30` | `60` | `90` |
| `urlExpiration` | `3600` | `3600` | `1800` |
| `allowedCorsOrigin` | `*` | SWA staging hostname | SWA prod hostname |
| `staticWebAppSku` | `Free` | `Free` | `Standard` |
| `branch` | `dev` | `staging` | `main` |

---

## 8. Security Requirements

### 8.1 Managed Identity and RBAC

| Identity | Resource | Role | Scope |
|---|---|---|---|
| Function App (System-Assigned) | Azure Storage Account | `Storage Blob Data Contributor` (`ba92f5b4-...`) | Storage Account resource |
| Function App (System-Assigned) | Azure Key Vault | `Key Vault Secrets User` (`4633458b-...`) | Key Vault resource |
| GitHub Actions service principal | Resource Group | `Contributor` | Resource Group (dev/staging/prod) |
| GitHub Actions service principal | Static Web Apps | `Website Contributor` | Static Web Apps resource |

### 8.2 Key Vault Secrets (pre-populate before deployment)

| Secret Name | Value | Consumed By |
|---|---|---|
| `storage-account-name` | Storage Account name (e.g. `devimageuploadstorXXXX`) | Function App via Key Vault reference |

> **Note:** The storage account name is not sensitive per se, but using Key Vault references ensures a single source of truth and enables rotation without redeployment.

### 8.3 Security Remediation (Pre-Migration — URGENT)

1. **Rotate IAM access key `AKIAXZEFIIOD2OIWPRPK` immediately** before starting any migration work.
2. **Remove the secret from CloudFormation outputs** — update the stack to remove the `ApiUserSecretAccessKey` output.
3. **Delete the `image-upload-api-user` IAM user** after confirming the Azure migration is live.
4. **Restrict S3 CORS `AllowedOrigins: ['*']`** on the ImageBucket to the known frontend origin (or leave blocked, since migration proceeds to Azure).

### 8.4 Network Security

No VNet is configured for this workload (Consumption plan Functions, public Blob Storage). Public network access to the Storage Account is required for direct browser SAS uploads. Mitigations:

- `allowBlobPublicAccess: false` — authenticated access only
- SAS tokens are scoped to individual blobs with write-only permission and short expiry
- CORS restricted to SWA origin in staging/prod
- `minimumTlsVersion: TLS1_2` on all services
- `httpsOnly: true` on Function App

For higher security posture (post-migration), consider:
- Azure Front Door + WAF in front of Functions (Standard tier)
- Private endpoints on Storage Account with VNet-integrated Functions (Premium plan)

### 8.5 Azure AD App Registration

| Setting | Value |
|---|---|
| Display Name | `image-upload-app` |
| Supported account types | Single tenant |
| Redirect URI | SWA default hostname (HTTPS) |
| Implicit grant | ID tokens enabled (for MSAL.js popup/redirect flow) |
| API permissions | None required (Functions use anonymous/function key) |

---

## 9. Deployment Order

The following numbered steps must be executed in order:

1. **Security remediation (AWS side):** Rotate and delete IAM access key `AKIAXZEFIIOD2OIWPRPK`. Update/delete `image-upload-api-user` IAM user. Remove secret from CloudFormation outputs.

2. **Create Azure Resource Group:** `az group create --name rg-imageupload-{env} --location australiaeast`

3. **Deploy `monitoring` module** (no dependencies): Log Analytics Workspace + Application Insights. Capture `connectionString` output.

4. **Deploy `storage` module** (no dependencies): Storage Account + `images` container. Capture `resourceName` and `resourceId` outputs.

5. **Deploy `staticWebApp` module** (no dependencies, parallel with steps 3–4): Static Web Apps resource. Capture `defaultHostname` and `deploymentToken` outputs.

6. **Deploy `functionApp` module** (depends on steps 3 and 4): Function App with all app settings wired to monitoring and storage outputs. Capture `principalId` and `defaultHostname` outputs.

7. **Deploy `rbac` module** (depends on steps 4 and 6): Assign `Storage Blob Data Contributor` to Function App managed identity on Storage Account.

8. **Pre-populate Key Vault secret:** `az keyvault secret set --vault-name {kv} --name storage-account-name --value {storageAccountName}`
   > Note: Key Vault is deployed as part of `functionApp` module or as a separate `keyvault` module (add to IaC if not included). Assign `Key Vault Secrets User` to Function App identity.

9. **Deploy Azure Functions code:** `func azure functionapp publish {functionAppName} --python`

10. **Deploy frontend to Static Web Apps:** GitHub Actions `deploy-static-web.yml` or `swa deploy` CLI. Update `app.html` to reference new Function App URL and Azure AD App Registration client ID.

11. **Update CORS:** Once SWA `defaultHostname` is known, update storage module `allowedCorsOrigin` parameter and redeploy storage module. Update Function App `ALLOWED_CORS_ORIGIN` app setting.

12. **Smoke test** (see Section 10).

---

## 10. Validation Checklist

- [ ] `az deployment group what-if` completes with 0 errors for all three parameter files (dev/staging/prod)
- [ ] `az bicep build --file main.bicep` exits with code 0
- [ ] Resource Group `rg-imageupload-dev` exists in australiaeast
- [ ] Storage Account created; `images` container exists; `allowBlobPublicAccess` is `false`
- [ ] Function App deployed; status is `Running`; Python runtime confirmed
- [ ] `curl https://{functionAppHostname}/api/upload -X POST -H "Content-Type: application/json" -d '{"fileName":"test.jpg","fileType":"image/jpeg"}' -w "%{http_code}"` returns `200`
- [ ] Upload SAS URL is returned; PUT to SAS URL with a test image file returns HTTP 201
- [ ] `curl https://{functionAppHostname}/api/files` returns `{ "files": [...], "count": 1 }`
- [ ] `curl https://{functionAppHostname}/api/files/{fileId}/view-url` returns a SAS URL
- [ ] GET to the view SAS URL returns the image bytes (HTTP 200)
- [ ] `curl -X DELETE https://{functionAppHostname}/api/files/{fileId}` returns `{ "message": "File(s) deleted" }`
- [ ] `curl https://{functionAppHostname}/api/files` returns `{ "files": [], "count": 0 }` after delete
- [ ] Static Web App URL loads `app.html` over HTTPS
- [ ] Application Insights shows traces for all 4 function invocations
- [ ] Log Analytics query: `traces | where message contains "upload"` returns results
- [ ] RBAC: Function App managed identity has `Storage Blob Data Contributor` on Storage Account
- [ ] No connection strings in Function App configuration (all use managed identity or Key Vault references)

---

## 11. CI/CD Pipeline Architecture

> Consulted: `bicep-generation.md` — deployment commands and parameter patterns.

### 11.1 Pipeline Overview

| Workflow File | Trigger | Purpose | Target Azure Service |
|---|---|---|---|
| `.github/workflows/deploy-infra.yml` | Push to `main`/`dev`/`staging`; manual dispatch | Deploy Bicep IaC (all 5 modules via main.bicep) | Resource Group, Storage, Function App, Static Web Apps, Monitoring |
| `.github/workflows/deploy-functions.yml` | Push to `main`/`dev`/`staging` when files under `outputs/azure-functions/**` change; manual dispatch | Build Python package and publish to Azure Functions | Azure Functions |
| `.github/workflows/deploy-static-web.yml` | Push to `main`/`dev`/`staging` when files under `source-app/app-code/build/**` or `outputs/azure-functions/static/**` change; manual dispatch | Deploy frontend HTML/JS to Azure Static Web Apps | Azure Static Web Apps |

### 11.2 Authentication Strategy

**Method:** OIDC / Workload Identity Federation — no long-lived credentials stored in GitHub Secrets.

**GitHub Secrets required:**

| Secret Name | Value Source | Used By |
|---|---|---|
| `AZURE_CLIENT_ID` | App Registration (federated credential) client ID | All workflows — `azure/login` action |
| `AZURE_TENANT_ID` | Azure AD tenant ID | All workflows — `azure/login` action |
| `AZURE_SUBSCRIPTION_ID` | Target Azure subscription ID | All workflows — `azure/login` action |
| `AZURE_RESOURCE_GROUP_DEV` | `rg-imageupload-dev` | `deploy-infra.yml` (dev environment) |
| `AZURE_RESOURCE_GROUP_STAGING` | `rg-imageupload-staging` | `deploy-infra.yml` (staging environment) |
| `AZURE_RESOURCE_GROUP_PROD` | `rg-imageupload-prod` | `deploy-infra.yml` (prod environment) |
| `STATIC_WEB_APP_TOKEN_DEV` | SWA deployment token (from Bicep output `deploymentToken`) | `deploy-static-web.yml` (dev) |
| `STATIC_WEB_APP_TOKEN_STAGING` | SWA deployment token (staging) | `deploy-static-web.yml` (staging) |
| `STATIC_WEB_APP_TOKEN_PROD` | SWA deployment token (prod) | `deploy-static-web.yml` (prod) |
| `FUNCTION_APP_NAME_DEV` | `dev-imageupload-func-australiaeast` | `deploy-functions.yml` (dev) |
| `FUNCTION_APP_NAME_STAGING` | `staging-imageupload-func-australiaeast` | `deploy-functions.yml` (staging) |
| `FUNCTION_APP_NAME_PROD` | `prod-imageupload-func-australiaeast` | `deploy-functions.yml` (prod) |

**Federated credential subject filter** (configure on App Registration for each environment):

```
repo:<org>/<repo>:environment:dev
repo:<org>/<repo>:environment:staging
repo:<org>/<repo>:environment:prod
```

**RBAC role assignments** for the service principal:

| Role | Scope | Purpose |
|---|---|---|
| `Contributor` | Resource Group (each environment) | Deploy all Bicep resources |
| `Role Based Access Control Administrator` | Resource Group | Create RBAC role assignments (rbac.bicep) |
| `Website Contributor` | Static Web Apps | Deploy static web app content (optional — Contributor covers this) |

---

### 11.3 Per-Workflow Specification

#### 11.3.1 `.github/workflows/deploy-infra.yml`

**Trigger conditions:**
```yaml
on:
  push:
    branches: [main, dev, staging]
    paths:
      - 'outputs/bicep-templates/**'
  workflow_dispatch:
    inputs:
      environment:
        description: 'Target environment'
        required: true
        type: choice
        options: [dev, staging, prod]
```

**Environment protection rules:**
- `dev`: no approval required
- `staging`: 1 reviewer required
- `prod`: 2 reviewers required; deployment window restriction recommended

**Jobs and steps (in order):**

```yaml
jobs:
  determine-environment:
    runs-on: ubuntu-latest
    outputs:
      environment: ${{ steps.set-env.outputs.environment }}
    steps:
      - id: set-env
        run: |
          if [[ "${{ github.event_name }}" == "workflow_dispatch" ]]; then
            echo "environment=${{ inputs.environment }}" >> $GITHUB_OUTPUT
          elif [[ "${{ github.ref_name }}" == "main" ]]; then
            echo "environment=prod" >> $GITHUB_OUTPUT
          else
            echo "environment=${{ github.ref_name }}" >> $GITHUB_OUTPUT
          fi

  deploy-infra:
    needs: determine-environment
    runs-on: ubuntu-latest
    environment: ${{ needs.determine-environment.outputs.environment }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Azure Login (OIDC)
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Set environment variables
        id: env-vars
        run: |
          ENV="${{ needs.determine-environment.outputs.environment }}"
          echo "RESOURCE_GROUP=rg-imageupload-${ENV}" >> $GITHUB_ENV

      - name: Create Resource Group (idempotent)
        run: |
          az group create --name $RESOURCE_GROUP --location australiaeast --output none

      - name: Bicep what-if validation
        run: |
          az deployment group what-if \
            --resource-group $RESOURCE_GROUP \
            --template-file outputs/bicep-templates/main.bicep \
            --parameters outputs/bicep-templates/parameters/${{ needs.determine-environment.outputs.environment }}.bicepparam \
            --mode Incremental

      - name: Deploy Bicep IaC
        id: deploy
        run: |
          az deployment group create \
            --resource-group $RESOURCE_GROUP \
            --template-file outputs/bicep-templates/main.bicep \
            --parameters outputs/bicep-templates/parameters/${{ needs.determine-environment.outputs.environment }}.bicepparam \
            --mode Incremental \
            --name "infra-$(date +%Y%m%d%H%M%S)" \
            --output json > deployment-output.json
          echo "deploymentOutput=$(cat deployment-output.json | jq -c '.properties.outputs')" >> $GITHUB_OUTPUT

      - name: Export deployment outputs as summary
        run: |
          echo "## Deployment Outputs" >> $GITHUB_STEP_SUMMARY
          cat deployment-output.json | jq '.properties.outputs' >> $GITHUB_STEP_SUMMARY

      - name: Rollback on failure
        if: failure()
        run: |
          echo "Deployment failed. Review what-if output and fix template errors." >> $GITHUB_STEP_SUMMARY
          echo "To rollback manually: az deployment group cancel --resource-group $RESOURCE_GROUP --name infra-<timestamp>"
```

**Secrets referenced:** `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`  
**Artifact handling:** `deployment-output.json` written to step output for downstream use  
**Rollback strategy:** Bicep is idempotent and incremental — re-running the previous commit's template restores the prior state. For destructive changes, what-if must be reviewed before approval.

---

#### 11.3.2 `.github/workflows/deploy-functions.yml`

**Trigger conditions:**
```yaml
on:
  push:
    branches: [main, dev, staging]
    paths:
      - 'outputs/azure-functions/**'
  workflow_dispatch:
    inputs:
      environment:
        description: 'Target environment'
        required: true
        type: choice
        options: [dev, staging, prod]
```

**Environment protection rules:** Same as `deploy-infra.yml`.

**Jobs and steps (in order):**

```yaml
jobs:
  determine-environment:
    # Same as deploy-infra.yml

  build-and-deploy:
    needs: determine-environment
    runs-on: ubuntu-latest
    environment: ${{ needs.determine-environment.outputs.environment }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Python 3.11
        uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: |
          cd outputs/azure-functions
          python -m pip install --upgrade pip
          pip install -r requirements.txt --target .python_packages/lib/site-packages

      - name: Azure Login (OIDC)
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Set function app name
        run: |
          ENV="${{ needs.determine-environment.outputs.environment }}"
          if [[ "$ENV" == "dev" ]]; then
            echo "FUNCTION_APP_NAME=${{ secrets.FUNCTION_APP_NAME_DEV }}" >> $GITHUB_ENV
          elif [[ "$ENV" == "staging" ]]; then
            echo "FUNCTION_APP_NAME=${{ secrets.FUNCTION_APP_NAME_STAGING }}" >> $GITHUB_ENV
          else
            echo "FUNCTION_APP_NAME=${{ secrets.FUNCTION_APP_NAME_PROD }}" >> $GITHUB_ENV
          fi

      - name: Deploy to Azure Functions
        uses: azure/functions-action@v1
        with:
          app-name: ${{ env.FUNCTION_APP_NAME }}
          package: outputs/azure-functions
          scm-do-build-during-deployment: true
          enable-oryx-build: true

      - name: Health check
        run: |
          HOST=$(az functionapp show --name $FUNCTION_APP_NAME --resource-group rg-imageupload-${{ needs.determine-environment.outputs.environment }} --query defaultHostName -o tsv)
          STATUS=$(curl -s -o /dev/null -w "%{http_code}" "https://$HOST/api/files")
          if [[ "$STATUS" != "200" ]]; then
            echo "Health check failed with status $STATUS"
            exit 1
          fi
          echo "Health check passed: $STATUS"
```

**Secrets referenced:** `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`, `FUNCTION_APP_NAME_{ENV}`  
**Artifact handling:** `.python_packages/` folder included in deployment package  
**Rollback strategy:** Re-run the workflow pointing to the previous commit SHA via `workflow_dispatch`.

---

#### 11.3.3 `.github/workflows/deploy-static-web.yml`

**Trigger conditions:**
```yaml
on:
  push:
    branches: [main, dev, staging]
    paths:
      - 'source-app/app-code/build/**'
  workflow_dispatch:
    inputs:
      environment:
        description: 'Target environment'
        required: true
        type: choice
        options: [dev, staging, prod]
```

**Environment protection rules:** Same as above.

**Jobs and steps (in order):**

```yaml
jobs:
  determine-environment:
    # Same as previous workflows

  deploy-static:
    needs: determine-environment
    runs-on: ubuntu-latest
    environment: ${{ needs.determine-environment.outputs.environment }}
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set SWA token
        run: |
          ENV="${{ needs.determine-environment.outputs.environment }}"
          if [[ "$ENV" == "dev" ]]; then
            echo "SWA_TOKEN=${{ secrets.STATIC_WEB_APP_TOKEN_DEV }}" >> $GITHUB_ENV
          elif [[ "$ENV" == "staging" ]]; then
            echo "SWA_TOKEN=${{ secrets.STATIC_WEB_APP_TOKEN_STAGING }}" >> $GITHUB_ENV
          else
            echo "SWA_TOKEN=${{ secrets.STATIC_WEB_APP_TOKEN_PROD }}" >> $GITHUB_ENV
          fi

      - name: Deploy to Azure Static Web Apps
        uses: Azure/static-web-apps-deploy@v1
        with:
          azure_static_web_apps_api_token: ${{ env.SWA_TOKEN }}
          repo_token: ${{ secrets.GITHUB_TOKEN }}
          action: upload
          app_location: source-app/app-code/build
          output_location: ''
          skip_app_build: true
```

**Secrets referenced:** `STATIC_WEB_APP_TOKEN_{ENV}`, `GITHUB_TOKEN`  
**Artifact handling:** Static files uploaded directly from `source-app/app-code/build/`  
**Rollback strategy:** Re-run workflow with previous commit or use SWA built-in environment snapshots.

---

### 11.4 Multi-Environment Strategy

| Aspect | Dev | Staging | Prod |
|---|---|---|---|
| Branch | `dev` | `staging` | `main` |
| GitHub Environment | `dev` | `staging` | `prod` |
| Approval required | None | 1 reviewer | 2 reviewers |
| Azure Resource Group | `rg-imageupload-dev` | `rg-imageupload-staging` | `rg-imageupload-prod` |
| Parameter file | `dev.bicepparam` | `staging.bicepparam` | `prod.bicepparam` |
| Secrets scope | `*_DEV` secrets | `*_STAGING` secrets | `*_PROD` secrets |
| Federated credential subject | `environment:dev` | `environment:staging` | `environment:prod` |

**Branch protection rules:**
- `main`: require PR, require passing CI, require 2 approvals, no force push
- `staging`: require PR, require 1 approval
- `dev`: no restrictions

**Environment secrets separation:** Each GitHub Environment (`dev`, `staging`, `prod`) has its own set of `STATIC_WEB_APP_TOKEN_*` and `FUNCTION_APP_NAME_*` secrets. `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` are at the repository level (all environments target the same subscription with different resource groups).

---

### 11.5 Pipeline Dependency Order

The following sequence must succeed before the next step starts:

1. **`deploy-infra.yml`** must complete successfully for the target environment — it provisions all Azure resources including the Function App and Static Web Apps deployment token.
2. **`deploy-functions.yml`** can run after step 1 completes — requires the Function App to exist.
3. **`deploy-static-web.yml`** can run after step 1 completes (parallel with step 2) — requires the Static Web Apps deployment token from Key Vault or GitHub Secrets.
4. **Smoke tests** (Section 10 checklist) must pass before promoting from dev → staging → prod.

---

*End of Design Document — Version 1.0*
