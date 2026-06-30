#!/usr/bin/env bash
# =============================================================
# scripts/deploy.sh
# Deploy the image-upload Bicep stack to a target environment.
# Stores the deployment name for rollback reference.
#
# Usage:
#   ./deploy.sh <environment> <resource-group>
#   ./deploy.sh dev    rg-image-upload-dev
#   ./deploy.sh staging rg-image-upload-stg
#   ./deploy.sh prod   rg-image-upload-prd
# =============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BICEP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENVIRONMENT="${1:-dev}"
RESOURCE_GROUP="${2:-rg-image-upload}"
PARAM_FILE="${BICEP_ROOT}/parameters/${ENVIRONMENT}.bicepparam"
DEPLOYMENT_NAME="img-upload-${ENVIRONMENT}-$(date +%Y%m%d%H%M%S)"
DEPLOYMENT_RECORD="/tmp/img-upload-last-deployment-${ENVIRONMENT}.txt"

echo "========================================================"
echo " Image Upload Service — Bicep Deployment"
echo " Environment   : ${ENVIRONMENT}"
echo " Resource Group: ${RESOURCE_GROUP}"
echo " Deployment ID : ${DEPLOYMENT_NAME}"
echo "========================================================"

# ── Pre-flight checks ─────────────────────────────────────────────────────────
if [[ ! -f "${PARAM_FILE}" ]]; then
  echo "❌ Parameter file not found: ${PARAM_FILE}"
  exit 1
fi

if ! az group show --name "${RESOURCE_GROUP}" &>/dev/null; then
  echo "⚠️  Resource group '${RESOURCE_GROUP}' does not exist. Creating..."
  az group create \
    --name "${RESOURCE_GROUP}" \
    --location australiasoutheast \
    --tags workload=image-upload environment="${ENVIRONMENT}" managedBy=bicep
fi

# ── Restore AVM modules ───────────────────────────────────────────────────────
echo ""
echo "=== Restoring AVM modules ==="
az bicep restore --file "${BICEP_ROOT}/main.bicep" --force
echo "✅ AVM modules restored"

# ── Deploy ────────────────────────────────────────────────────────────────────
echo ""
echo "=== Deploying Bicep stack ==="
az deployment group create \
  --name "${DEPLOYMENT_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --template-file "${BICEP_ROOT}/main.bicep" \
  --parameters "${PARAM_FILE}" \
  --mode Incremental

DEPLOY_EXIT=$?

if [[ ${DEPLOY_EXIT} -ne 0 ]]; then
  echo ""
  echo "❌ Deployment failed (exit code ${DEPLOY_EXIT})"
  echo "   Run rollback.sh to revert to the previous deployment."
  exit ${DEPLOY_EXIT}
fi

# ── Save deployment name for rollback ─────────────────────────────────────────
echo "${DEPLOYMENT_NAME}" > "${DEPLOYMENT_RECORD}"
echo ""
echo "✅ Deployment successful: ${DEPLOYMENT_NAME}"
echo "   Deployment ID saved to: ${DEPLOYMENT_RECORD}"

# ── Show key outputs ──────────────────────────────────────────────────────────
echo ""
echo "=== Deployment Outputs ==="
az deployment group show \
  --name "${DEPLOYMENT_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --query "properties.outputs" \
  --output table

echo ""
echo "========================================================"
echo " Deployment complete."
echo " Next: Update CORS origins with the Static Web App"
echo " hostname shown in outputs above, then re-deploy."
echo "========================================================"
