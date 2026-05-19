// =============================================================================
// modules/monitoring.bicep
// Purpose: Deploy Log Analytics Workspace + Application Insights instance
//   linked to the Function App for telemetry, logs, and distributed tracing.
//   Replaces: CloudWatch Logs + CloudWatch Metrics (3× log groups)
// AVM modules:
//   br/public:avm/res/operational-insights/workspace:0.15.0  — Log Analytics Workspace
//   br/public:avm/res/insights/component:0.7.1               — Application Insights
//   Selected per SKILLS.MD §Step 3 — Monitoring (CloudWatch → App Insights + Log Analytics)
// =============================================================================

@description('Log Analytics Workspace name.')
param workspaceName string

@description('Application Insights resource name.')
param appInsightsName string

@description('Azure region for deployment.')
param location string

@description('Log retention in days. Dev=30, staging=60, prod=90.')
@minValue(30)
@maxValue(730)
param retentionDays int = 30

// ---------------------------------------------------------------------------
// Log Analytics Workspace
// ---------------------------------------------------------------------------
module logAnalyticsWorkspaceAvmDeploy 'br/public:avm/res/operational-insights/workspace:0.15.0' = {
  name: 'logAnalyticsWorkspaceAvmDeploy'
  params: {
    name: workspaceName
    location: location
    skuName: 'PerGB2018'
    dataRetention: retentionDays
  }
}

// ---------------------------------------------------------------------------
// Application Insights (workspace-based, linked to Log Analytics)
// ---------------------------------------------------------------------------
module appInsightsAvmDeploy 'br/public:avm/res/insights/component:0.7.1' = {
  name: 'appInsightsAvmDeploy'
  params: {
    name: appInsightsName
    location: location
    workspaceResourceId: logAnalyticsWorkspaceAvmDeploy.outputs.resourceId
    applicationType: 'web'
    kind: 'web'
    retentionInDays: retentionDays
  }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------

@description('Application Insights connection string. Set as APPLICATIONINSIGHTS_CONNECTION_STRING in Function App settings.')
output appInsightsConnectionString string = appInsightsAvmDeploy.outputs.connectionString

@description('Application Insights instrumentation key (legacy fallback).')
output appInsightsInstrumentationKey string = appInsightsAvmDeploy.outputs.instrumentationKey

@description('Log Analytics Workspace resource ID.')
output workspaceId string = logAnalyticsWorkspaceAvmDeploy.outputs.resourceId

@description('Application Insights resource ID.')
output appInsightsId string = appInsightsAvmDeploy.outputs.resourceId
