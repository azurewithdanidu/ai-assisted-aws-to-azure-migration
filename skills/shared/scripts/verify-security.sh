#!/usr/bin/env bash
# Post-deployment security verification for a migrated Azure environment.
# Usage: verify-security.sh --resource-group <rg> [--subscription <id>]
#          [--storage-account-name <name>] [--key-vault-name <name>] [--function-app-name <name>]
#
# Outputs: outputs/deployment-validation/security-report.md
# Exits 1 if any FAIL result is found (WARN does not block).

set -euo pipefail

RESOURCE_GROUP=""
SUBSCRIPTION=""
STORAGE_ACCOUNT_NAME=""
KEY_VAULT_NAME=""
FUNCTION_APP_NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --resource-group)       RESOURCE_GROUP="$2";       shift 2 ;;
    --subscription)         SUBSCRIPTION="$2";         shift 2 ;;
    --storage-account-name) STORAGE_ACCOUNT_NAME="$2"; shift 2 ;;
    --key-vault-name)       KEY_VAULT_NAME="$2";       shift 2 ;;
    --function-app-name)    FUNCTION_APP_NAME="$2";    shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

[[ -z "$RESOURCE_GROUP" ]] && { echo "ERROR: --resource-group is required"; exit 1; }

SUB_ARGS=()
[[ -n "$SUBSCRIPTION" ]] && SUB_ARGS=(--subscription "$SUBSCRIPTION")

OUT_DIR="outputs/deployment-validation"
REPORT_FILE="$OUT_DIR/security-report.md"
mkdir -p "$OUT_DIR"

PASSED=0; FAILED=0; WARNINGS=0
declare -a ROWS=()

add_row() {
  local check="$1" result="$2" details="$3"
  ROWS+=("| $check | $result | $details |")
  case "$result" in
    PASS) echo "  [PASS] $check — $details"; ((PASSED++))  ;;
    FAIL) echo "  [FAIL] $check — $details"; ((FAILED++))  ;;
    WARN) echo "  [WARN] $check — $details"; ((WARNINGS++)) ;;
  esac
}

echo ""
echo "==> Security Verification: $RESOURCE_GROUP"
echo ""

# ── Auto-discover resources if not provided ───────────────────────────────────
if [[ -z "$STORAGE_ACCOUNT_NAME" ]]; then
  STORAGE_ACCOUNT_NAME=$(az storage account list --resource-group "$RESOURCE_GROUP" \
    "${SUB_ARGS[@]}" --query "[0].name" -o tsv 2>/dev/null || true)
  [[ -n "$STORAGE_ACCOUNT_NAME" ]] && echo "    [auto] Storage: $STORAGE_ACCOUNT_NAME"
fi
if [[ -z "$KEY_VAULT_NAME" ]]; then
  KEY_VAULT_NAME=$(az keyvault list --resource-group "$RESOURCE_GROUP" \
    "${SUB_ARGS[@]}" --query "[0].name" -o tsv 2>/dev/null || true)
  [[ -n "$KEY_VAULT_NAME" ]] && echo "    [auto] Key Vault: $KEY_VAULT_NAME"
fi
if [[ -z "$FUNCTION_APP_NAME" ]]; then
  FUNCTION_APP_NAME=$(az functionapp list --resource-group "$RESOURCE_GROUP" \
    "${SUB_ARGS[@]}" --query "[0].name" -o tsv 2>/dev/null || true)
  [[ -n "$FUNCTION_APP_NAME" ]] && echo "    [auto] Function App: $FUNCTION_APP_NAME"
fi

# ── Storage Account ────────────────────────────────────────────────────────────
if [[ -n "$STORAGE_ACCOUNT_NAME" ]]; then
  echo ""
  echo "Storage Account: $STORAGE_ACCOUNT_NAME"
  STOR=$(az storage account show --name "$STORAGE_ACCOUNT_NAME" \
    --resource-group "$RESOURCE_GROUP" "${SUB_ARGS[@]}" -o json 2>/dev/null || echo "{}")

  PNA=$(echo "$STOR" | jq -r '.publicNetworkAccess // "unknown"')
  [[ "$PNA" == "Disabled" ]] \
    && add_row "Storage publicNetworkAccess"          "PASS" "Disabled" \
    || add_row "Storage publicNetworkAccess"          "FAIL" "Value='$PNA' — must be Disabled"

  BPA=$(echo "$STOR" | jq -r '.allowBlobPublicAccess // "unknown"')
  [[ "$BPA" == "false" ]] \
    && add_row "Storage allowBlobPublicAccess"        "PASS" "false" \
    || add_row "Storage allowBlobPublicAccess"        "FAIL" "Value='$BPA' — must be false"

  RIE=$(echo "$STOR" | jq -r '.encryption.requireInfrastructureEncryption // "false"')
  [[ "$RIE" == "true" ]] \
    && add_row "Storage requireInfrastructureEncryption" "PASS" "true" \
    || add_row "Storage requireInfrastructureEncryption" "WARN" "false — enable for regulated workloads"

  HTTPS=$(echo "$STOR" | jq -r '.supportsHttpsTrafficOnly // "false"')
  [[ "$HTTPS" == "true" ]] \
    && add_row "Storage supportsHttpsTrafficOnly"     "PASS" "true" \
    || add_row "Storage supportsHttpsTrafficOnly"     "FAIL" "false — HTTP traffic allowed"
else
  add_row "Storage checks" "WARN" "No storage account found in $RESOURCE_GROUP — skipped"
fi

# ── Key Vault ──────────────────────────────────────────────────────────────────
if [[ -n "$KEY_VAULT_NAME" ]]; then
  echo ""
  echo "Key Vault: $KEY_VAULT_NAME"
  KV=$(az keyvault show --name "$KEY_VAULT_NAME" \
    --resource-group "$RESOURCE_GROUP" "${SUB_ARGS[@]}" -o json 2>/dev/null || echo "{}")

  KV_PNA=$(echo "$KV" | jq -r '.properties.publicNetworkAccess // "unknown"')
  [[ "$KV_PNA" == "Disabled" ]] \
    && add_row "Key Vault publicNetworkAccess"   "PASS" "Disabled" \
    || add_row "Key Vault publicNetworkAccess"   "FAIL" "Value='$KV_PNA' — must be Disabled"

  SD=$(echo "$KV" | jq -r '.properties.enableSoftDelete // "false"')
  [[ "$SD" == "true" ]] \
    && add_row "Key Vault softDelete"            "PASS" "enabled" \
    || add_row "Key Vault softDelete"            "FAIL" "disabled"

  PP=$(echo "$KV" | jq -r '.properties.enablePurgeProtection // "false"')
  [[ "$PP" == "true" ]] \
    && add_row "Key Vault purgeProtection"       "PASS" "enabled" \
    || add_row "Key Vault purgeProtection"       "FAIL" "disabled"

  RBAC=$(echo "$KV" | jq -r '.properties.enableRbacAuthorization // "false"')
  [[ "$RBAC" == "true" ]] \
    && add_row "Key Vault enableRbacAuthorization" "PASS" "true" \
    || add_row "Key Vault enableRbacAuthorization" "WARN" "false — using access policies instead of RBAC"
else
  add_row "Key Vault checks" "WARN" "No key vault found in $RESOURCE_GROUP — skipped"
fi

# ── Function App ───────────────────────────────────────────────────────────────
if [[ -n "$FUNCTION_APP_NAME" ]]; then
  echo ""
  echo "Function App: $FUNCTION_APP_NAME"
  FA=$(az functionapp show --name "$FUNCTION_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" "${SUB_ARGS[@]}" -o json 2>/dev/null || echo "{}")

  HTTPS_ONLY=$(echo "$FA" | jq -r '.httpsOnly // "false"')
  [[ "$HTTPS_ONLY" == "true" ]] \
    && add_row "Function App httpsOnly"        "PASS" "true" \
    || add_row "Function App httpsOnly"        "FAIL" "false — HTTP allowed"

  TLS=$(az functionapp config show --name "$FUNCTION_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" "${SUB_ARGS[@]}" \
    --query minTlsVersion -o tsv 2>/dev/null || echo "unknown")
  [[ "$TLS" == "1.2" || "$TLS" == "1.3" ]] \
    && add_row "Function App minTlsVersion"    "PASS" "$TLS" \
    || add_row "Function App minTlsVersion"    "FAIL" "Value='$TLS' — must be 1.2 or higher"

  VNET_ID=$(echo "$FA" | jq -r '.virtualNetworkSubnetId // ""')
  [[ -n "$VNET_ID" ]] \
    && add_row "Function App VNet integration" "PASS" "Integrated: $VNET_ID" \
    || add_row "Function App VNet integration" "WARN" "Not VNet-integrated — outbound traffic is public"
else
  add_row "Function App checks" "WARN" "No function app found in $RESOURCE_GROUP — skipped"
fi

# ── NSG Rules ──────────────────────────────────────────────────────────────────
echo ""
echo "NSG Rules"
NSG_LIST=$(az network nsg list --resource-group "$RESOURCE_GROUP" \
    "${SUB_ARGS[@]}" -o json 2>/dev/null || echo "[]")
NSG_COUNT=$(echo "$NSG_LIST" | jq 'length')

if [[ "$NSG_COUNT" -gt 0 ]]; then
  while IFS= read -r nsg_name; do
    DANGEROUS=$(echo "$NSG_LIST" | jq -r \
      --arg name "$nsg_name" \
      '[.[] | select(.name==$name) | .securityRules[]? |
        select(.access=="Allow" and .direction=="Inbound") |
        select(.destinationPortRange=="*" or .sourceAddressPrefix=="*")] | length')
    if [[ "$DANGEROUS" -gt 0 ]]; then
      add_row "NSG $nsg_name" "FAIL" "Has Allow-Any-Inbound rule(s)"
    else
      add_row "NSG $nsg_name" "PASS" "No overly-permissive inbound rules"
    fi
  done < <(echo "$NSG_LIST" | jq -r '.[].name')
else
  add_row "NSG checks" "WARN" "No NSGs found in $RESOURCE_GROUP — skipped"
fi

# ── Write report ───────────────────────────────────────────────────────────────
STATUS="PASSED"
[[ "$FAILED" -gt 0 ]] && STATUS="FAILED"

{
  echo "# Security Verification Report"
  echo "## Status: $STATUS"
  echo ""
  echo "**Date:** $(date -u '+%Y-%m-%d %H:%M:%S')"
  echo "**Resource Group:** $RESOURCE_GROUP"
  echo ""
  echo "| Check | Result | Details |"
  echo "|---|---|---|"
  for row in "${ROWS[@]}"; do echo "$row"; done
  echo ""
  echo "## Summary"
  echo "- Passed:   $PASSED"
  echo "- Failed:   $FAILED"
  echo "- Warnings: $WARNINGS"
  echo ""
  echo "## References"
  echo "- https://learn.microsoft.com/en-us/azure/security/fundamentals/best-practices-and-patterns"
  echo "- https://learn.microsoft.com/en-us/azure/storage/common/storage-network-security"
  echo "- https://learn.microsoft.com/en-us/azure/key-vault/general/security-features"
} > "$REPORT_FILE"

echo ""
echo "Report written to $REPORT_FILE"

if [[ "$FAILED" -gt 0 ]]; then
  echo "RESULT: FAILED ($FAILED check(s) failed)"
  exit 1
fi
echo "RESULT: PASSED ($PASSED passed, $WARNINGS warning(s))"
