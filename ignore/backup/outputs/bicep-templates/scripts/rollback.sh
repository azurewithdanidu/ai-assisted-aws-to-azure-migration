#!/usr/bin/env bash
# =============================================================
# scripts/rollback.sh
# Roll back to the previous successful deployment by re-deploying
# the ARM template captured in that deployment.
#
# Azure does not support native template rollback via the CLI,
# so this script retrieves the previous deployment's template
# and re-deploys it with the same parameters.
#
# Usage:
#   ./rollback.sh <environment> <resource-group>
#   ./rollback.sh dev rg-image-upload-dev
# =============================================================
set -euo pipefail

ENVIRONMENT="${1:-dev}"
RESOURCE_GROUP="${2:-rg-image-upload}"
DEPLOYMENT_RECORD="/tmp/img-upload-last-deployment-${ENVIRONMENT}.txt"

echo "========================================================"
echo " Image Upload Service — Rollback"
echo " Environment   : ${ENVIRONMENT}"
echo " Resource Group: ${RESOURCE_GROUP}"
echo "========================================================"

# ── Find previous successful deployment ──────────────────────────────────────
# Sort deployments by timestamp descending and take the second one
# (index 1 = previous; index 0 = current/latest)
echo ""
echo "=== Finding previous successful deployment ==="
DEPLOYMENTS=$(az deployment group list \
  --resource-group "${RESOURCE_GROUP}" \
  --filter "provisioningState eq 'Succeeded'" \
  --query "sort_by(@, &properties.timestamp)[].name" \
  --output tsv)

DEPLOYMENT_COUNT=$(echo "${DEPLOYMENTS}" | grep -c . || true)

if [[ ${DEPLOYMENT_COUNT} -lt 2 ]]; then
  echo "❌ Cannot roll back — fewer than 2 successful deployments found."
  echo "   Deployments found: ${DEPLOYMENT_COUNT}"
  exit 1
fi

# Second-to-last successful deployment
PREVIOUS=$(echo "${DEPLOYMENTS}" | tail -2 | head -1)
CURRENT=$(echo "${DEPLOYMENTS}" | tail -1)

echo "   Current deployment : ${CURRENT}"
echo "   Rollback target    : ${PREVIOUS}"

# ── Retrieve previous deployment template ─────────────────────────────────────
echo ""
echo "=== Retrieving template from deployment '${PREVIOUS}' ==="
TEMPLATE_FILE="/tmp/rollback-template-${ENVIRONMENT}.json"
az deployment group export \
  --name "${PREVIOUS}" \
  --resource-group "${RESOURCE_GROUP}" \
  --output json > "${TEMPLATE_FILE}"

if [[ ! -s "${TEMPLATE_FILE}" ]]; then
  echo "❌ Failed to export template from previous deployment."
  exit 1
fi
echo "   Template saved to: ${TEMPLATE_FILE}"

# ── Re-deploy previous template ───────────────────────────────────────────────
ROLLBACK_DEPLOYMENT_NAME="img-upload-rollback-${ENVIRONMENT}-$(date +%Y%m%d%H%M%S)"
echo ""
echo "=== Re-deploying previous template as '${ROLLBACK_DEPLOYMENT_NAME}' ==="
az deployment group create \
  --name "${ROLLBACK_DEPLOYMENT_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --template-file "${TEMPLATE_FILE}" \
  --mode Incremental

ROLLBACK_EXIT=$?

if [[ ${ROLLBACK_EXIT} -ne 0 ]]; then
  echo ""
  echo "❌ Rollback deployment failed (exit code ${ROLLBACK_EXIT})."
  echo "   Manual intervention required."
  echo "   Previous template is available at: ${TEMPLATE_FILE}"
  exit ${ROLLBACK_EXIT}
fi

echo ""
echo "✅ Rollback successful: ${ROLLBACK_DEPLOYMENT_NAME}"
echo "   The stack has been reverted to the state from deployment '${PREVIOUS}'."
echo "========================================================"
