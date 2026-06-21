---
name: workflow-generation
description: Generate production-ready GitHub Actions YAML for IaC, Azure Functions, and Static Web App deployments — job structure, artifact handling, and rollback
---

# Workflow Generation Skill

## Purpose

Produce working, secure, idempotent GitHub Actions workflow files that deploy Azure infrastructure and application code across dev/staging/prod environments.

## When to Use

When implementing the workflows specified in `design-document.md` Section 11.

## Process

1. Read Section 11.1 for the list of workflow files to create.
2. Read Section 11.3 for the per-workflow job/step specification.
3. Apply the patterns below for each workflow type.
4. Pin all action versions explicitly.
5. Write all files under `.github/workflows/`.

**IaC deployment workflow pattern:**

```yaml
name: Deploy Infrastructure

on:
  push:
    branches: [main]
    paths: ['outputs/bicep-templates/**']
  workflow_dispatch:
    inputs:
      environment:
        description: Target environment
        required: true
        default: dev
        type: choice
        options: [dev, staging, prod]

permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: ${{ github.event.inputs.environment || 'staging' }}
    steps:
      - uses: actions/checkout@v4

      - name: Azure Login
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Validate Bicep
        run: az bicep build --file outputs/bicep-templates/main.bicep

      - name: What-If Check
        run: |
          az deployment group what-if \
            --resource-group ${{ vars.RESOURCE_GROUP_NAME }} \
            --template-file outputs/bicep-templates/main.bicep \
            --parameters outputs/bicep-templates/parameters/${{ github.event.inputs.environment || 'staging' }}.bicepparam \
            --mode Incremental

      - name: Deploy
        id: deploy
        run: |
          az deployment group create \
            --name "deploy-${{ github.run_id }}" \
            --resource-group ${{ vars.RESOURCE_GROUP_NAME }} \
            --template-file outputs/bicep-templates/main.bicep \
            --parameters outputs/bicep-templates/parameters/${{ github.event.inputs.environment || 'staging' }}.bicepparam \
            --mode Incremental

      - name: Rollback on failure
        if: failure() && steps.deploy.outcome == 'failure'
        run: |
          az deployment group cancel \
            --name "deploy-${{ github.run_id }}" \
            --resource-group ${{ vars.RESOURCE_GROUP_NAME }} || true
```

**Azure Functions deployment workflow pattern:**

```yaml
name: Deploy Azure Functions

on:
  push:
    branches: [main]
    paths: ['outputs/azure-functions/**']

permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: staging
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: pip install -r outputs/azure-functions/requirements.txt --target .python_packages/lib/site-packages

      - name: Package function app
        run: |
          cd outputs/azure-functions
          zip -r ../../function-app.zip . -x "*.pyc" -x "__pycache__/*"
          cd ../..

      - uses: actions/upload-artifact@v4
        with:
          name: function-app
          path: function-app.zip

      - name: Azure Login
        uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Deploy to Azure Functions
        run: |
          az functionapp deployment source config-zip \
            --name ${{ vars.FUNCTION_APP_NAME }} \
            --resource-group ${{ vars.RESOURCE_GROUP_NAME }} \
            --src function-app.zip
```

## Rules

- **Always set `permissions: id-token: write`** — without this, OIDC token is not issued.
- **Always pin action versions** — `actions/checkout@v4` not `@latest`. Never use a moving tag.
- **Never put environment-specific values in workflow YAML** — always `${{ secrets.X }}` or `${{ vars.X }}`.
- **Always include a what-if step before any `az deployment group create`** — never deploy without preview.
- **Always include a rollback step** using `if: failure()` — the step should attempt to cancel the in-flight deployment.
- **Never use `continue-on-error: true`** on deployment steps — fail fast.

## Output

- `.github/workflows/deploy-infra.yml` — IaC deployment workflow
- `.github/workflows/deploy-functions.yml` — Function App deployment workflow
- Additional workflows as specified in `design-document.md` Section 11.1
