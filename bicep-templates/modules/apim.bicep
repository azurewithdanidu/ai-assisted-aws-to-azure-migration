// =============================================================================
// apim.bicep — API Management Module
// Deploys Azure API Management (Consumption tier) replacing AWS API Gateway
// Mirrors: 4 routes (POST /upload, GET /files, GET /files/{fileId}/view-url,
//          DELETE /files/{fileId}), CORS policy, App Insights logging
// Auth change: AWS_IAM (SigV4) → Subscription key (header: Ocp-Apim-Subscription-Key)
// TLS upgrade: TLS 1.0 → TLS 1.2 (enforced by default in APIM)
// =============================================================================

metadata name = 'API Management Module'
metadata description = 'Deploys Azure API Management Consumption tier (replaces AWS API Gateway REST API)'

@description('Azure region for all resources.')
param location string

@description('Environment name (dev, staging, prod).')
@allowed(['dev', 'staging', 'prod'])
param environment string

@description('Resource name prefix used for all resources in this module.')
param resourceNamePrefix string

@description('Publisher email address required for APIM service creation.')
param publisherEmail string

@description('Publisher organization name.')
param publisherName string

@description('Hostname of the Function App backend (without https://).')
param functionAppHostname string

@description('Application Insights resource ID for APIM diagnostics.')
param appInsightsId string

@description('Application Insights instrumentation key for APIM logger.')
param appInsightsInstrumentationKey string

// =============================================================================
// APIM Service — Consumption tier (pay-per-call, no infrastructure overhead)
// Replaces AWS API Gateway Regional REST API (4lrh2l7i86)
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
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Protocols.Tls11': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls10': 'false'
      'Microsoft.WindowsAzure.ApiManagement.Gateway.Security.Backend.Protocols.Tls11': 'false'
    }
  }
  tags: {
    environment: environment
    application: 'image-upload-service'
    'aws-equivalent': 'api-gateway-image-upload-api-4lrh2l7i86'
  }
}

// =============================================================================
// Application Insights Logger — replaces AWS X-Ray + CloudWatch API logging
// =============================================================================
resource apimLogger 'Microsoft.ApiManagement/service/loggers@2023-05-01-preview' = {
  parent: apimService
  name: 'app-insights-logger'
  properties: {
    loggerType: 'applicationInsights'
    description: 'Application Insights logger for APIM telemetry'
    credentials: {
      instrumentationKey: appInsightsInstrumentationKey
    }
    isBuffered: true
    resourceId: appInsightsId
  }
}

// =============================================================================
// APIM Diagnostics — send all API requests to App Insights
// =============================================================================
resource apimDiagnostics 'Microsoft.ApiManagement/service/diagnostics@2023-05-01-preview' = {
  parent: apimService
  name: 'applicationinsights'
  properties: {
    alwaysLog: 'allErrors'
    httpCorrelationProtocol: 'W3C'
    verbosity: 'information'
    logClientIp: true
    loggerId: apimLogger.id
    sampling: {
      samplingType: 'fixed'
      percentage: 100
    }
    frontend: {
      request: {
        headers: []
        body: {
          bytes: 0
        }
      }
      response: {
        headers: []
        body: {
          bytes: 0
        }
      }
    }
    backend: {
      request: {
        headers: []
        body: {
          bytes: 0
        }
      }
      response: {
        headers: []
        body: {
          bytes: 0
        }
      }
    }
  }
}

// =============================================================================
// Named Value — Function App base URL (used in backend operations)
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
// Replaces AWS Lambda integration in API Gateway
// =============================================================================
resource functionBackend 'Microsoft.ApiManagement/service/backends@2023-05-01-preview' = {
  parent: apimService
  name: 'image-upload-function-backend'
  properties: {
    description: 'Azure Functions backend for Image Upload Service'
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
// 4 routes mirror CloudFormation API Gateway resource definitions
// =============================================================================
resource imageUploadApi 'Microsoft.ApiManagement/service/apis@2023-05-01-preview' = {
  parent: apimService
  name: 'image-upload-api'
  properties: {
    displayName: 'Image Upload API'
    description: 'API for the Image Upload Service — migrated from AWS API Gateway (4lrh2l7i86)'
    subscriptionRequired: true
    subscriptionKeyParameterNames: {
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
// API-level CORS Policy
// Replaces AWS Lambda OPTIONS mock methods (one per route)
// Single policy covers all routes — simpler and more maintainable
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
        <!-- Production: restrict to SWA origin -->
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
// Replaces: AWS UploadMethod (POST /upload) → Lambda UploadFunction
// =============================================================================
resource uploadOperation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: imageUploadApi
  name: 'post-upload'
  properties: {
    displayName: 'Generate Upload URL'
    description: 'Generates a SAS upload URL for a new image (replaces AWS presigned PUT URL)'
    method: 'POST'
    urlTemplate: '/upload'
    request: {
      description: 'Upload request with filename and content type'
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
        description: 'SAS upload URL generated successfully'
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
// Replaces: AWS ListFilesMethod (GET /files) → Lambda ListFilesFunction
// =============================================================================
resource listFilesOperation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: imageUploadApi
  name: 'get-files'
  properties: {
    displayName: 'List Files'
    description: 'Lists all uploaded images (replaces AWS S3 ListBucket via Lambda)'
    method: 'GET'
    urlTemplate: '/files'
    request: {
      headers: []
      queryParameters: [
        {
          name: 'prefix'
          description: 'Optional prefix filter for blob names'
          type: 'string'
          required: false
        }
      ]
      representations: []
    }
    responses: [
      {
        statusCode: 200
        description: 'List of image files'
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
// Replaces: AWS GetViewUrlMethod (GET /files/{fileId}/view-url) → Lambda GetViewUrlFunction
// =============================================================================
resource getViewUrlOperation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: imageUploadApi
  name: 'get-files-fileid-view-url'
  properties: {
    displayName: 'Get View URL'
    description: 'Generates a time-limited SAS read URL for viewing an image (replaces AWS presigned GET URL)'
    method: 'GET'
    urlTemplate: '/files/{fileId}/view-url'
    templateParameters: [
      {
        name: 'fileId'
        description: 'Blob name / file identifier'
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
        description: 'SAS view URL valid for URL_EXPIRATION_SECONDS (default 3600s)'
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
// Operation: DELETE /files/{fileId}
// Replaces: AWS DeleteFileMethod (DELETE /files/{fileId}) → Lambda DeleteFileFunction
// =============================================================================
resource deleteFileOperation 'Microsoft.ApiManagement/service/apis/operations@2023-05-01-preview' = {
  parent: imageUploadApi
  name: 'delete-files-fileid'
  properties: {
    displayName: 'Delete File'
    description: 'Deletes an image file from Blob Storage (replaces AWS S3 DeleteObject via Lambda)'
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
    ]
  }
}

// =============================================================================
// APIM Subscription — grants access using subscription key
// Replaces AWS IAM ApiUser + AccessKey for API invocation
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

@description('Resource ID of the APIM service.')
output apimServiceId string = apimService.id

@description('Name of the APIM service.')
output apimServiceName string = apimService.name

@description('Gateway URL of the APIM service (public API endpoint).')
output apimGatewayUrl string = apimService.properties.gatewayUrl

@description('Principal ID of the APIM system-assigned managed identity.')
output apimPrincipalId string = apimService.identity.principalId
