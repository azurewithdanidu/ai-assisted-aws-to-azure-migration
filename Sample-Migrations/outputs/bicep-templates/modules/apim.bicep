// =============================================================================
// apim.bicep — API Management Module
// Deploys Azure API Management (Consumption tier) replacing AWS API Gateway
// Mirrors: 4 routes (POST /upload, GET /files, GET /files/{fileId}/view-url,
//          DELETE /files/{fileId}), CORS policy, subscription key authentication
// Auth change: AWS_IAM (SigV4) → Subscription key (header: Ocp-Apim-Subscription-Key)
// Design doc: Section 5.7
//
// Security:
//   Subscription key required on all API operations
//   TLS 1.0 and 1.1 disabled (TLS 1.2 enforced)
//   CORS policy replaces 4 OPTIONS mock integrations from API Gateway
//   Do NOT embed subscription key in client-side source — store in Key Vault
// =============================================================================

metadata name = 'API Management Module'
metadata description = 'Deploys Azure API Management Consumption tier (replaces AWS API Gateway REST API)'

@description('Azure region for all resources.')
param location string

@description('Environment name (dev, staging, prod).')
@allowed(['dev', 'staging', 'prod'])
param environment string

@description('Resource name prefix used for all resources in this module (e.g. img-upload-dev).')
param resourceNamePrefix string

@description('Hostname of the Function App backend (without https://). From functions module output.')
param functionAppHostname string

@description('Publisher email address required for APIM service creation.')
param publisherEmail string

@description('Publisher organization name.')
param publisherName string

@description('Application Insights resource ID for APIM diagnostics logger (optional).')
param appInsightsResourceId string = ''

@description('Application Insights instrumentation key for APIM logger (optional).')
param appInsightsInstrumentationKey string = ''

// =============================================================================
// APIM Service — Consumption tier (pay-per-call, no infrastructure overhead)
// Replaces: AWS API Gateway Regional REST API (image-upload-api)
// Capacity 0 = Consumption tier (unlike Standard/Premium which set capacity > 0)
// =============================================================================
resource apimService 'Microsoft.ApiManagement/service@2023-05-01-preview' = {
  name: '${resourceNamePrefix}-apim'
  location: location
  sku: {
    name: 'Consumption'
    capacity: 0
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    customProperties: {
      // Disable legacy TLS protocols — enforce TLS 1.2 minimum
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'false'
    }
  }
  tags: {
    environment: environment
    application: 'image-upload-service'
    'aws-equivalent': 'api-gateway-image-upload-api'
  }
}

// =============================================================================
// Application Insights Logger (optional — created when appInsightsResourceId provided)
// Replaces: AWS X-Ray + CloudWatch API Gateway access logs
// =============================================================================
resource apimLogger 'Microsoft.ApiManagement/service/loggers@2023-05-01-preview' = if (appInsightsResourceId != '') {
  parent: apimService
  name: 'app-insights-logger'
  properties: {
    loggerType: 'applicationInsights'
    description: 'Application Insights logger for APIM request telemetry'
    credentials: {
      instrumentationKey: appInsightsInstrumentationKey
    }
    isBuffered: true
    resourceId: appInsightsResourceId
  }
}

// =============================================================================
// Named Value — Function App base URL for backend routing
// =============================================================================
resource functionBackendUrl 'Microsoft.ApiManagement/service/namedValues@2023-05-01-preview' = {
  parent: apimService
  name: 'function-app-base-url'
  properties: {
    displayName: 'function-app-base-url'
    value: 'https://${functionAppHostname}'
    secret: false
  }
}

// =============================================================================
// Backend — Azure Functions app as APIM backend
// Replaces: AWS Lambda integration in API Gateway (Lambda proxy)
// All 4 API operations forward to this backend via set-backend-service policy
// =============================================================================
resource functionBackend 'Microsoft.ApiManagement/service/backends@2023-05-01-preview' = {
  parent: apimService
  name: 'image-upload-function-backend'
  properties: {
    description: 'Azure Functions backend for Image Upload Service'
    // Functions v2 default route prefix is /api/ — matches @app.route() decorators
    url: 'https://${functionAppHostname}/api'
    protocol: 'http'
    tls: {
      validateCertificateChain: true
      validateCertificateName: true
    }
  }
  dependsOn: [functionBackendUrl]
}

// =============================================================================
// Image Upload API — replaces AWS API Gateway image-upload-api
// 4 operations mirror CloudFormation API Gateway resource definitions
// subscriptionRequired: true — all requests need Ocp-Apim-Subscription-Key header
// =============================================================================
resource imageUploadApi 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  parent: apimService
  name: 'image-upload-api'
  properties: {
    displayName: 'Image Upload API'
    description: 'API for the Image Upload Service — migrated from AWS API Gateway (image-upload-api)'
    subscriptionRequired: true
    subscriptionKeyParameterNames: {
      // Replaces: AWS_IAM SigV4 auth; client sends this header instead
      header: 'Ocp-Apim-Subscription-Key'
      query: 'subscription-key'
    }
    path: ''
    protocols: ['https']
    serviceUrl: 'https://${functionAppHostname}/api'
    apiType: 'http'
    isCurrent: true
  }
}

// =============================================================================
// API-level CORS + backend routing policy
// Replaces: 4 OPTIONS mock integrations from AWS API Gateway (one per route)
// Single APIM policy covers all routes — simpler and more maintainable
// CORS wildcard acceptable for demo; restrict to SWA hostname in prod
// =============================================================================
resource imageUploadApiPolicy 'Microsoft.ApiManagement/service/apis/policies@2023-05-01-preview' = {
  parent: imageUploadApi
  name: 'policy'
  properties: {
    format: 'xml'
    value: '''
<policies>
  <inbound>
    <base />
    <cors allow-credentials="false">
      <allowed-origins>
        <origin>*</origin>
        <!-- Production: restrict to Static Web Apps hostname -->
        <!-- <origin>https://img-upload-prod-swa.azurestaticapps.net</origin> -->
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
    <set-backend-service backend-id="image-upload-function-backend" />
  </inbound>
  <backend>
    <base />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
'''
  }
  dependsOn: [functionBackend]
}

// =============================================================================
// Operation: POST /upload
// Replaces: AWS API Gateway POST /upload → Lambda UploadFunction
// Function: upload_image() — generates SAS write URL for new image upload
// =============================================================================
resource uploadOperation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: imageUploadApi
  name: 'post-upload'
  properties: {
    displayName: 'Generate Upload URL'
    description: 'Generates a SAS write URL for a new image (replaces AWS S3 presigned POST URL)'
    method: 'POST'
    urlTemplate: '/upload'
    request: {
      description: 'Upload request body with filename and content type'
      headers: []
      queryParameters: []
      representations: [
        {
          contentType: 'application/json'
        }
      ]
    }
    responses: [
      {
        statusCode: 200
        description: 'SAS upload URL — client should PUT directly to this URL with file bytes'
        headers: []
        representations: [
          {
            contentType: 'application/json'
          }
        ]
      }
    ]
  }
}

// =============================================================================
// Operation: GET /files
// Replaces: AWS API Gateway GET /files → Lambda ListFilesFunction
// Function: list_files() — lists blobs with SAS read URLs
// =============================================================================
resource listFilesOperation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: imageUploadApi
  name: 'get-files'
  properties: {
    displayName: 'List Files'
    description: 'Lists all uploaded images with SAS read URLs (replaces AWS S3 ListBucket via Lambda)'
    method: 'GET'
    urlTemplate: '/files'
    request: {
      headers: []
      queryParameters: [
        {
          name: 'prefix'
          description: 'Optional blob name prefix filter'
          type: 'string'
          required: false
        }
        {
          name: 'maxKeys'
          description: 'Maximum number of results to return (default: 50)'
          type: 'integer'
          required: false
        }
      ]
      representations: []
    }
    responses: [
      {
        statusCode: 200
        description: 'List of image files with metadata and SAS read URLs'
        headers: []
        representations: [
          {
            contentType: 'application/json'
          }
        ]
      }
    ]
  }
}

// =============================================================================
// Operation: GET /files/{fileId}/view-url
// Replaces: AWS API Gateway GET /files/{fileId}/view-url → Lambda GetViewUrlFunction
// Function: get_view_url() — generates SAS read URL for specific image
// =============================================================================
resource getViewUrlOperation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: imageUploadApi
  name: 'get-files-fileid-view-url'
  properties: {
    displayName: 'Get View URL'
    description: 'Generates a time-limited SAS read URL for viewing an image (replaces AWS S3 presigned GET URL)'
    method: 'GET'
    urlTemplate: '/files/{fileId}/view-url'
    templateParameters: [
      {
        name: 'fileId'
        description: 'Blob name / file identifier (e.g. uuid/filename.jpg)'
        type: 'string'
        required: true
      }
    ]
    request: {
      headers: []
      queryParameters: []
      representations: []
    }
    responses: [
      {
        statusCode: 200
        description: 'SAS view URL valid for URL_EXPIRATION seconds (default 3600)'
        headers: []
        representations: [
          {
            contentType: 'application/json'
          }
        ]
      }
      {
        statusCode: 404
        description: 'File not found'
        headers: []
        representations: []
      }
    ]
  }
}

// =============================================================================
// Operation: DELETE /files/{fileId}
// Replaces: AWS API Gateway DELETE /files/{fileId} → Lambda DeleteFileFunction
// Function: delete_file() — deletes image blob by prefix
// =============================================================================
resource deleteFileOperation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: imageUploadApi
  name: 'delete-files-fileid'
  properties: {
    displayName: 'Delete File'
    description: 'Deletes an image from Blob Storage (replaces AWS S3 DeleteObject via Lambda)'
    method: 'DELETE'
    urlTemplate: '/files/{fileId}'
    templateParameters: [
      {
        name: 'fileId'
        description: 'Blob name / file identifier to delete'
        type: 'string'
        required: true
      }
    ]
    request: {
      headers: []
      queryParameters: []
      representations: []
    }
    responses: [
      {
        statusCode: 200
        description: 'File deleted successfully'
        headers: []
        representations: []
      }
      {
        statusCode: 404
        description: 'File not found'
        headers: []
        representations: []
      }
    ]
  }
}

// =============================================================================
// APIM Subscription — grants API access using subscription key
// Replaces: AWS IAM ApiUser + access key AKIAXZEFIIOD2OIWPRPK
// Key: auto-generated; copy primary key to Key Vault secret
//      'apim-subscription-primary-key' post-deployment
// =============================================================================
resource apimSubscription 'Microsoft.ApiManagement/service/subscriptions@2023-05-01-preview' = {
  parent: apimService
  name: 'image-upload-subscription'
  properties: {
    displayName: 'Image Upload Service Subscription'
    scope: imageUploadApi.id
    state: 'active'
    allowTracing: false
  }
}

// =============================================================================
// Outputs
// =============================================================================

@description('APIM gateway URL (public API endpoint) — update frontend APIM_BASE_URL with this value.')
output apimGatewayUrl string = apimService.properties.gatewayUrl

@description('Name of the APIM service.')
output apimServiceName string = apimService.name

@description('Name of the Key Vault secret where the APIM subscription key should be stored post-deployment.')
output apimSubscriptionKeySecretName string = 'apim-subscription-primary-key'

@description('Resource ID of the APIM service.')
output apimServiceId string = apimService.id

@description('Principal ID of the APIM system-assigned managed identity.')
output apimPrincipalId string = apimService.identity.principalId
