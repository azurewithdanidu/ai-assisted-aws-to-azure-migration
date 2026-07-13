#!/usr/bin/env bash
# Pre-deployment validation: Bicep syntax, ARM validation, what-if dry-run, policy check, quota check.
# Usage: run-what-if.sh --resource-group <rg> --environment <dev|staging|prod> [--bicep-root <path>] [--subscription <id>]
#
# Outputs:
#   outputs/deployment-validation/what-if-<env>.json
#   outputs/deployment-validation/what-if-report.md
# Exits 1 if any BLOCKING condition is found.

set -euo pipefail

RESOURCE_GROUP=""
ENVIRONMENT=""
BICEP_ROOT="outputs/bicep-templates"
SUBSCRIPTION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --resource-group)  RESOURCE_GROUP="$2"; shift 2 ;;
    --environment)     ENVIRONMENT="$2";    shift 2 ;;
    --bicep-root)      BICEP_ROOT="$2";     shift 2 ;;
    --subscription)    SUBSCRIPTION="$2";   shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

[[ -z "$RESOURCE_GROUP" ]] && { echo "ERROR: --resource-group is required"; exit 1; }
[[ -z "$ENVIRONMENT" ]]    && { echo "ERROR: --environment is required (dev|staging|prod)"; exit 1; }
[[ "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]] || { echo "ERROR: --environment must be dev, staging, or prod"; exit 1; }

MAIN_BICEP="$BICEP_ROOT/main.bicep"
PARAM_FILE="$BICEP_ROOT/parameters/$ENVIRONMENT.bicepparam"
OUT_DIR="outputs/deployment-validation"
WHATIF_FILE="$OUT_DIR/what-if-$ENVIRONMENT.json"
REPORT_FILE="$OUT_DIR/what-if-report.md"

SUB_ARGS=()
[[ -n "$SUBSCRIPTION" ]] && SUB_ARGS=(--subscription "$SUBSCRIPTION")

BLOCKING=0
WARNINGS=0
REPORT_LINES=()

step()    { echo; echo "==> $1"; }
pass()    { echo "  [PASS]    $1"; REPORT_LINES+=("- [x] PASS: $1"); }
warn()    { echo "  [WARN]    $1"; REPORT_LINES+=("- [ ] WARN: $1"); ((WARNINGS++)); }
block()   { echo "  [BLOCKED] $1"; REPORT_LINES+=("- [ ] BLOCKED: $1"); ((BLOCKING++)); }

mkdir -p "$OUT_DIR"

# ── Step 1: Bicep syntax ──────────────────────────────────────────────────────
step "Step 1 — Bicep syntax (az bicep build)"
az bicep restore --file "$MAIN_BICEP" --force &>/dev/null
if ! az bicep build --file "$MAIN_BICEP" 2>&1; then
  block "az bicep build FAILED — fix syntax errors first"
  exit 1
fi
pass "az bicep build"

# ── Step 2: ARM validation ────────────────────────────────────────────────────
step "Step 2 — ARM template validation"
if ! az deployment group validate \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$MAIN_BICEP" \
    --parameters "$PARAM_FILE" \
    "${SUB_ARGS[@]}" \
    --output json &>/dev/null; then
  block "ARM validation failed — run manually for details"
  exit 1
fi
pass "az deployment group validate"

# ── Step 3: What-if dry run ───────────────────────────────────────────────────
step "Step 3 — What-if dry run (Incremental mode)"
az deployment group what-if \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$MAIN_BICEP" \
    --parameters "$PARAM_FILE" \
    --mode Incremental \
    --output json \
    "${SUB_ARGS[@]}" 2>&1 > "$WHATIF_FILE" || true

echo "  Saved to $WHATIF_FILE"

if command -v jq &>/dev/null && [[ -s "$WHATIF_FILE" ]]; then
  # Blocking: delete on data resources
  DELETES=$(jq -r '.properties.changes[]? | select(.changeType=="Delete") | select(.resourceId | test("storageAccounts|vaults|servers|namespaces|databaseAccounts|redis")) | .resourceId' "$WHATIF_FILE" 2>/dev/null || true)
  while IFS= read -r rid; do
    [[ -n "$rid" ]] && block "Delete on data resource: $rid"
  done <<< "$DELETES"

  # Blocking: public network access re-enabled
  PUBLIC=$(jq -r '.properties.changes[]? | select(.changeType=="Create" or .changeType=="Modify") | .resourceId' "$WHATIF_FILE" 2>/dev/null || true)
  [[ -n "$PUBLIC" ]] && warn "Review Modify/Create changes for publicNetworkAccess in $WHATIF_FILE"

  NEW_COUNT=$(jq '[.properties.changes[]? | select(.changeType=="Create")] | length' "$WHATIF_FILE" 2>/dev/null || echo 0)
  MOD_COUNT=$(jq '[.properties.changes[]? | select(.changeType=="Modify")] | length' "$WHATIF_FILE" 2>/dev/null || echo 0)
  [[ "$NEW_COUNT" -gt 0 ]] && warn "$NEW_COUNT new resource(s) will be created (review expected)"
  [[ "$MOD_COUNT" -gt 0 ]] && warn "$MOD_COUNT resource(s) will be modified (review expected)"
  [[ "$BLOCKING" -eq 0 ]] && pass "No blocking conditions found in what-if output"
else
  warn "Could not parse what-if JSON — review $WHATIF_FILE manually"
fi

# ── Step 4: Policy compliance ─────────────────────────────────────────────────
step "Step 4 — Policy compliance check"
NON_COMPLIANT=$(az policy state summarize --resource-group "$RESOURCE_GROUP" "${SUB_ARGS[@]}" --output json 2>/dev/null \
  | jq '.results.nonCompliantResources // 0' 2>/dev/null || echo 0)
if [[ "$NON_COMPLIANT" -gt 0 ]]; then
  block "$NON_COMPLIANT non-compliant resource(s) — check for Deny-effect policies before deploying"
else
  pass "Policy compliance — 0 non-compliant resources"
fi

# ── Step 5: Quota spot-check ──────────────────────────────────────────────────
step "Step 5 — Quota spot-checks"
STOR_COUNT=$(az resource list --resource-group "$RESOURCE_GROUP" \
  --resource-type Microsoft.Storage/storageAccounts "${SUB_ARGS[@]}" --output json 2>/dev/null \
  | jq 'length' 2>/dev/null || echo 0)
if [[ "$STOR_COUNT" -ge 240 ]]; then
  warn "Storage account count is $STOR_COUNT — approaching 250/region limit"
else
  pass "Storage account count: $STOR_COUNT (limit 250)"
fi

# ── Write report ──────────────────────────────────────────────────────────────
STATUS="PASS"
[[ "$BLOCKING" -gt 0 ]] && STATUS="BLOCKED"
[[ "$BLOCKING" -eq 0 && "$WARNINGS" -gt 0 ]] && STATUS="PASS (with warnings)"

{
  echo "# What-If Validation Report — $ENVIRONMENT"
  echo ""
  echo "**Date:** $(date -u '+%Y-%m-%d')"
  echo "**Environment:** $ENVIRONMENT"
  echo "**Resource Group:** $RESOURCE_GROUP"
  echo "**Status:** $STATUS"
  echo ""
  echo "## Checks"
  echo ""
  for line in "${REPORT_LINES[@]}"; do echo "$line"; done
  echo ""
  echo "## What-If Output"
  echo "Saved to: $WHATIF_FILE"
} > "$REPORT_FILE"

echo ""
echo "Report written to $REPORT_FILE"

if [[ "$BLOCKING" -gt 0 ]]; then
  echo "RESULT: $BLOCKING BLOCKING condition(s) — deployment must not proceed"
  exit 1
fi
echo "RESULT: Validation PASSED ($WARNINGS warning(s))"
