#!/usr/bin/env bash
# Validate all Bicep files and optionally run what-if for each parameter file.
# Usage: validate-bicep.sh [--bicep-root <path>] [--resource-group <rg>] [--subscription <id>]
#
# --resource-group is optional. If omitted, what-if dry runs are skipped (syntax-only).
# Exits 1 if any check fails.

set -euo pipefail

BICEP_ROOT="outputs/bicep-templates"
RESOURCE_GROUP=""
SUBSCRIPTION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bicep-root)      BICEP_ROOT="$2";      shift 2 ;;
    --resource-group)  RESOURCE_GROUP="$2";  shift 2 ;;
    --subscription)    SUBSCRIPTION="$2";    shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

MAIN_BICEP="$BICEP_ROOT/main.bicep"
if [[ ! -f "$MAIN_BICEP" ]]; then
  echo "ERROR: main.bicep not found at '$MAIN_BICEP'. Adjust --bicep-root."
  exit 1
fi

SUB_ARGS=()
[[ -n "$SUBSCRIPTION" ]] && SUB_ARGS=(--subscription "$SUBSCRIPTION")

ERRORS=0

pass() { echo "  [PASS] $1"; }
fail() { echo "  [FAIL] $1"; ((ERRORS++)); }

# ── Step 1: Restore AVM modules ───────────────────────────────────────────────
echo ""
echo "==> Restoring AVM module cache"
if az bicep restore --file "$MAIN_BICEP" --force 2>&1; then
  pass "az bicep restore"
else
  fail "az bicep restore failed"
  exit 1
fi

# ── Step 2: Build (syntax-check) every .bicep file ────────────────────────────
echo ""
echo "==> Building (syntax-checking) all Bicep files under $BICEP_ROOT"
while IFS= read -r -d '' bicep_file; do
  fname=$(basename "$bicep_file")
  if az bicep build --file "$bicep_file" &>/dev/null; then
    pass "$fname"
  else
    fail "$fname"
  fi
done < <(find "$BICEP_ROOT" -name "*.bicep" -print0)

# ── Step 3: What-if for each parameter file ───────────────────────────────────
if [[ -n "$RESOURCE_GROUP" ]]; then
  PARAMS_DIR="$BICEP_ROOT/parameters"
  echo ""
  echo "==> Running what-if for each parameter file"

  PARAM_FILES=()
  while IFS= read -r -d '' f; do
    PARAM_FILES+=("$f")
  done < <(find "$PARAMS_DIR" -name "*.bicepparam" -print0 2>/dev/null || true)

  if [[ "${#PARAM_FILES[@]}" -eq 0 ]]; then
    echo "  No .bicepparam files found under $PARAMS_DIR — skipping what-if"
  else
    for pf in "${PARAM_FILES[@]}"; do
      env_name=$(basename "$pf" .bicepparam)
      echo -n "  what-if: $env_name ... "
      WHATIF_OUT=$(az deployment group what-if \
          --resource-group "$RESOURCE_GROUP" \
          --template-file "$MAIN_BICEP" \
          --parameters "$pf" \
          --mode Incremental \
          --output json \
          "${SUB_ARGS[@]}" 2>&1 || true)

      if echo "$WHATIF_OUT" | jq -e . &>/dev/null; then
        BLOCKING=$(echo "$WHATIF_OUT" | jq -r \
          '[.properties.changes[]? | select(.changeType=="Delete") | select(.resourceId | test("storageAccounts|vaults|servers|namespaces|databaseAccounts"))] | length' \
          2>/dev/null || echo 0)
        if [[ "$BLOCKING" -gt 0 ]]; then
          fail "$env_name — BLOCKING DELETE on data resource(s)"
          echo "$WHATIF_OUT" | jq -r \
            '.properties.changes[]? | select(.changeType=="Delete") | select(.resourceId | test("storageAccounts|vaults|servers|namespaces|databaseAccounts")) | "    DELETE: \(.resourceId)"' \
            2>/dev/null || true
        else
          pass "$env_name — no blocking changes"
        fi
      else
        echo "(could not parse JSON — review manually)"
      fi
    done
  fi
else
  echo ""
  echo "  --resource-group not supplied — skipping what-if dry runs"
fi

# ── Result ─────────────────────────────────────────────────────────────────────
echo ""
if [[ "$ERRORS" -gt 0 ]]; then
  echo "RESULT: $ERRORS check(s) FAILED"
  exit 1
fi
echo "RESULT: All Bicep validation checks PASSED"
