#!/usr/bin/env bash
# =============================================================
# scripts/validate-deployment.sh
# Pre-deployment validation: Bicep build + what-if check
# =============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BICEP_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENVIRONMENT="${1:-dev}"
RESOURCE_GROUP="${2:-rg-image-upload}"
PARAM_FILE="${BICEP_ROOT}/parameters/${ENVIRONMENT}.bicepparam"

echo "========================================================"
echo " Image Upload Service — Bicep Validation"
echo " Environment : ${ENVIRONMENT}"
echo " Resource Group: ${RESOURCE_GROUP}"
echo "========================================================"

# ── Step 1: Restore AVM modules from MCR registry ─────────────────────────────
echo ""
echo "=== Step 1: Restoring AVM modules ==="
az bicep restore \
  --file "${BICEP_ROOT}/main.bicep" \
  --force

echo "✅ AVM modules restored"

# ── Step 2: Build (compile) all Bicep files ───────────────────────────────────
echo ""
echo "=== Step 2: Building Bicep templates ==="
for bicep_file in \
  "${BICEP_ROOT}/main.bicep" \
  "${BICEP_ROOT}/modules/monitoring.bicep" \
  "${BICEP_ROOT}/modules/storage.bicep" \
  "${BICEP_ROOT}/modules/function-app.bicep" \
  "${BICEP_ROOT}/modules/static-web-app.bicep" \
  "${BICEP_ROOT}/modules/rbac.bicep"; do
  echo "  Building: ${bicep_file}"
  az bicep build --file "${bicep_file}"
done
echo "✅ All templates compiled successfully"

# ── Step 3: What-if check ─────────────────────────────────────────────────────
echo ""
echo "=== Step 3: Running deployment what-if ==="
WHATIF_OUTPUT=$(az deployment group what-if \
  --name "bicep-whatif-${ENVIRONMENT}-$(date +%s)" \
  --resource-group "${RESOURCE_GROUP}" \
  --template-file "${BICEP_ROOT}/main.bicep" \
  --parameters "${PARAM_FILE}" \
  --mode Incremental \
  2>&1)

echo "${WHATIF_OUTPUT}"

# Check for policy violations
if echo "${WHATIF_OUTPUT}" | grep -qi "deny\|policy violation"; then
  echo ""
  echo "❌ WARNING: Potential policy violations detected in what-if output."
  exit 1
fi

echo ""
echo "✅ What-if check passed — no blocking issues detected"
echo ""
echo "========================================================"
echo " Validation complete. Ready to deploy with deploy.sh."
echo "========================================================"
