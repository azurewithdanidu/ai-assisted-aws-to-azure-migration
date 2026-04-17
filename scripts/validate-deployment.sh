#!/usr/bin/env bash
# =============================================================================
# validate-deployment.sh — Pre-deployment Bicep Validation + What-If Analysis
# Replaces: aws cloudformation validate-template + changeset preview
#
# Usage:
#   ./scripts/validate-deployment.sh <resource-group> [parameter-file]
#
# Examples:
#   ./scripts/validate-deployment.sh rg-img-upload-dev
#   ./scripts/validate-deployment.sh rg-img-upload-prod outputs/bicep-templates/parameters/prod.bicepparam
# =============================================================================

set -euo pipefail

RESOURCE_GROUP="${1:-}"
PARAM_FILE="${2:-outputs/bicep-templates/parameters/dev.bicepparam}"
TEMPLATE_FILE="outputs/bicep-templates/main.bicep"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Validate required arguments
if [[ -z "${RESOURCE_GROUP}" ]]; then
  echo "ERROR: Resource group argument is required."
  echo "Usage: $0 <resource-group> [parameter-file]"
  exit 1
fi

echo "============================================================"
echo " Validating Bicep Templates"
echo " Template:        ${TEMPLATE_FILE}"
echo " Parameter file:  ${PARAM_FILE}"
echo " Resource group:  ${RESOURCE_GROUP}"
echo "============================================================"

# Change to repo root
cd "${REPO_ROOT}"

# ---------------------------------------------------------------------------
# Step 1: Build / lint all Bicep templates (syntax validation)
# Replaces: aws cloudformation validate-template
# ---------------------------------------------------------------------------
echo ""
echo "--- Step 1: Validating Bicep syntax (az bicep build)"
echo ""

BICEP_FILES=(
  "outputs/bicep-templates/main.bicep"
  "outputs/bicep-templates/modules/monitoring.bicep"
  "outputs/bicep-templates/modules/keyvault.bicep"
  "outputs/bicep-templates/modules/storage.bicep"
  "outputs/bicep-templates/modules/staticweb.bicep"
  "outputs/bicep-templates/modules/functions.bicep"
)

for f in "${BICEP_FILES[@]}"; do
  echo "  Validating: ${f}"
  az bicep build --file "${f}" --stdout > /dev/null
  echo "  ✓ ${f}"
done

echo ""
echo "All Bicep templates validated successfully."

# ---------------------------------------------------------------------------
# Step 2: ARM template validation (against Azure Resource Manager API)
# Validates resource types, API versions, required properties
# ---------------------------------------------------------------------------
echo ""
echo "--- Step 2: ARM template validation (az deployment group validate)"
echo ""

az deployment group validate \
  --resource-group "${RESOURCE_GROUP}" \
  --template-file "${TEMPLATE_FILE}" \
  --parameters "${PARAM_FILE}" \
  --mode Incremental \
  --output table

echo ""
echo "ARM validation passed."

# ---------------------------------------------------------------------------
# Step 3: What-If analysis (preview all resource changes)
# No AWS CloudFormation equivalent — key Azure deployment safety feature
# ---------------------------------------------------------------------------
echo ""
echo "--- Step 3: What-If analysis (az deployment group what-if)"
echo ""

WHATIF_OUTPUT_FILE="/tmp/whatif-results-$(date +%s).txt"

az deployment group what-if \
  --name "whatif-$(date +%s)" \
  --resource-group "${RESOURCE_GROUP}" \
  --template-file "${TEMPLATE_FILE}" \
  --parameters "${PARAM_FILE}" \
  --mode Incremental \
  --result-format FullResourcePayloads \
  --output table | tee "${WHATIF_OUTPUT_FILE}"

# Check for policy violations or critical changes in what-if output
if grep -qi "conflict\|error\|denied\|policy" "${WHATIF_OUTPUT_FILE}" 2>/dev/null; then
  echo ""
  echo "WARNING: Potential policy violations or conflicts detected in what-if output."
  echo "         Review the output above before proceeding."
  exit 1
fi

echo ""
echo "============================================================"
echo " Validation Complete — Deployment is safe to proceed."
echo " Run: ./scripts/deploy.sh ${RESOURCE_GROUP} ${PARAM_FILE}"
echo "============================================================"
