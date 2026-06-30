// ── modules/monitoring.bicep ────────────────────────────────────────────────
// Purpose: Log Analytics Workspace + Application Insights.
//          Application Insights is linked to the workspace (workspace-based).
//
// AVM modules:
//   br/public:avm/res/operational-insights/workspace:0.15.0
//   br/public:avm/res/insights/component:0.7.1

@allowed(['dev', 'staging', 'prod'])
@description('Deployment environment.')
param environment string

@description('Workload short name, e.g. imageupload.')
param workload string

@description('Azure region, e.g. australiaeast.')
param location string

@description('Resource tags applied to all resources.')
param tags object

@minValue(30)
@maxValue(730)
@description('Log retention in days. 30 for dev, 60 for staging, 90 for prod.')
param retentionDays int = 30

// ── Variables ───────────────────────────────────────────────────────────────
var workspaceName = '${environment}-${workload}-law-${location}'
var appInsightsName = '${environment}-${workload}-appi-${location}'

// ── AVM Log Analytics Workspace ─────────────────────────────────────────────
module logAnalyticsWorkspace 'br/public:avm/res/operational-insights/workspace:0.15.0' = {
  name: 'logAnalyticsWorkspaceDeploy'
  params: {
    name: workspaceName
    location: location
    tags: tags
    skuName: 'PerGB2018'
    dataRetention: retentionDays
  }
}

// ── AVM Application Insights ─────────────────────────────────────────────────
module appInsights 'br/public:avm/res/insights/component:0.7.1' = {
  name: 'appInsightsDeploy'
  params: {
    name: appInsightsName
    location: location
    tags: tags
    workspaceResourceId: logAnalyticsWorkspace.outputs.resourceId
    kind: 'web'
    applicationType: 'web'
  }
}

// ── Outputs ─────────────────────────────────────────────────────────────────
@description('Application Insights resource ID.')
output resourceId string = appInsights.outputs.resourceId

@description('Application Insights resource name.')
output resourceName string = appInsights.outputs.name

@description('Application Insights connection string.')
output connectionString string = appInsights.outputs.connectionString

@description('Log Analytics Workspace resource ID.')
output workspaceId string = logAnalyticsWorkspace.outputs.resourceId
