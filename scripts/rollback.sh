#!/usr/bin/env bash
# =============================================================================
# rollback.sh — Azure Deployment Rollback Script
# Retrieves the previously successful deployment and re-deploys its template
#
# Usage:
#   ./scripts/rollback.sh <resource-group> [target-deployment-name]
#
# Examples:
#   ./scripts/rollback.sh rg-img-upload-prod
#   ./scripts/rollback.sh rg-img-upload-prod bicep-deploy-42-1713000000
#
# Note: Azure Incremental deployment mode means resources added in a failed
# deployment may persist. This script re-applies the last known-good state.
# For full cleanup, use 'Complete' mode or delete individual resources.
# =============================================================================

set -euo pipefail

RESOURCE_GROUP="${1:-}"
TARGET_DEPLOYMENT="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Validate required arguments
if [[ -z "${RESOURCE_GROUP}" ]]; then
  echo "ERROR: Resource group argument is required."
  echo "Usage: $0 <resource-group> [target-deployment-name]"
  exit 1
fi

echo "============================================================"
echo " Azure Deployment Rollback"
echo " Resource group: ${RESOURCE_GROUP}"
echo "============================================================"

# ---------------------------------------------------------------------------
# Step 1: Find the target deployment (previous successful deployment)
# ---------------------------------------------------------------------------
if [[ -z "${TARGET_DEPLOYMENT}" ]]; then
  echo ""
  echo "--- Finding previous successful deployment..."

  # Get the 2nd most recent successful deployment (skip current/failed)
  TARGET_DEPLOYMENT=$(az deployment group list \
    --resource-group "${RESOURCE_GROUP}" \
    --filter "provisioningState eq 'Succeeded'" \
    --query "sort_by(@, &properties.timestamp)[-2].name" \
    --output tsv 2>/dev/null || true)

  if [[ -z "${TARGET_DEPLOYMENT}" ]]; then
    # Fall back to most recent successful deployment
    TARGET_DEPLOYMENT=$(az deployment group list \
      --resource-group "${RESOURCE_GROUP}" \
      --filter "provisioningState eq 'Succeeded'" \
      --query "sort_by(@, &properties.timestamp)[-1].name" \
      --output tsv 2>/dev/null || true)
  fi
fi

if [[ -z "${TARGET_DEPLOYMENT}" ]]; then
  echo "ERROR: No successful previous deployment found in resource group '${RESOURCE_GROUP}'."
  echo "       Manual intervention required."
  echo ""
  echo "To list all deployments:"
  echo "  az deployment group list --resource-group ${RESOURCE_GROUP} --output table"
  exit 1
fi

echo "  Target deployment: ${TARGET_DEPLOYMENT}"

# ---------------------------------------------------------------------------
# Step 2: Retrieve the template from the target deployment
# ---------------------------------------------------------------------------
echo ""
echo "--- Retrieving template from previous deployment..."

TEMPLATE_FILE="/tmp/rollback-template-$(date +%s).json"

az deployment group export \
  --name "${TARGET_DEPLOYMENT}" \
  --resource-group "${RESOURCE_GROUP}" \
  --output json > "${TEMPLATE_FILE}"

echo "  Template saved to: ${TEMPLATE_FILE}"

# ---------------------------------------------------------------------------
# Step 3: Run what-if against the rollback template
# ---------------------------------------------------------------------------
echo ""
echo "--- What-if analysis for rollback..."

az deployment group what-if \
  --name "whatif-rollback-$(date +%s)" \
  --resource-group "${RESOURCE_GROUP}" \
  --template-file "${TEMPLATE_FILE}" \
  --mode Incremental \
  --output table

echo ""
read -r -p "Proceed with rollback to deployment '${TARGET_DEPLOYMENT}'? [y/N] " confirm
if [[ "${confirm}" != "y" && "${confirm}" != "Y" ]]; then
  echo "Rollback cancelled."
  exit 0
fi

# ---------------------------------------------------------------------------
# Step 4: Re-deploy the previous template
# ---------------------------------------------------------------------------
ROLLBACK_DEPLOYMENT_NAME="rollback-$(date +%s)"
echo ""
echo "--- Rolling back to '${TARGET_DEPLOYMENT}'..."
echo "    Rollback deployment name: ${ROLLBACK_DEPLOYMENT_NAME}"

az deployment group create \
  --name "${ROLLBACK_DEPLOYMENT_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --template-file "${TEMPLATE_FILE}" \
  --mode Incremental \
  --output table

if [[ $? -eq 0 ]]; then
  echo ""
  echo "============================================================"
  echo " Rollback successful!"
  echo " Rolled back to: ${TARGET_DEPLOYMENT}"
  echo " Rollback deployment: ${ROLLBACK_DEPLOYMENT_NAME}"
  echo "============================================================"

  # Clean up temp file
  rm -f "${TEMPLATE_FILE}"
else
  echo ""
  echo "============================================================"
  echo " ERROR: Rollback failed!"
  echo " Template retained at: ${TEMPLATE_FILE}"
  echo " Manual intervention required."
  echo " Contact: ops@example.com"
  echo "============================================================"
  exit 1
fi
