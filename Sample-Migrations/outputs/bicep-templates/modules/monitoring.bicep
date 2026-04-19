// =============================================================================
// monitoring.bicep — Monitoring Module
// Deploys Log Analytics Workspace and Application Insights
// Must deploy first — appInsightsConnectionString consumed by functions module
// AWS equivalent: Amazon CloudWatch Logs + CloudWatch Metrics + X-Ray
// Design doc: Section 5.2
// =============================================================================

metadata name = 'Monitoring Module'
metadata description = 'Deploys Log Analytics Workspace and Application Insights for the Image Upload Service'

@description('Azure region for all resources.')
param location string

@description('Environment name (dev, staging, prod).')
@allowed(['dev', 'staging', 'prod'])
param environment string

@description('Resource name prefix used for all resources in this module (e.g. img-upload-dev).')
param resourceNamePrefix string

@description('Number of days to retain log data. Dev: 30, staging: 60, prod: 90.')
@minValue(7)
@maxValue(730)
param logRetentionDays int = 30

// =============================================================================
// Log Analytics Workspace — replaces CloudWatch Log Groups
// =============================================================================
module logAnalyticsWorkspace 'br/public:avm/res/operational-insights/workspace:0.15.0' = {
  name: 'logAnalyticsWorkspaceDeploy'
  params: {
    name: '${resourceNamePrefix}-law'
    location: location
    skuName: 'PerGB2018'
    dataRetention: logRetentionDays
    tags: {
      environment: environment
      application: 'image-upload-service'
      'aws-equivalent': 'cloudwatch-log-groups'
    }
  }
}

// =============================================================================
// Application Insights — replaces CloudWatch Metrics + X-Ray
// Workspace-based (preferred) for advanced KQL querying and retention control
// Resource named ${resourceNamePrefix}-ai to match architecture diagram
// =============================================================================
module appInsights 'br/public:avm/res/insights/component:0.7.1' = {
  name: 'appInsightsDeploy'
  params: {
    name: '${resourceNamePrefix}-ai'
    location: location
    workspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
    kind: 'web'
    applicationType: 'web'
    disableIpMasking: false
    tags: {
      environment: environment
      application: 'image-upload-service'
      'aws-equivalent': 'cloudwatch-metrics-xray'
    }
  }
}

// =============================================================================
// Outputs
// =============================================================================

@description('Resource ID of the Log Analytics Workspace.')
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.outputs.resourceId

@description('Resource ID of Application Insights (used by APIM logger).')
output appInsightsResourceId string = appInsights.outputs.resourceId

@description('Application Insights instrumentation key (used by APIM logger).')
output appInsightsInstrumentationKey string = appInsights.outputs.instrumentationKey

@description('Application Insights connection string — set as APPLICATIONINSIGHTS_CONNECTION_STRING app setting.')
output appInsightsConnectionString string = appInsights.outputs.connectionString

@description('Application Insights resource name.')
output appInsightsName string = appInsights.outputs.name
