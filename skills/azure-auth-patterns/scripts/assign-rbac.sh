#!/usr/bin/env bash
# Assign an Azure built-in RBAC role to a managed identity or principal.
# Usage: assign-rbac.sh --principal-id <id> --scope <resource-id> --role <name-or-guid> [--subscription <id>]
#
# Friendly role name shortcuts (same as PowerShell version):
#   StorageBlobDataContributor, StorageBlobDataReader, KeyVaultSecretsUser,
#   KeyVaultSecretsOfficer, ServiceBusDataSender, ServiceBusDataReceiver,
#   CosmosDBDataContributor, Contributor, Reader

set -euo pipefail

PRINCIPAL_ID=""
SCOPE=""
ROLE=""
SUBSCRIPTION=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --principal-id)  PRINCIPAL_ID="$2"; shift 2 ;;
    --scope)         SCOPE="$2";        shift 2 ;;
    --role)          ROLE="$2";         shift 2 ;;
    --subscription)  SUBSCRIPTION="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

[[ -z "$PRINCIPAL_ID" ]] && { echo "ERROR: --principal-id is required"; exit 1; }
[[ -z "$SCOPE" ]]        && { echo "ERROR: --scope is required";        exit 1; }
[[ -z "$ROLE" ]]         && { echo "ERROR: --role is required";         exit 1; }

# Map friendly names → built-in role GUIDs
declare -A ROLE_MAP=(
  [StorageBlobDataContributor]="ba92f5b4-2d11-453d-a403-e96b0029c9fe"
  [StorageBlobDataReader]="2a2b9908-6ea1-4ae2-8e65-a410df84e7d1"
  [KeyVaultSecretsUser]="4633458b-17de-408a-b874-0445c86b69e6"
  [KeyVaultSecretsOfficer]="b86a8fe4-44ce-4948-aee5-eccb2c155cd7"
  [ServiceBusDataSender]="69a216fc-b8fb-44d8-bc22-1f3c2cd27a39"
  [ServiceBusDataReceiver]="4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0"
  [CosmosDBDataContributor]="00000000-0000-0000-0000-000000000002"
  [Contributor]="b24988ac-6180-42a0-ab88-20f7382dd24c"
  [Reader]="acdd72a7-3385-48ef-bd42-f606fba81ae7"
)

RESOLVED_ROLE="${ROLE_MAP[$ROLE]:-$ROLE}"

SUB_ARGS=()
[[ -n "$SUBSCRIPTION" ]] && SUB_ARGS=(--subscription "$SUBSCRIPTION")

echo "==> Assigning role"
echo "    Role      : $ROLE ($RESOLVED_ROLE)"
echo "    Principal : $PRINCIPAL_ID"
echo "    Scope     : $SCOPE"

# Check if assignment already exists (idempotent)
EXISTING=$(az role assignment list \
    --assignee "$PRINCIPAL_ID" \
    --role "$RESOLVED_ROLE" \
    --scope "$SCOPE" \
    "${SUB_ARGS[@]}" \
    --query "[0].id" -o tsv 2>/dev/null || true)

if [[ -n "$EXISTING" ]]; then
  echo "    Already assigned — skipping (idempotent)"
  exit 0
fi

az role assignment create \
    --assignee "$PRINCIPAL_ID" \
    --role "$RESOLVED_ROLE" \
    --scope "$SCOPE" \
    "${SUB_ARGS[@]}" \
    --output none

echo "    Done"
