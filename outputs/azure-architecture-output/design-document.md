# Azure Architecture Design Document

**Project:** Image Upload Photo Gallery — AWS → Azure Migration  
**Source AWS Account:** 535002891143 (ap-southeast-2)  
**Target Azure Region:** Australia East (australiaeast)  
**Document Version:** 1.0  
**Date:** 2026-05-19  
**Prepared by:** Azure Architect Agent (azure-architect mode)  

---

## 1. Executive Summary

This document specifies the full Azure target architecture for migrating the **image-upload** photo gallery application from AWS (account 535002891143, ap-southeast-2) to Azure Australia East. The application is a low-complexity serverless photo gallery comprising four Python 3.11 Lambda functions behind an API Gateway REST API, an S3 image-storage bucket, and an S3-hosted static single-page application. The migration adopts an **equivalent-serverless** pattern: AWS Lambda → Azure Functions (Consumption Y1), Amazon API Gateway → Azure Functions HTTP triggers (no API Management), Amazon S3 (images) → Azure Blob Storage (Standard LRS, Hot), Amazon S3 (static website) → Azure Static Web Apps (Free tier), IAM role → System-assigned Managed Identity + `Storage Blob Data Contributor` RBAC. The primary outcome is a 40–50 % cost reduction (~$3.50/month AWS → ~$1.60/month Azure), elimination of the critical IAM-user static key security vulnerability, and a repeatable Bicep + GitHub Actions deployment pipeline for dev/staging/prod environments.

---

## 2. AWS Discovery Summary

All data sourced from `outputs/aws-migration-artifacts/aws-inventory.json` and `outputs/aws-migration-artifacts/migration-assessment.md`, verified against live AWS account 535002891143 on 2026-05-19.

### In-scope resources (14)

| Resource | Type | ARN / ID | Criticality |
|---|---|---|---|
| image-upload-UploadFunction-iIIJ7xiZECuB | Lambda Python 3.11 | arn:aws:lambda:ap-southeast-2:535002891143:function:image-upload-UploadFunction-iIIJ7xiZECuB | HIGH |
| image-upload-ListFilesFunction-Pb0dKq9dR0Is | Lambda Python 3.11 | arn:aws:lambda:ap-southeast-2:535002891143:function:image-upload-ListFilesFunction-Pb0dKq9dR0Is | HIGH |
| image-upload-GetViewUrlFunction-yMGI9X8Us5Em | Lambda Python 3.11 | arn:aws:lambda:ap-southeast-2:535002891143:function:image-upload-GetViewUrlFunction-yMGI9X8Us5Em | MEDIUM |
| image-upload-DeleteFileFunction-EG7Cfj3m2P6f | Lambda Python 3.11 | arn:aws:lambda:ap-southeast-2:535002891143:function:image-upload-DeleteFileFunction-EG7Cfj3m2P6f | HIGH |
| image-upload-imagebucket-t8isnbr8sswv | S3 Bucket (image store, versioning enabled, SSE-S3) | arn:aws:s3:::image-upload-imagebucket-t8isnbr8sswv | CRITICAL |
| image-upload-websitebucket-vd866vxtcs1z | S3 Bucket (static website, public read, app.html index) | arn:aws:s3:::image-upload-websitebucket-vd866vxtcs1z | MEDIUM |
| image-upload-api (4lrh2l7i86) | API Gateway REST REGIONAL, stage: dev, auth: AWS_IAM | arn:aws:apigateway:ap-southeast-2::/restapis/4lrh2l7i86 | CRITICAL |
| image-upload-LambdaExecutionRole-2MhYmRQ3aAnA | IAM Role (Lambda execution, AWSLambdaBasicExecutionRole + S3 CRUD) | arn:aws:iam::535002891143:role/image-upload-LambdaExecutionRole-2MhYmRQ3aAnA | CRITICAL |
| image-upload-ApiGatewayCloudWatchLogsRole-YGFCwY9oRVqq | IAM Role (API GW → CloudWatch) | arn:aws:iam::535002891143:role/image-upload-ApiGatewayCloudWatchLogsRole-YGFCwY9oRVqq | LOW |
| image-upload-api-user | IAM User (static access key AKIAXZEFIIOD2OIWPRPK — CRITICAL security risk) | arn:aws:iam::535002891143:user/image-upload-api-user | CRITICAL |
| image-upload | CloudFormation Stack (CREATE_COMPLETE) | arn:aws:cloudformation:ap-southeast-2:535002891143:stack/image-upload | HIGH |
| /aws/lambda/image-upload-UploadFunction-* | CloudWatch Log Group | — | MEDIUM |
| /aws/lambda/image-upload-ListFilesFunction-* | CloudWatch Log Group | — | MEDIUM |
| API-Gateway-Execution-Logs_4lrh2l7i86/dev | CloudWatch Log Group | — | LOW |

### Lambda function details

| Function | Handler | Memory | Timeout | Env Vars |
|---|---|---|---|---|
| UploadFunction | upload_handler.lambda_handler | 256 MB | 30 s | BUCKET_NAME, URL_EXPIRATION=3600 |
| ListFilesFunction | list_handler.lambda_handler | 256 MB | 30 s | BUCKET_NAME, URL_EXPIRATION=3600 |
| GetViewUrlFunction | view_handler.lambda_handler | 256 MB | 30 s | BUCKET_NAME, URL_EXPIRATION=3600 |
| DeleteFileFunction | delete_handler.lambda_handler | 256 MB | 30 s | BUCKET_NAME |

### API endpoints

| AWS Endpoint | Method | Auth | Lambda |
|---|---|---|---|
| POST /upload | POST | AWS_IAM | UploadFunction |
| GET /files | GET | AWS_IAM | ListFilesFunction |
| GET /files/{fileId}/view-url | GET | AWS_IAM | GetViewUrlFunction |
| DELETE /files/{fileId} | DELETE | AWS_IAM | DeleteFileFunction |
| OPTIONS /* | OPTIONS | NONE | MOCK (CORS) |

### Key observations
- **No database, no message queue, no container infrastructure** — pure serverless + object storage.
- Object key pattern `{uuid4}/{original_filename}` is preserved on Azure unchanged.
- S3 metadata (`x-amz-meta-uploaddate`, `x-amz-meta-originalfilename`, `x-amz-meta-description`) maps to Azure blob `metadata` dict after stripping the `x-amz-meta-` prefix.
- **Critical security blocker:** static IAM access key (AKIAXZEFIIOD2OIWPRPK) is hard-coded in the SPA front-end. This MUST be replaced by Azure Function App key (`x-functions-key` header) before go-live.
- Current AWS monthly cost: ~$3.50 USD.

---

## 3. Azure Service Mapping

> Consulted: `azure-functions/SKILL.md` §Decision Making, §Deployment; `azure-blob-storage/SKILL.md` §Best Practices, §Security; `azure-static-web-apps/SKILL.md` §Decision Making, §Deployment; `azure-architecture/SKILL.md` §Migration Guides.

| AWS Service | AWS Config | Azure Equivalent | Azure Config | Migration Notes |
|---|---|---|---|---|
| **Lambda (Python 3.11) × 4** | 256 MB, 30 s, x86_64, no VNet, no layers | **Azure Functions v2 (Python 3.11, Consumption Y1)** | Single Function App, 4 HTTP-triggered functions, system-assigned MI | `boto3` → `azure-storage-blob`; `lambda_handler(event, context)` → `main(req: func.HttpRequest)`; Consumption plan = cost-equivalent; SKU justification: <1M req/month, no VNet needed, 30 s timeout fits 10-min Consumption limit |
| **Amazon API Gateway REST** | REGIONAL, 4 routes, AWS_IAM auth, SigV4, stage=dev | **Azure Functions HTTP triggers (built-in)** | Route prefix `/api/`, function-level API key auth (`x-functions-key`), CORS in `host.json` | No API Management — APIM explicitly forbidden; HTTP trigger provides equivalent routing; `x-functions-key` header replaces SigV4 |
| **S3 ImageBucket** (versioning ON, SSE-S3, CORS *, 10 MB max, `{uuid}/{filename}`) | 1 bucket, Standard, ~1 GB, LRS equivalent | **Azure Blob Storage** (Standard LRS, Hot tier, container `images`) | StorageV2, LRS, Hot, CORS configured, blob versioning optional, max blob size up to 5 TB (policy: 10 MB enforced via SAS policy) | `generate_presigned_post()` → `generate_blob_sas(BlobSasPermissions(write=True))`; SPA changes from multipart POST to PUT with SAS URL; metadata `x-amz-meta-*` → `blob.metadata` dict |
| **S3 WebsiteBucket** (static website, public read, `app.html` index) | 1 bucket, public | **Azure Static Web Apps (Free tier)** | Free plan, `index.html` (rename from `app.html`), custom domain optional, built-in CDN | Free tier includes global CDN, custom domain, 100 GB bandwidth/month; rename `app.html` → `index.html`; SPA JS config must replace API URL and auth |
| **IAM Role (LambdaExecutionRole)** | AWSLambdaBasicExecutionRole + S3 CRUD inline policy on ImageBucket | **System-assigned Managed Identity on Function App** | MI auto-created with Function App; `Storage Blob Data Contributor` role assignment on Storage Account | Single MI covers all 4 functions; no credential rotation needed |
| **IAM User + Access Key** (SPA auth, static key in browser) | AKIAXZEFIIOD2OIWPRPK, execute-api:Invoke | **Azure Functions key (`x-functions-key` header)** | Function-level default key stored in Azure Functions secrets (Key Vault-backed in prod) | Replace SigV4 signing with simple header; SPA JS updated; for prod upgrade to Azure AD MSAL if user-identity auth needed |
| **CloudFormation** | 1 stack, ap-southeast-2, CREATE_COMPLETE | **Azure Bicep** | `main.bicep` + 6 modules; `dev.bicepparam`, `staging.bicepparam`, `prod.bicepparam` | Direct declarative equivalent; same parameter/output concept; Bicep outputs map to equivalent CF outputs |
| **CloudWatch Logs** (3 log groups) | Lambda + API GW execution logs | **Application Insights + Log Analytics Workspace** | Built-in with Azure Functions; no explicit log group config; 30-day default retention | Structured logging preserved; KQL replaces CloudWatch Insights; `logging.getLogger()` → Application Insights via `APPLICATIONINSIGHTS_CONNECTION_STRING` |
| **CloudWatch Alarms** (AppStream-related, not in scope) | N/A | N/A — Azure Monitor Metric Alerts | Optional post-migration | Not in application scope |

---

## 4. Target Architecture

### Architecture Diagram

```mermaid
%%{ init: { "theme": "default", "flowchart": { "curve": "basis" } } }%%
graph TB
    classDef userLayer fill:#e8f5e9,stroke:#388e3c,color:#1b5e20
    classDef frontendLayer fill:#e3f2fd,stroke:#1565c0,color:#0d47a1
    classDef computeLayer fill:#fce4ec,stroke:#880e4f,color:#880e4f
    classDef storageLayer fill:#f3e5f5,stroke:#4a148c,color:#4a148c
    classDef identityLayer fill:#e8eaf6,stroke:#283593,color:#283593
    classDef monitorLayer fill:#e0f7fa,stroke:#006064,color:#006064
    classDef infraLayer fill:#fafafa,stroke:#9e9e9e,color:#424242
    classDef cicdLayer fill:#fff8e1,stroke:#f57f17,color:#e65100

    subgraph USERS["👤 Users / Browsers"]
        USER[Browser Client<br/>Photo Gallery SPA]:::userLayer
    end

    subgraph FRONTEND["🌐 Static Hosting — Azure Static Web Apps (Free)"]
        SWA["Azure Static Web Apps<br/>Free tier | Australia East<br/>index.html — Global CDN<br/>URL: *.azurestaticapps.net"]:::frontendLayer
    end

    subgraph COMPUTE["⚡ Compute — Azure Functions (Consumption Y1, Python 3.11)"]
        FA["Function App: photo-gallery-func<br/>Australia East | Consumption Y1<br/>System-assigned Managed Identity<br/>CORS: SWA origin"]:::computeLayer
        UPLOAD["upload_image()<br/>POST /api/upload<br/>Returns SAS write URL + fields<br/>Stores metadata in blob.metadata"]:::computeLayer
        LIST["list_images()<br/>GET /api/files<br/>Lists blobs + generates SAS read URLs<br/>Supports prefix & max_results params"]:::computeLayer
        VIEW["get_view_url()<br/>GET /api/files/{fileId}/view-url<br/>Generates SAS read URL<br/>Lookup by fileId/ prefix"]:::computeLayer
        DELETE["delete_image()<br/>DELETE /api/files/{fileId}<br/>Deletes all blobs under fileId/ prefix"]:::computeLayer
    end

    subgraph STORAGE["🗄️ Storage — Azure Blob Storage (Standard LRS, Hot)"]
        SA["Storage Account: photogallerysto<br/>Standard LRS | Hot tier<br/>Australia East | StorageV2"]:::storageLayer
        CONTAINER["Container: images<br/>Private access<br/>Blob versioning optional<br/>CORS: all origins (restrict in prod)<br/>Key pattern: {uuid4}/{filename}"]:::storageLayer
        FUNCSTORAGE["Container: azure-webjobs-*<br/>Function App runtime storage<br/>(internal, same account)"]:::storageLayer
    end

    subgraph IDENTITY["🔐 Identity — Azure RBAC"]
        MI["System-assigned Managed Identity<br/>on Function App<br/>Storage Blob Data Contributor<br/>on photogallerysto"]:::identityLayer
        FUNCKEY["Function App Default Key<br/>x-functions-key header<br/>SPA reads from config<br/>(Key Vault-backed in prod)"]:::identityLayer
    end

    subgraph MONITOR["📊 Monitoring — Azure Monitor"]
        AI["Application Insights<br/>Distributed tracing<br/>Request logs, exceptions<br/>Live Metrics"]:::monitorLayer
        LAW["Log Analytics Workspace<br/>30-day retention (dev)<br/>90-day retention (prod)<br/>KQL queries"]:::monitorLayer
    end

    subgraph INFRA["🏗️ IaC — Azure Bicep"]
        BICEP["main.bicep<br/>6 modules<br/>dev / staging / prod params"]:::infraLayer
    end

    subgraph CICD["🔄 CI/CD — GitHub Actions"]
        GHA["3 Workflows<br/>deploy-infra.yml<br/>deploy-functions.yml<br/>deploy-static-web.yml<br/>OIDC / Workload Identity"]:::cicdLayer
    end

    %% User flows
    USER -->|"1. Load SPA"| SWA
    SWA -->|"Static files (CDN)"| USER
    USER -->|"2. API calls (x-functions-key header)"| FA

    %% Function App routing
    FA --> UPLOAD
    FA --> LIST
    FA --> VIEW
    FA --> DELETE

    %% Functions → Blob Storage (via Managed Identity)
    UPLOAD -->|"generate_blob_sas(write)"| CONTAINER
    LIST -->|"list_blobs() + generate_blob_sas(read)"| CONTAINER
    VIEW -->|"list_blobs() + generate_blob_sas(read)"| CONTAINER
    DELETE -->|"list_blobs() + delete_blob()"| CONTAINER

    %% Direct upload from browser
    USER -->|"3. Direct PUT to Blob (SAS URL)"| CONTAINER

    %% Identity
    MI -->|"authenticates"| FA
    MI -->|"Storage Blob Data Contributor"| SA
    FUNCKEY -->|"API auth for SPA"| FA

    %% Monitoring
    FA -->|"telemetry"| AI
    AI -->|"logs"| LAW

    %% IaC provisions all
    BICEP -.->|"provisions"| FA
    BICEP -.->|"provisions"| SA
    BICEP -.->|"provisions"| SWA
    BICEP -.->|"provisions"| AI
    BICEP -.->|"provisions"| LAW
    BICEP -.->|"provisions"| MI

    %% CI/CD deploys
    GHA -.->|"deploys via"| BICEP
    GHA -.->|"deploys code to"| FA
    GHA -.->|"deploys static to"| SWA
```

### Component descriptions

**Azure Static Web Apps (Free):** Replaces the S3 static website bucket. Hosts `index.html` (renamed from `app.html`) and serves it globally via built-in CDN. Free tier provides 100 GB/month bandwidth, custom domains, and automated GitHub Actions deployment. No cost.

**Azure Functions (Consumption Y1, Australia East):** Replaces all four Lambda functions plus the API Gateway. A single Function App hosts all four HTTP-triggered functions under the `/api/` route prefix. Consumption plan scales to zero and bills only for actual executions — appropriate for <100K requests/month. System-assigned Managed Identity authenticates to Blob Storage without credentials.

**Azure Blob Storage (Standard LRS, Hot):** Replaces the S3 image bucket. Container `images` stores blobs with the same `{uuid4}/{filename}` key pattern. SAS tokens (write-permission, 1-hour expiry) replace S3 pre-signed POST URLs. SAS tokens (read-permission) replace S3 pre-signed GET URLs. Custom metadata fields (`uploaddate`, `originalfilename`, `description`) map to `blob.metadata` dict.

**System-assigned Managed Identity + RBAC:** Replaces `image-upload-LambdaExecutionRole`. The MI is automatically created with the Function App. A `Storage Blob Data Contributor` role assignment on the Storage Account grants read/write/delete permissions. `DefaultAzureCredential` in application code resolves the MI token transparently.

**Application Insights + Log Analytics Workspace:** Replaces CloudWatch Logs. Application Insights collects request logs, exceptions, and distributed traces automatically when `APPLICATIONINSIGHTS_CONNECTION_STRING` is set in Function App settings. Log Analytics Workspace stores structured logs with KQL query support.

**Azure Bicep (main.bicep + 6 modules):** Replaces the CloudFormation stack. Parameterised for dev/staging/prod with separate `.bicepparam` files.

**GitHub Actions (3 workflows):** Provides CI/CD using OIDC / Workload Identity Federation — no long-lived secrets. Deploys IaC, Functions code, and Static Web App in dependency order.

---

## 5. Infrastructure as Code Specification

Root template: `outputs/bicep-templates/main.bicep`  
Module directory: `outputs/bicep-templates/modules/`  
Parameter files: `outputs/bicep-templates/parameters/dev.bicepparam`, `staging.bicepparam`, `prod.bicepparam`

### 5.1 `storage.bicep` (`modules/storage.bicep`)

**Purpose:** Deploys the Azure Storage Account and the `images` blob container.

**Parameters:**

| Name | Type | Allowed Values | Description |
|---|---|---|---|
| `storageAccountName` | string | 3–24 lowercase alphanumeric | Globally unique storage account name |
| `location` | string | Azure region | Deployment region |
| `skuName` | string | `Standard_LRS`, `Standard_GRS` | Storage SKU; dev=LRS, prod=GRS |
| `containerName` | string | — | Blob container name (default `images`) |
| `corsAllowedOrigins` | array | — | CORS allowed origins list; dev=['*'], prod=[SWA URL] |
| `enableBlobVersioning` | bool | — | Enable blob versioning; false for dev, true for prod |

**Resources:**

```bicep
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  kind: 'StorageV2'
  sku: { name: skuName }
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
    isVersioningEnabled: enableBlobVersioning
  }
}
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-01-01' = {
  // CORS rules, versioning policy
}
resource imagesContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-01-01' = {
  properties: { publicAccess: 'None' }
}
```

**Outputs:**

| Name | Type | Description |
|---|---|---|
| `storageAccountId` | string | Resource ID of the storage account |
| `storageAccountName` | string | Name of the storage account |
| `blobEndpoint` | string | Primary blob service endpoint URL |
| `storageConnectionString` | string | Connection string (used only for Function App runtime storage in dev; in prod use MI) |

**Security requirements:**
- `allowBlobPublicAccess: false` — all access via SAS or MI
- `minimumTlsVersion: TLS1_2`
- `supportsHttpsTrafficOnly: true`
- No public network access restrictions needed for this workload (Functions accesses via service endpoint or internet with MI token)

**Environment differences:**

| Parameter | Dev | Staging | Prod |
|---|---|---|---|
| `skuName` | Standard_LRS | Standard_LRS | Standard_GRS |
| `enableBlobVersioning` | false | false | true |
| `corsAllowedOrigins` | ['*'] | ['*'] | [SWA prod URL] |

---

### 5.2 `identity.bicep` (`modules/identity.bicep`)

**Purpose:** Outputs are used by `functionApp.bicep`; actual MI is created as part of the Function App resource. This module creates a user-assigned managed identity as an alternative (or validates system-assigned MI is used correctly). For this workload, the system-assigned MI on the Function App is sufficient — this module is kept minimal.

> **Note:** For simplicity and cost-effectiveness, system-assigned MI is used and created inline in `functionApp.bicep`. The `identity.bicep` module can be omitted or used as a placeholder for future user-assigned MI if multi-resource identity sharing is required.

**Parameters:** `location`, `identityName` (if user-assigned)  
**Resources:** `Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31` (optional)  
**Outputs:** `principalId`, `clientId` (forwarded to rbac.bicep)

---

### 5.3 `functionApp.bicep` (`modules/functionApp.bicep`)

**Purpose:** Deploys the Consumption-plan Azure Function App (Python 3.11 v2), the App Service Plan (Y1), and the associated Azure Functions runtime storage account connection.

**Parameters:**

| Name | Type | Allowed Values | Description |
|---|---|---|---|
| `functionAppName` | string | — | Globally unique Function App name |
| `location` | string | — | Deployment region |
| `storageAccountName` | string | — | Storage account for Function runtime (same account used for blobs) |
| `storageAccountId` | string | — | Resource ID of the storage account |
| `appInsightsConnectionString` | string | — | Application Insights connection string |
| `imageContainerName` | string | — | Blob container name for images (default `images`) |
| `urlExpiration` | int | 300–86400 | SAS token lifetime in seconds (default 3600) |
| `allowedCorsOrigins` | array | — | CORS origins for HTTP triggers |
| `functionAppSkuName` | string | `Y1` | Consumption plan SKU; hardcoded Y1 per cost constraints |

**Resources:**

```bicep
resource hostingPlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  sku: { name: 'Y1', tier: 'Dynamic' }
  properties: { reserved: true }  // Linux
}

resource functionApp 'Microsoft.Web/sites@2022-09-01' = {
  kind: 'functionapp,linux'
  identity: { type: 'SystemAssigned' }
  properties: {
    serverFarmId: hostingPlan.id
    siteConfig: {
      pythonVersion: '3.11'
      linuxFxVersion: 'Python|3.11'
      appSettings: [
        { name: 'AzureWebJobsStorage', value: 'DefaultEndpointsProtocol=https;...' }
        { name: 'FUNCTIONS_EXTENSION_VERSION', value: '~4' }
        { name: 'FUNCTIONS_WORKER_RUNTIME', value: 'python' }
        { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsightsConnectionString }
        { name: 'STORAGE_ACCOUNT_NAME', value: storageAccountName }
        { name: 'BLOB_CONTAINER_NAME', value: imageContainerName }
        { name: 'URL_EXPIRATION', value: string(urlExpiration) }
      ]
      cors: {
        allowedOrigins: allowedCorsOrigins
        supportCredentials: false
      }
    }
    httpsOnly: true
  }
}
```

**Outputs:**

| Name | Type | Description |
|---|---|---|
| `functionAppId` | string | Resource ID of the Function App |
| `functionAppName` | string | Name of the Function App |
| `functionAppHostname` | string | Default hostname (e.g., `photo-gallery-func.azurewebsites.net`) |
| `principalId` | string | System-assigned MI principal ID (forwarded to rbac.bicep) |
| `functionAppDefaultKey` | string | Default function key (obtain post-deployment via `az functionapp keys list`) |

**Security requirements:**
- `httpsOnly: true`
- `identity.type: SystemAssigned`
- App settings must NOT include storage account keys in prod — use MI + `DefaultAzureCredential`
- CORS restricted to SWA domain in prod

**Environment differences:**

| Parameter | Dev | Staging | Prod |
|---|---|---|---|
| `allowedCorsOrigins` | ['*'] | ['https://staging.azurestaticapps.net'] | ['https://prod.azurestaticapps.net'] |
| `urlExpiration` | 3600 | 3600 | 3600 |

---

### 5.4 `monitoring.bicep` (`modules/monitoring.bicep`)

**Purpose:** Deploys the Log Analytics Workspace and Application Insights instance linked to the Function App.

**Parameters:**

| Name | Type | Description |
|---|---|---|
| `workspaceName` | string | Log Analytics Workspace name |
| `appInsightsName` | string | Application Insights name |
| `location` | string | Deployment region |
| `retentionDays` | int | Log retention in days (30=dev, 90=prod) |

**Resources:**

```bicep
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  properties: { retentionInDays: retentionDays, sku: { name: 'PerGB2018' } }
}
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    RetentionInDays: retentionDays
  }
}
```

**Outputs:**

| Name | Type | Description |
|---|---|---|
| `appInsightsConnectionString` | string | Connection string for Function App setting |
| `appInsightsInstrumentationKey` | string | Instrumentation key (legacy fallback) |
| `workspaceId` | string | Log Analytics Workspace resource ID |

**Environment differences:**

| Parameter | Dev | Staging | Prod |
|---|---|---|---|
| `retentionDays` | 30 | 60 | 90 |

---

### 5.5 `rbac.bicep` (`modules/rbac.bicep`)

**Purpose:** Assigns the `Storage Blob Data Contributor` built-in role to the Function App's system-assigned Managed Identity on the Storage Account scope.

**Parameters:**

| Name | Type | Description |
|---|---|---|
| `storageAccountId` | string | Resource ID of the storage account (role assignment scope) |
| `principalId` | string | Principal ID of the Function App system-assigned MI |

**Resources:**

```bicep
var storageBlobDataContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccountId, principalId, storageBlobDataContributorRoleId)
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', storageBlobDataContributorRoleId)
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
```

**Outputs:** None (role assignment has no useful outputs)

**Security requirements:**
- Scope to the specific Storage Account, not subscription or resource group — principle of least privilege
- `principalType: ServicePrincipal` to avoid delay in Entra ID propagation

**Environment differences:** None — same role required in all environments.

---

### 5.6 `staticWebApp.bicep` (`modules/staticWebApp.bicep`)

**Purpose:** Deploys the Azure Static Web Apps resource for hosting the photo gallery SPA.

**Parameters:**

| Name | Type | Allowed Values | Description |
|---|---|---|---|
| `staticWebAppName` | string | — | Globally unique Static Web App name |
| `location` | string | — | Region (must be one supporting SWA Free: `eastasia`, `eastus2`, `westus2`, `centralus`, `westeurope`, `eastus`, `australiaeast`) |
| `skuName` | string | `Free`, `Standard` | Free for dev/staging, Standard for prod if custom domain auth needed |
| `repositoryUrl` | string | — | GitHub repository URL for CI/CD integration |
| `branch` | string | — | Branch to deploy from (main for prod, staging for staging) |

**Resources:**

```bicep
resource staticWebApp 'Microsoft.Web/staticSites@2022-09-01' = {
  sku: { name: skuName, tier: skuName }
  properties: {
    repositoryUrl: repositoryUrl
    branch: branch
    buildProperties: {
      appLocation: '/'
      apiLocation: ''
      outputLocation: ''
    }
  }
}
```

**Outputs:**

| Name | Type | Description |
|---|---|---|
| `staticWebAppId` | string | Resource ID |
| `defaultHostname` | string | Default SWA hostname (used in CORS config of Function App and Storage) |
| `deploymentToken` | string | Secret deployment token (used in GitHub Actions secret `STATIC_WEB_APP_TOKEN`) |

**Security requirements:**
- `allowedCorsOrigins` in Function App and Storage must reference `defaultHostname` in prod
- SWA Free tier does not support private endpoints — acceptable for this workload

**Environment differences:**

| Parameter | Dev | Staging | Prod |
|---|---|---|---|
| `skuName` | Free | Free | Free (upgrade to Standard only if Entra auth needed) |
| `branch` | dev | staging | main |

---

## 6. Application Code Changes

All rewritten functions go into a single Python Function App in `outputs/azure-functions/function_app.py` (Azure Functions v2 Python programming model). Supporting shared utilities in `outputs/azure-functions/shared/blob_helpers.py`.

### 6.1 `upload_image` (replaces `UploadFunction`)

**Original file:** `source-app/app-code/lambda/upload/upload_handler.py`  
**Azure file:** `outputs/azure-functions/function_app.py` — function `upload_image`  
**Trigger type:** HTTP POST `/api/upload`

**SDK changes:**

| Old (boto3) | New (azure-sdk) | Package |
|---|---|---|
| `import boto3` | `from azure.storage.blob import BlobServiceClient, BlobSasPermissions, generate_blob_sas` | `azure-storage-blob>=12.19.0` |
| `import botocore` | `from azure.identity import DefaultAzureCredential` | `azure-identity>=1.15.0` |
| `boto3.client('s3')` | `BlobServiceClient(account_url=..., credential=DefaultAzureCredential())` | — |
| `s3.generate_presigned_post(Bucket, Key, ExpiresIn, Conditions)` | `generate_blob_sas(account_name, container, blob_name, account_key=None, credential=mi_credential, permission=BlobSasPermissions(write=True, create=True), expiry=datetime.utcnow()+timedelta(seconds=URL_EXPIRATION))` | — |
| `lambda_handler(event, context)` | `@app.route(route="upload", methods=["POST"]) async def upload_image(req: func.HttpRequest)` | `azure-functions>=1.18.0` |
| `event['body']` → `json.loads(body)` | `req.get_json()` | — |
| `event['pathParameters']` | `req.route_params` | — |
| `event['queryStringParameters']` | `req.params` | — |
| Return `{'statusCode': 200, 'body': json.dumps(...)}` | `return func.HttpResponse(json.dumps(...), status_code=200, mimetype='application/json')` | — |

**Environment variables:**

| Old Name | New Name | Source |
|---|---|---|
| `BUCKET_NAME` | `STORAGE_ACCOUNT_NAME` | Bicep app setting (storage account name) |
| — | `BLOB_CONTAINER_NAME` | Bicep app setting (default: `images`) |
| `URL_EXPIRATION` | `URL_EXPIRATION` | Bicep app setting (default: `3600`) |

**Auth pattern:** `DefaultAzureCredential()` resolves to System-assigned Managed Identity in Azure. Locally (`local.settings.json`) set `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, `AZURE_CLIENT_SECRET` for a service principal, or use `az login`.

**Key logic change:** AWS flow returns `url` + `fields` dict for multipart POST. Azure SAS returns a single PUT URL. SPA upload JavaScript must change from `FormData` POST to `fetch(sasUrl, {method:'PUT', headers:{'x-ms-blob-type':'BlockBlob'}, body:file})`.

**Configuration changes:**
- `requirements.txt`: add `azure-functions`, `azure-storage-blob`, `azure-identity`
- `host.json`: CORS `allowedOrigins` replaces per-function CORS in AWS

---

### 6.2 `list_images` (replaces `ListFilesFunction`)

**Original file:** `source-app/app-code/lambda/list/` (list_handler.py)  
**Azure file:** `outputs/azure-functions/function_app.py` — function `list_images`  
**Trigger type:** HTTP GET `/api/files`

**SDK changes:**

| Old (boto3) | New (azure-sdk) |
|---|---|
| `s3.list_objects_v2(Bucket, Prefix, MaxKeys)` | `container_client.list_blobs(name_starts_with=prefix, results_per_page=max_keys)` |
| `obj['Key']` | `blob.name` |
| `obj['Size']` | `blob.size` |
| `obj['LastModified']` | `blob.last_modified` |
| `s3.head_object(Bucket, Key)` to get metadata | `blob.metadata` dict directly from `list_blobs()` (if metadata=True) or `blob_client.get_blob_properties()` |
| `x-amz-meta-uploaddate` | `metadata['uploaddate']` |
| `x-amz-meta-originalfilename` | `metadata['originalfilename']` |
| `x-amz-meta-description` | `metadata['description']` |
| `s3.generate_presigned_url('get_object', ...)` | `generate_blob_sas(..., BlobSasPermissions(read=True))` + construct URL |
| Pagination via `ContinuationToken` | Pagination via `list_blobs()` iterator (no explicit token needed for simple cases) |

**Query parameters:** `prefix` and `maxKeys` (default 50) → `req.params.get('prefix', '')` and `req.params.get('maxKeys', '50')`.

---

### 6.3 `get_view_url` (replaces `GetViewUrlFunction`)

**Original file:** `source-app/app-code/lambda/view/` (view_handler.py)  
**Azure file:** `outputs/azure-functions/function_app.py` — function `get_view_url`  
**Trigger type:** HTTP GET `/api/files/{fileId}/view-url`

**SDK changes:**

| Old (boto3) | New (azure-sdk) |
|---|---|
| `s3.list_objects_v2(Bucket=BUCKET_NAME, Prefix=f"{file_id}/")` | `container_client.list_blobs(name_starts_with=f"{file_id}/")` |
| `s3.generate_presigned_url('get_object', Params={'Bucket': BUCKET_NAME, 'Key': key}, ExpiresIn=URL_EXPIRATION)` | `f"https://{account_name}.blob.core.windows.net/{container}/{blob_name}?{generate_blob_sas(account_name, container, blob_name, credential=..., permission=BlobSasPermissions(read=True), expiry=datetime.utcnow()+timedelta(seconds=URL_EXPIRATION))}"` |

**Route parameter:** `file_id = req.route_params.get('fileId')` replaces `event['pathParameters']['fileId']`.

---

### 6.4 `delete_image` (replaces `DeleteFileFunction`)

**Original file:** `source-app/app-code/lambda/delete/delete_handler.py`  
**Azure file:** `outputs/azure-functions/function_app.py` — function `delete_image`  
**Trigger type:** HTTP DELETE `/api/files/{fileId}`

**SDK changes:**

| Old (boto3) | New (azure-sdk) |
|---|---|
| `s3.list_objects_v2(Bucket=BUCKET_NAME, Prefix=f"{file_id}/")` | `container_client.list_blobs(name_starts_with=f"{file_id}/")` |
| `s3.delete_object(Bucket=BUCKET_NAME, Key=obj['Key'])` | `container_client.delete_blob(blob_name)` (per-blob loop; Azure SDK v12 has no batch delete by prefix) |
| `'Contents' not in response` | `list(blobs) == []` |

**Error handling:** 404 when blob list is empty (same logic as AWS). Azure `ResourceNotFoundError` on `delete_blob` should be caught and treated as already-deleted (idempotent).

---

### 6.5 Shared utility: `blob_helpers.py`

**File:** `outputs/azure-functions/shared/blob_helpers.py`  
**Purpose:** Centralises `BlobServiceClient` and `ContainerClient` construction using `DefaultAzureCredential`. Imported by all four functions. Avoids repeated client initialisation on every invocation.

```python
import os
from azure.storage.blob import BlobServiceClient, ContainerClient
from azure.identity import DefaultAzureCredential

_credential = DefaultAzureCredential()
_blob_service_client: BlobServiceClient | None = None

def get_container_client() -> ContainerClient:
    global _blob_service_client
    account_name = os.environ['STORAGE_ACCOUNT_NAME']
    container_name = os.environ.get('BLOB_CONTAINER_NAME', 'images')
    if _blob_service_client is None:
        account_url = f"https://{account_name}.blob.core.windows.net"
        _blob_service_client = BlobServiceClient(account_url=account_url, credential=_credential)
    return _blob_service_client.get_container_client(container_name)
```

---

### 6.6 `requirements.txt` additions

```
azure-functions>=1.18.0
azure-storage-blob>=12.19.0
azure-identity>=1.15.0
```

Remove: `boto3`, `botocore`

---

### 6.7 `host.json` changes

```json
{
  "version": "2.0",
  "extensions": {
    "http": {
      "routePrefix": "api"
    }
  },
  "logging": {
    "applicationInsights": {
      "samplingSettings": {
        "isEnabled": true,
        "maxTelemetryItemsPerSecond": 20
      }
    }
  },
  "functionTimeout": "00:00:30"
}
```

CORS is configured in the Function App resource in Bicep (`siteConfig.cors`), not in `host.json` for production. For local development, add to `local.settings.json`.

---

## 7. Environment Configuration

| Parameter | Dev | Staging | Prod |
|---|---|---|---|
| Resource Group | `rg-photo-gallery-dev` | `rg-photo-gallery-staging` | `rg-photo-gallery-prod` |
| Location | australiaeast | australiaeast | australiaeast |
| Function App name | `photo-gallery-func-dev` | `photo-gallery-func-staging` | `photo-gallery-func-prod` |
| Function App SKU | Y1 (Consumption) | Y1 (Consumption) | Y1 (Consumption) |
| Storage Account name | `photogallstordev` | `photogallstorstagng` | `photogallstoreprod` |
| Storage SKU | Standard_LRS | Standard_LRS | Standard_GRS |
| Blob versioning | false | false | true |
| CORS allowed origins | ['*'] | SWA staging hostname | SWA prod hostname |
| Log Analytics retention | 30 days | 60 days | 90 days |
| Static Web App SKU | Free | Free | Free |
| Static Web App branch | dev | staging | main |
| URL_EXPIRATION | 3600 | 3600 | 3600 |

---

## 8. Security Requirements

### Managed Identity assignments

| Identity | Type | Scope | Role | RBAC Role ID |
|---|---|---|---|---|
| Function App system-assigned MI | ServicePrincipal | Storage Account | Storage Blob Data Contributor | ba92f5b4-2d11-453d-a403-e96b0029c9fe |

### Key Vault secrets (prod only)
For production, the following values should be pre-populated in Azure Key Vault and referenced from Function App app settings via `@Microsoft.KeyVault(...)` syntax:

| Secret Name | Description | Consumer |
|---|---|---|
| `photo-gallery-appinsights-connstring` | Application Insights connection string | Function App `APPLICATIONINSIGHTS_CONNECTION_STRING` |

The storage account name is not a secret (it's a non-sensitive configuration value). The Function App accesses Blob Storage via MI, so no storage account keys are needed or stored.

### Network Security Group rules
No NSGs required — this is a fully serverless workload with no VNets. Services are accessed over public endpoints with authentication:
- Blob Storage: authenticated via MI token (no public blob access)
- Functions: authenticated via `x-functions-key` header (or Azure AD for prod upgrade)
- Static Web Apps: publicly accessible (it's a public SPA)

### Private Endpoints
Not required for this workload — Consumption plan Functions cannot use VNet integration without Premium plan. Cost justification: adding private endpoints would require Premium plan (~$150/month) for a workload with $1.60/month compute cost.

### Critical security fix: IAM user static key
The AWS IAM user `image-upload-api-user` with static access key `AKIAXZEFIIOD2OIWPRPK` is embedded in the SPA front-end. **This key must never be migrated to Azure.** The Azure replacement is:
1. SPA reads the Function App default key from a config value at deploy time
2. SPA passes `x-functions-key: <key>` header with every API request
3. In production, consider rotating to Azure AD MSAL-based auth (future enhancement)

### CORS
- Dev/Staging: `allowedOrigins: ['*']` for ease of testing
- Production: `allowedOrigins: ['https://<swa-prod-hostname>.azurestaticapps.net']`

### Blob public access
`allowBlobPublicAccess: false` on Storage Account. All blob access is via time-limited SAS tokens generated by the Function App's MI.

---

## 9. Deployment Order

The following sequence must be followed; steps 1–3 are prerequisites for step 4.

1. **Resource Group** — Create target resource group (e.g., `rg-photo-gallery-dev`) in `australiaeast`.
2. **Monitoring** — Deploy `monitoring.bicep` first; outputs `appInsightsConnectionString` needed by `functionApp.bicep`.
3. **Storage** — Deploy `storage.bicep`; outputs `storageAccountId` and `storageAccountName` needed by `functionApp.bicep` and `rbac.bicep`.
4. **Function App** — Deploy `functionApp.bicep` with monitoring and storage outputs as inputs; outputs `principalId` needed by `rbac.bicep`.
5. **RBAC** — Deploy `rbac.bicep` with `storageAccountId` (from step 3) and `principalId` (from step 4). **Must complete before any function invocation that touches Blob Storage.**
6. **Static Web App** — Deploy `staticWebApp.bicep`; outputs `defaultHostname` used to update CORS in Function App (may require a second pass on step 4 in prod if CORS origins must be tightened).
7. **Function App code** — Deploy Python code package to Function App via `az functionapp deployment source config-zip` or GitHub Actions.
8. **Static Web App content** — Deploy `index.html` (renamed from `app.html`) and update JavaScript config (API URL = `https://<func-hostname>/api`, auth header = `x-functions-key: <key>`).
9. **Smoke tests** — Run validation checklist (Section 10).

**Dependency graph:**
```
1 (RG) → 2 (Monitoring) → 4 (FunctionApp)
1 (RG) → 3 (Storage) → 4 (FunctionApp)
4 (FunctionApp) → 5 (RBAC)
5 (RBAC) → 7 (Function code deployment)
4 (FunctionApp) → 6 (SWA) [CORS hostname feedback loop for prod]
6 (SWA) → 8 (SWA content)
7 + 8 → 9 (Smoke tests)
```

---

## 10. Validation Checklist

The deployment-validation agent must run all checks after each environment deployment.

### Infrastructure checks
- [ ] Resource group `rg-photo-gallery-<env>` exists in australiaeast
- [ ] Storage account exists; blob versioning matches env config; `allowBlobPublicAccess=false`
- [ ] Container `images` exists with private access level
- [ ] Function App exists; runtime `python|3.11`; `httpsOnly=true`; identity type `SystemAssigned`
- [ ] Function App `principalId` is assigned `Storage Blob Data Contributor` on the storage account (verify via `az role assignment list`)
- [ ] Log Analytics Workspace and Application Insights exist and are linked
- [ ] Static Web App exists; deployment succeeded

### Functional smoke tests
- [ ] **Upload:** `POST /api/upload` with `x-functions-key` header returns HTTP 200 and a JSON body containing `sas_url` and `blob_name`
- [ ] **Direct upload:** PUT to the returned `sas_url` with a test PNG file (< 10 MB) returns HTTP 201
- [ ] **List:** `GET /api/files` returns HTTP 200 and JSON array containing at least the uploaded blob; metadata fields `originalfilename`, `uploaddate` are present
- [ ] **View URL:** `GET /api/files/{fileId}/view-url` returns HTTP 200 and a `view_url` that loads the image when opened in a browser (HTTP 200, Content-Type: image/*)
- [ ] **Delete:** `DELETE /api/files/{fileId}` returns HTTP 200; subsequent `GET /api/files/{fileId}/view-url` returns HTTP 404
- [ ] **CORS:** Browser pre-flight `OPTIONS /api/upload` from the SWA origin returns HTTP 200 with correct `Access-Control-Allow-Origin` header
- [ ] **SPA load:** Navigate to the Static Web App URL; `index.html` loads without console errors; gallery shows uploaded images

### Security checks
- [ ] No blob is accessible without a SAS token (direct URL without `?sv=...` query returns HTTP 403 or 404)
- [ ] Function App rejects requests without `x-functions-key` header with HTTP 401
- [ ] No AWS credentials (`AKIAXZEFIIOD2OIWPRPK` or any `AKIA*` pattern) present in Function App app settings or SPA JavaScript

### Monitoring checks
- [ ] Application Insights receives request telemetry after smoke tests
- [ ] Log Analytics Workspace shows function execution logs via KQL: `requests | where timestamp > ago(10m)`

---

## 11. CI/CD Pipeline Architecture

### 11.1 Pipeline Overview

| Workflow File | Trigger | Purpose | Target Azure Service |
|---|---|---|---|
| `.github/workflows/deploy-infra.yml` | Push to `main`/`staging`/`dev`; manual dispatch | Deploy Bicep IaC (storage, monitoring, function app, RBAC, SWA) | Azure Resource Manager (subscription/RG scope) |
| `.github/workflows/deploy-functions.yml` | Push to `main`/`staging`/`dev` (path: `outputs/azure-functions/**`); manual dispatch | Build Python package and deploy to Azure Functions | Azure Functions |
| `.github/workflows/deploy-static-web.yml` | Push to `main`/`staging`/`dev` (path: `source-app/app-code/build/**`); manual dispatch | Deploy SPA static files to Azure Static Web Apps | Azure Static Web Apps |

### 11.2 Authentication Strategy

**Method:** OIDC / Workload Identity Federation — no long-lived client secrets stored in GitHub.

**GitHub Secrets required:**

| Secret Name | Value Source | Used By |
|---|---|---|
| `AZURE_CLIENT_ID` | App registration Client ID (with federated credential) | All three workflows |
| `AZURE_TENANT_ID` | Azure AD tenant ID | All three workflows |
| `AZURE_SUBSCRIPTION_ID` | Target Azure subscription ID | `deploy-infra.yml`, `deploy-functions.yml` |
| `STATIC_WEB_APP_TOKEN_DEV` | SWA deployment token (dev) from `az staticwebapp secrets list` | `deploy-static-web.yml` (dev env) |
| `STATIC_WEB_APP_TOKEN_STAGING` | SWA deployment token (staging) | `deploy-static-web.yml` (staging env) |
| `STATIC_WEB_APP_TOKEN_PROD` | SWA deployment token (prod) | `deploy-static-web.yml` (prod env) |

**Federated credential subject filters** (configure on the app registration):
```
repo:<org>/<repo>:ref:refs/heads/main          (prod deployments)
repo:<org>/<repo>:ref:refs/heads/staging        (staging deployments)
repo:<org>/<repo>:ref:refs/heads/dev            (dev deployments)
repo:<org>/<repo>:environment:production        (if using GitHub Environments)
```

**RBAC roles required for the service principal (app registration):**

| Role | Scope | Purpose |
|---|---|---|
| `Contributor` | Resource Group (`rg-photo-gallery-<env>`) | Create/update all resources via Bicep |
| `Role Based Access Control Administrator` | Resource Group | Create role assignments (for MI → Storage RBAC in `rbac.bicep`) — restrict with `assignableScopes` condition to only `Storage Blob Data Contributor` |

> **Note:** If `Role Based Access Control Administrator` scope is too broad, use `User Access Administrator` with a condition: `@Resource[Microsoft.Storage/storageAccounts]:name StringLike 'photogallst*'`.

### 11.3 Per-Workflow Specification

#### 11.3.1 `.github/workflows/deploy-infra.yml`

**Trigger conditions:**
```yaml
on:
  push:
    branches: [main, staging, dev]
    paths:
      - 'outputs/bicep-templates/**'
  workflow_dispatch:
    inputs:
      environment:
        type: choice
        options: [dev, staging, prod]
        required: true
```

**Environment protection rules:** `prod` environment requires 1 required reviewer approval.

**Jobs and steps (in order):**

1. `checkout` — `actions/checkout@v4`
2. `azure-login` — `azure/login@v2` with `client-id`, `tenant-id`, `subscription-id` (OIDC; no secret)
3. `determine-env` — Shell step: derive environment name from branch (`main`→`prod`, `staging`→`staging`, `dev`→`dev`), set `ENV_NAME` output
4. `bicep-what-if` — `az deployment group what-if` with `--template-file outputs/bicep-templates/main.bicep --parameters outputs/bicep-templates/parameters/${{ ENV_NAME }}.bicepparam` — fail on error
5. `deploy-infra` — `az deployment group create --resource-group rg-photo-gallery-${{ ENV_NAME }} --template-file outputs/bicep-templates/main.bicep --parameters outputs/bicep-templates/parameters/${{ ENV_NAME }}.bicepparam --name deploy-${{ github.run_number }}`
6. `save-outputs` — Extract and echo deployment outputs: `functionAppName`, `storageAccountName`, `swaHostname`; save to step outputs for downstream workflows

**Bicep commands (exact flags):**
```bash
az deployment group create \
  --resource-group rg-photo-gallery-$ENV_NAME \
  --template-file outputs/bicep-templates/main.bicep \
  --parameters outputs/bicep-templates/parameters/$ENV_NAME.bicepparam \
  --name "infra-${{ github.run_number }}" \
  --rollback-on-error
```

**Rollback strategy:** `--rollback-on-error` flag on `az deployment group create` reverts the deployment to the last successful state if the deployment fails.

**Secrets and env vars:**
- `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` from GitHub Secrets
- `ENV_NAME` derived from branch name

**Artifact handling:** Deployment outputs (function app name, SWA hostname) written to `$GITHUB_OUTPUT` for use by downstream workflows via `workflow_run` event or manual chaining.

---

#### 11.3.2 `.github/workflows/deploy-functions.yml`

**Trigger conditions:**
```yaml
on:
  push:
    branches: [main, staging, dev]
    paths:
      - 'outputs/azure-functions/**'
  workflow_dispatch:
    inputs:
      environment: { type: choice, options: [dev, staging, prod], required: true }
      functionAppName: { type: string, required: true }
```

**Environment protection rules:** `prod` requires 1 required reviewer.

**Jobs and steps (in order):**

1. `checkout` — `actions/checkout@v4`
2. `setup-python` — `actions/setup-python@v5` with `python-version: '3.11'`
3. `install-deps` — `cd outputs/azure-functions && pip install -r requirements.txt --target .python_packages/lib/site-packages`
4. `package` — `cd outputs/azure-functions && zip -r ../function-app.zip . -x "*.git*" "__pycache__/*" "*.pyc" ".venv/*"`
5. `azure-login` — `azure/login@v2` (OIDC)
6. `determine-env` — Derive `ENV_NAME` and `FUNC_APP_NAME` from branch or input
7. `deploy-functions` — `az functionapp deployment source config-zip --resource-group rg-photo-gallery-$ENV_NAME --name $FUNC_APP_NAME --src function-app.zip`
8. `verify-deployment` — `az functionapp show --resource-group rg-photo-gallery-$ENV_NAME --name $FUNC_APP_NAME --query "state" -o tsv` — assert `Running`

**Rollback strategy:** Re-run previous successful workflow run manually; or use deployment slots (not available on Consumption plan) → fallback: redeploy previous known-good zip artifact from GitHub Actions artifact store.

**Artifact handling:** The `function-app.zip` is uploaded as a GitHub Actions artifact (`actions/upload-artifact@v4`) for 7-day retention to enable rollback.

---

#### 11.3.3 `.github/workflows/deploy-static-web.yml`

**Trigger conditions:**
```yaml
on:
  push:
    branches: [main, staging, dev]
    paths:
      - 'source-app/app-code/build/**'
      - 'source-app/app-code/examples/**'
  workflow_dispatch:
    inputs:
      environment: { type: choice, options: [dev, staging, prod], required: true }
```

**Environment protection rules:** `prod` requires 1 required reviewer.

**Jobs and steps (in order):**

1. `checkout` — `actions/checkout@v4`
2. `determine-env` — Derive `ENV_NAME` and `SWA_TOKEN_SECRET` name from branch
3. `rename-index` — `cp source-app/app-code/build/app.html source-app/app-code/build/index.html` (rename for SWA compatibility)
4. `patch-spa-config` — Shell: replace hardcoded AWS API URL and credentials in `index.html` with Azure Function App URL and key using `sed` or a JSON config injection script. **Critical: remove `AKIAXZEFIIOD2OIWPRPK` from any embedded config.**
5. `deploy-swa` — `azure/static-web-apps-deploy@v1` with `azure_static_web_apps_api_token: ${{ secrets[SWA_TOKEN_SECRET] }}`, `app_location: source-app/app-code/build`, `skip_app_build: true`

**Secrets and env vars:**
- `STATIC_WEB_APP_TOKEN_DEV` / `_STAGING` / `_PROD` from GitHub Secrets (env-specific)
- `AZURE_FUNCTIONS_URL` — constructed from env-specific function app hostname
- `AZURE_FUNCTIONS_KEY` — Function App default key; stored as GitHub Secret `FUNC_KEY_DEV` etc. (rotate via Key Vault reference in prod)

**Rollback strategy:** SWA supports staging environments and traffic splitting. A previous deployment can be promoted. For immediate rollback, trigger a re-deploy of the last known-good commit.

**Artifact handling:** No build artifacts (HTML/JS is not compiled). Source is deployed directly.

---

### 11.4 Multi-Environment Strategy

| Aspect | Dev | Staging | Prod |
|---|---|---|---|
| Git branch | `dev` | `staging` | `main` |
| GitHub Environment | `dev` | `staging` | `production` |
| Approval required | None | None | 1 reviewer |
| Resource group | `rg-photo-gallery-dev` | `rg-photo-gallery-staging` | `rg-photo-gallery-prod` |
| Bicep params file | `dev.bicepparam` | `staging.bicepparam` | `prod.bicepparam` |
| SWA token secret | `STATIC_WEB_APP_TOKEN_DEV` | `STATIC_WEB_APP_TOKEN_STAGING` | `STATIC_WEB_APP_TOKEN_PROD` |
| Functions key secret | `FUNC_KEY_DEV` | `FUNC_KEY_STAGING` | `FUNC_KEY_PROD` |

**Branch/tag strategy:** Feature branches merge to `dev` (auto-deploy to dev). `dev` merges to `staging` via PR (auto-deploy to staging). `staging` merges to `main` via PR with required review (auto-deploy to prod after approval gate).

**Environment secrets separation:** GitHub Environments (`dev`, `staging`, `production`) hold environment-specific secrets. The `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` are stored at repository level (shared across environments since all environments are in the same subscription). SWA tokens and function keys are environment-scoped.

### 11.5 Pipeline Dependency Order

1. **`deploy-infra.yml`** must succeed first — it provisions all Azure resources including Function App and Static Web App.
2. **`deploy-functions.yml`** runs after `deploy-infra.yml` — Function App must exist before code can be deployed.
3. **`deploy-static-web.yml`** runs after `deploy-infra.yml` (SWA must exist) and after `deploy-functions.yml` (SPA config must reference the live Function App URL and key).

**In a single pipeline run (manual full deploy):** trigger `deploy-infra.yml` → on success trigger `deploy-functions.yml` → on success trigger `deploy-static-web.yml`. In the GitHub Actions `workflow_dispatch` model, use `workflow_run` events or a single composite workflow that calls all three as jobs with `needs:` dependencies.

---

## Open Questions / Gaps

1. **Custom domain:** No custom domain was specified. SWA provides a `*.azurestaticapps.net` URL and Functions provides `*.azurewebsites.net`. If a custom domain is required, add DNS configuration to `staticWebApp.bicep` and update CORS.
2. **Authentication upgrade (prod):** Current plan replaces SigV4 + static key with `x-functions-key`. For user-facing production workloads, Azure AD B2C or Entra External ID is recommended to provide per-user identity. This is a future enhancement outside the current migration scope.
3. **Blob lifecycle policy:** The source S3 bucket had no lifecycle policies. Azure lifecycle management is not configured in the initial migration. If cost savings on old images are desired post-migration, add a lifecycle policy to move blobs to Cool tier after 30 days.
4. **GitHub repository URL:** `staticWebApp.bicep` requires the GitHub repository URL and branch for CI/CD integration. The actual URL is unknown at design time — substitute `https://github.com/<org>/<repo>` at deployment time.
