// ── modules/static-web-app.bicep ────────────────────────────────────────────
// Purpose: Azure Static Web Apps — hosts app.html frontend.
//          Replaces the public S3 website bucket.
//
// AVM module: br/public:avm/res/web/static-site:0.9.3

@allowed(['dev', 'staging', 'prod'])
@description('Deployment environment.')
param environment string

@description('Workload short name, e.g. imageupload.')
param workload string

@description('Azure region, e.g. australiaeast.')
param location string

@description('Resource tags applied to all resources.')
param tags object

@description('GitHub repository URL for built-in CI/CD, e.g. https://github.com/org/repo.')
param repositoryUrl string = ''

@description('Git branch to deploy from. dev → dev, staging → staging, prod → main.')
param branch string = 'main'

@description('Relative path to application source code within the repository.')
param appLocation string = 'source-app/app-code/build'

@description('Relative path to build output folder.')
param outputLocation string = ''

@allowed(['Free', 'Standard'])
@description('Static Web Apps pricing tier. Free for dev/staging, Standard for prod.')
param staticWebAppSku string = 'Free'

// ── Variables ───────────────────────────────────────────────────────────────
var staticSiteName = '${environment}-${workload}-swa-${location}'

// ── AVM Static Web App ───────────────────────────────────────────────────────
module staticSite 'br/public:avm/res/web/static-site:0.9.3' = {
  name: 'staticSiteDeploy'
  params: {
    name: staticSiteName
    location: location
    tags: tags
    sku: staticWebAppSku
    repositoryUrl: repositoryUrl
    branch: branch
    buildProperties: {
      appLocation: appLocation
      outputLocation: outputLocation
      appArtifactLocation: outputLocation
    }
  }
}

// ── Outputs ─────────────────────────────────────────────────────────────────
@description('Static Web App resource ID.')
output resourceId string = staticSite.outputs.resourceId

@description('Static Web App resource name.')
output resourceName string = staticSite.outputs.name

@description('Default hostname of the Static Web App (e.g. *.azurestaticapps.net).')
output defaultHostname string = staticSite.outputs.defaultHostname

@secure()
@description('Deployment token for the Static Web App (used by CI/CD).')
// AVM web/static-site:0.9.3 does not expose apiKey as an output.
// listSecrets() requires a value calculable at deployment start — module outputs
// are runtime values and cannot be passed directly.  resourceId() resolves the
// fully-qualified ID from the deterministic staticSiteName variable, which Bicep
// can evaluate before deployment begins.  The dependsOn relationship ensures the
// Static Web App resource exists before listSecrets() is called at deploy time.
output deploymentToken string = listSecrets(
  resourceId('Microsoft.Web/staticSites', staticSiteName),
  '2023-01-01'
).properties.apiKey
