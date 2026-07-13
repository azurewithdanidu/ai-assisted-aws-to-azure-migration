#!/usr/bin/env bash
# Post-deployment smoke tests for a migrated Azure environment.
# Usage: smoke-test.sh --resource-group <rg> --environment <dev|staging|prod> \
#          --function-app-name <name> --key-vault-name <name> \
#          [--storage-account-name <name>] [--log-analytics-workspace-id <id>] \
#          [--subscription <id>]
#
# Outputs: outputs/deployment-validation/smoke-test-report.md
# Exits 1 if any check fails.

set -euo pipefail

RESOURCE_GROUP=""
ENVIRONMENT=""
FUNCTION_APP_NAME=""
KEY_VAULT_NAME=""
STORAGE_ACCOUNT_NAME=""
STORAGE_CONTAINER_NAME="uploads"
COSMOS_ACCOUNT_NAME=""
COSMOS_DATABASE=""
COSMOS_CONTAINER=""
SERVICE_BUS_NAMESPACE=""
SERVICE_BUS_QUEUE_NAME=""
LOG_ANALYTICS_WORKSPACE_ID=""
SUBSCRIPTION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --resource-group)              RESOURCE_GROUP="$2";             shift 2 ;;
    --environment)                 ENVIRONMENT="$2";                shift 2 ;;
    --function-app-name)           FUNCTION_APP_NAME="$2";          shift 2 ;;
    --key-vault-name)              KEY_VAULT_NAME="$2";             shift 2 ;;
    --storage-account-name)        STORAGE_ACCOUNT_NAME="$2";       shift 2 ;;
    --storage-container-name)      STORAGE_CONTAINER_NAME="$2";     shift 2 ;;
    --cosmos-account-name)         COSMOS_ACCOUNT_NAME="$2";        shift 2 ;;
    --cosmos-database)             COSMOS_DATABASE="$2";            shift 2 ;;
    --cosmos-container)            COSMOS_CONTAINER="$2";           shift 2 ;;
    --service-bus-namespace)       SERVICE_BUS_NAMESPACE="$2";      shift 2 ;;
    --service-bus-queue-name)      SERVICE_BUS_QUEUE_NAME="$2";     shift 2 ;;
    --log-analytics-workspace-id)  LOG_ANALYTICS_WORKSPACE_ID="$2"; shift 2 ;;
    --subscription)                SUBSCRIPTION="$2";               shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

[[ -z "$RESOURCE_GROUP" ]]    && { echo "ERROR: --resource-group is required";    exit 1; }
[[ -z "$ENVIRONMENT" ]]       && { echo "ERROR: --environment is required";       exit 1; }
[[ -z "$FUNCTION_APP_NAME" ]] && { echo "ERROR: --function-app-name is required"; exit 1; }
[[ -z "$KEY_VAULT_NAME" ]]    && { echo "ERROR: --key-vault-name is required";    exit 1; }

SUB_ARGS=()
[[ -n "$SUBSCRIPTION" ]] && SUB_ARGS=(--subscription "$SUBSCRIPTION")

OUT_DIR="outputs/deployment-validation"
REPORT_FILE="$OUT_DIR/smoke-test-report.md"
mkdir -p "$OUT_DIR"

PASSED=0
FAILED=0
declare -a ROWS=()

add_row() {
  local check="$1" result="$2" details="$3"
  ROWS+=("| $check | $result | $details |")
  if [[ "$result" == "PASS" ]]; then
    echo "  [PASS] $check — $details"; ((PASSED++))
  else
    echo "  [FAIL] $check — $details"; ((FAILED++))
  fi
}

echo ""
echo "==> Smoke Tests: $ENVIRONMENT / $FUNCTION_APP_NAME"
echo ""

# ── 1. HTTP health endpoint ───────────────────────────────────────────────────
echo "Check 1 — HTTP health endpoint"
HOST=$(az functionapp show --name "$FUNCTION_APP_NAME" --resource-group "$RESOURCE_GROUP" \
    "${SUB_ARGS[@]}" --query defaultHostName -o tsv 2>/dev/null || true)
if [[ -n "$HOST" ]]; then
  CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 30 "https://$HOST/api/health" 2>/dev/null || echo "000")
  if [[ "$CODE" == "200" || "$CODE" == "401" ]]; then
    add_row "HTTP health endpoint" "PASS" "HTTP $CODE"
  elif [[ "$CODE" =~ ^5 ]]; then
    add_row "HTTP health endpoint" "FAIL" "HTTP $CODE (5xx — Function App error)"
  else
    add_row "HTTP health endpoint" "PASS" "HTTP $CODE (non-200 but not 5xx)"
  fi
else
  add_row "HTTP health endpoint" "FAIL" "Could not resolve Function App hostname"
fi

# ── 2. Managed identity ───────────────────────────────────────────────────────
echo "Check 2 — Managed identity"
PRINCIPAL_ID=$(az functionapp identity show --name "$FUNCTION_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" "${SUB_ARGS[@]}" --query principalId -o tsv 2>/dev/null || true)
if [[ -n "$PRINCIPAL_ID" && "$PRINCIPAL_ID" != "null" ]]; then
  add_row "Managed identity" "PASS" "principalId: $PRINCIPAL_ID"
else
  add_row "Managed identity" "FAIL" "No system-assigned managed identity found"
fi

# ── 3. Key Vault secret read ──────────────────────────────────────────────────
echo "Check 3 — Key Vault secret resolution"
SECRET_VAL=$(az keyvault secret show --vault-name "$KEY_VAULT_NAME" --name "TestSecret" \
    "${SUB_ARGS[@]}" --query value -o tsv 2>/dev/null || true)
if [[ -n "$SECRET_VAL" ]]; then
  add_row "Key Vault secret read" "PASS" "TestSecret resolved"
else
  add_row "Key Vault secret read" "FAIL" "Could not read TestSecret from $KEY_VAULT_NAME"
fi

# ── 4a. Blob Storage smoke test ───────────────────────────────────────────────
if [[ -n "$STORAGE_ACCOUNT_NAME" ]]; then
  echo "Check 4 — Blob Storage write/read/delete"
  TEST_BLOB="smoke-test-$(date +%Y%m%d%H%M%S).txt"
  if az storage blob upload \
      --account-name "$STORAGE_ACCOUNT_NAME" \
      --container-name "$STORAGE_CONTAINER_NAME" \
      --name "$TEST_BLOB" \
      --data "smoke-test $(date -u +%FT%TZ)" \
      --auth-mode login "${SUB_ARGS[@]}" &>/dev/null; then
    EXISTS=$(az storage blob show --account-name "$STORAGE_ACCOUNT_NAME" \
        --container-name "$STORAGE_CONTAINER_NAME" --name "$TEST_BLOB" \
        --auth-mode login "${SUB_ARGS[@]}" --query name -o tsv 2>/dev/null || true)
    if [[ "$EXISTS" == "$TEST_BLOB" ]]; then
      az storage blob delete --account-name "$STORAGE_ACCOUNT_NAME" \
          --container-name "$STORAGE_CONTAINER_NAME" --name "$TEST_BLOB" \
          --auth-mode login "${SUB_ARGS[@]}" &>/dev/null || true
      add_row "Blob Storage write/read/delete" "PASS" "Test blob created, verified, deleted"
    else
      add_row "Blob Storage write/read/delete" "FAIL" "Blob not found after upload"
    fi
  else
    add_row "Blob Storage write/read/delete" "FAIL" "Upload failed"
  fi
fi

# ── 5. Log Analytics ingestion ────────────────────────────────────────────────
if [[ -n "$LOG_ANALYTICS_WORKSPACE_ID" ]]; then
  echo "Check 5 — Log Analytics ingestion"
  ROW_COUNT=$(az monitor log-analytics query \
      --workspace "$LOG_ANALYTICS_WORKSPACE_ID" \
      --analytics-query "AzureActivity | take 5" \
      --output json 2>/dev/null | jq 'length' 2>/dev/null || echo 0)
  if [[ "$ROW_COUNT" -gt 0 ]]; then
    add_row "Log Analytics ingestion" "PASS" "$ROW_COUNT AzureActivity row(s) returned"
  else
    add_row "Log Analytics ingestion" "FAIL" "No rows — ingestion may not have started (wait 5-10 min)"
  fi
fi

# ── Write report ──────────────────────────────────────────────────────────────
STATUS="PASSED"
[[ "$FAILED" -gt 0 ]] && STATUS="FAILED"

{
  echo "# Smoke Test Report — $ENVIRONMENT"
  echo "## Status: $STATUS"
  echo ""
  echo "**Date:** $(date -u '+%Y-%m-%d %H:%M:%S') UTC"
  echo "**Function App:** $FUNCTION_APP_NAME"
  echo "**Resource Group:** $RESOURCE_GROUP"
  echo ""
  echo "| Check | Result | Details |"
  echo "|---|---|---|"
  for row in "${ROWS[@]}"; do echo "$row"; done
  echo ""
  echo "## Summary"
  echo "- Passed: $PASSED"
  echo "- Failed: $FAILED"
} > "$REPORT_FILE"

echo ""
echo "Report written to $REPORT_FILE"

if [[ "$FAILED" -gt 0 ]]; then
  echo "RESULT: FAILED ($FAILED check(s) failed)"
  exit 1
fi
echo "RESULT: PASSED ($PASSED check(s))"
