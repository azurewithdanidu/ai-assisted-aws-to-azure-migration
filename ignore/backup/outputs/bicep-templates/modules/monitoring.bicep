// ============================================================
// modules/monitoring.bicep
// Creates a workspace-based Log Analytics workspace and
// Application Insights component.
//
// AVM modules used (per module-organization skill):
//   - avm/res/operational-insights/workspace:0.15.0
//   - avm/res/insights/component:0.7.1
//
// Outputs: workspaceId, workspaceResourceId,
//          appInsightsConnectionString, appInsightsInstrumentationKey
// ============================================================

// ── Parameters ───────────────────────────────────────────────────────────────

@description('Name of the Log Analytics workspace.')
param workspaceName string

@description('Name of the Application Insights component.')
param appInsightsName string

@description('Azure region for all resources in this module.')
param location string

@description('Log data retention period in days.')
@minValue(30)
@maxValue(730)
param logRetentionDays int = 30

@description('Daily ingestion cap in GB. Recommended for dev to control costs.')
@minValue(1)
@maxValue(500)
param dailyCapGb int = 1

@description('Resource tags.')
param tags object = {}

// ─────────────────────────────────────────────────────────────────────────────
// RESOURCES
// ─────────────────────────────────────────────────────────────────────────────

// Log Analytics Workspace
// AVM: avm/res/operational-insights/workspace:0.15.0
module workspace 'br/public:avm/res/operational-insights/workspace:0.15.0' = {
  name: 'workspaceAvmDeploy'
  params: {
    name: workspaceName
    location: location
    skuName: 'PerGB2018'
    dataRetention: logRetentionDays
    dailyQuotaGb: string(dailyCapGb)
    tags: tags
  }
}

// Application Insights (workspace-based)
// AVM: avm/res/insights/component:0.7.1
module appInsights 'br/public:avm/res/insights/component:0.7.1' = {
  name: 'appInsightsAvmDeploy'
  params: {
    name: appInsightsName
    location: location
    workspaceResourceId: workspace.outputs.resourceId
    kind: 'web'
    applicationType: 'web'
    tags: tags
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OUTPUTS
// ─────────────────────────────────────────────────────────────────────────────

@description('Log Analytics workspace ARM resource ID.')
output workspaceId string = workspace.outputs.resourceId

@description('Log Analytics workspace resource ID (alias for downstream module use).')
output workspaceResourceId string = workspace.outputs.resourceId

@description('Application Insights connection string for app settings injection.')
output appInsightsConnectionString string = appInsights.outputs.connectionString

@description('Application Insights instrumentation key (legacy — prefer connection string).')
output appInsightsInstrumentationKey string = appInsights.outputs.instrumentationKey
