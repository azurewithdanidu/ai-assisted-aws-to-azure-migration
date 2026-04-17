#!/usr/bin/env bash
# =============================================================================
# deploy.sh — Azure Bicep Deployment Script
# Replaces: aws cloudformation deploy
#
# Usage:
#   ./scripts/deploy.sh <resource-group> [parameter-file] [subscription-id]
#
# Examples:
#   ./scripts/deploy.sh rg-img-upload-dev
#   ./scripts/deploy.sh rg-img-upload-prod outputs/bicep-templates/parameters/prod.bicepparam
#   ./scripts/deploy.sh rg-img-upload-prod outputs/bicep-templates/parameters/prod.bicepparam 00000000-0000-0000-0000-000000000000
# =============================================================================

set -euo pipefail

RESOURCE_GROUP="${1:-}"
PARAM_FILE="${2:-outputs/bicep-templates/parameters/dev.bicepparam}"
SUBSCRIPTION_ID="${3:-}"
TEMPLATE_FILE="outputs/bicep-templates/main.bicep"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEPLOYMENT_RECORD_FILE="/tmp/deployments-$(echo "${RESOURCE_GROUP}" | tr '/' '-').txt"

# Validate required arguments
if [[ -z "${RESOURCE_GROUP}" ]]; then
  echo "ERROR: Resource group argument is required."
  echo "Usage: $0 <resource-group> [parameter-file] [subscription-id]"
  exit 1
fi

# Set subscription if provided
if [[ -n "${SUBSCRIPTION_ID}" ]]; then
  az account set --subscription "${SUBSCRIPTION_ID}"
fi

# Unique deployment name (timestamp + build number if available)
BUILD_NUM="${BUILDKITE_BUILD_NUMBER:-local}"
DEPLOYMENT_NAME="bicep-deploy-${BUILD_NUM}-$(date +%s)"

echo "============================================================"
echo " Azure Bicep Deployment"
echo " Deployment name: ${DEPLOYMENT_NAME}"
echo " Template:        ${TEMPLATE_FILE}"
echo " Parameter file:  ${PARAM_FILE}"
echo " Resource group:  ${RESOURCE_GROUP}"
echo "============================================================"

cd "${REPO_ROOT}"

# ---------------------------------------------------------------------------
# Pre-flight: Run validation before deployment
# ---------------------------------------------------------------------------
echo ""
echo "--- Running pre-deployment validation..."
bash scripts/validate-deployment.sh "${RESOURCE_GROUP}" "${PARAM_FILE}"

# ---------------------------------------------------------------------------
# Deploy: Incremental mode preserves resources not defined in this template
# Replaces: aws cloudformation deploy --capabilities CAPABILITY_IAM
# ---------------------------------------------------------------------------
echo ""
echo "--- Deploying to Azure..."
echo ""

az deployment group create \
  --name "${DEPLOYMENT_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --template-file "${TEMPLATE_FILE}" \
  --parameters "${PARAM_FILE}" \
  --mode Incremental \
  --output table

DEPLOYMENT_STATUS=$?

if [[ ${DEPLOYMENT_STATUS} -eq 0 ]]; then
  echo ""
  echo "============================================================"
  echo " Deployment successful!"
  echo " Deployment name: ${DEPLOYMENT_NAME}"
  echo "============================================================"

  # Record deployment for rollback
  echo "${DEPLOYMENT_NAME}" >> "${DEPLOYMENT_RECORD_FILE}"

  # Retrieve and display key outputs
  echo ""
  echo "--- Deployment Outputs:"
  az deployment group show \
    --name "${DEPLOYMENT_NAME}" \
    --resource-group "${RESOURCE_GROUP}" \
    --query "properties.outputs" \
    --output table

else
  echo ""
  echo "============================================================"
  echo " ERROR: Deployment failed!"
  echo " Deployment name: ${DEPLOYMENT_NAME}"
  echo " Check Azure Portal or: az deployment group show --name ${DEPLOYMENT_NAME} --resource-group ${RESOURCE_GROUP}"
  echo " To rollback: ./scripts/rollback.sh ${RESOURCE_GROUP}"
  echo "============================================================"
  exit 1
fi
