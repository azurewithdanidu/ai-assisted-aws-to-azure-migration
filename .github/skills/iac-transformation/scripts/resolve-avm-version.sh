#!/usr/bin/env bash
# resolve-avm-version.sh — Fetch the latest published version of an AVM Bicep module.
#
# Usage:
#   ./resolve-avm-version.sh <provider>/<module>
#   ./resolve-avm-version.sh storage/storage-account
#   ./resolve-avm-version.sh web/site
#   ./resolve-avm-version.sh network/virtual-network
#
# For pattern modules prefix with ptn/:
#   ./resolve-avm-version.sh ptn/network/hub-networking
#
# Output:
#   Prints the latest version string, e.g. "0.32.0"
#   Exits 1 if the module is not found or CHANGELOG is unreachable.

set -euo pipefail

MODULE_PATH="${1:-}"

if [[ -z "$MODULE_PATH" ]]; then
  echo "Usage: $0 <provider>/<module>" >&2
  echo "       $0 storage/storage-account" >&2
  echo "       $0 ptn/network/hub-networking" >&2
  exit 1
fi

# Determine whether this is a res/ or ptn/ module
if [[ "$MODULE_PATH" == ptn/* ]]; then
  # Pattern module — path already includes ptn/
  RAW_PATH="$MODULE_PATH"
else
  # Resource module — prepend res/
  RAW_PATH="res/$MODULE_PATH"
fi

CHANGELOG_URL="https://raw.githubusercontent.com/Azure/bicep-registry-modules/main/avm/${RAW_PATH}/CHANGELOG.md"

echo "Fetching CHANGELOG: $CHANGELOG_URL" >&2

CHANGELOG=$(curl -fsSL "$CHANGELOG_URL" 2>/dev/null) || {
  echo "ERROR: Could not fetch CHANGELOG for avm/${RAW_PATH}" >&2
  echo "       Verify module path at: https://azure.github.io/Azure-Verified-Modules/indexes/bicep/" >&2
  exit 1
}

# Extract the first semantic version header from the CHANGELOG
# CHANGELOGs use headings like: ## 0.32.0 (2024-11-01) or ## [0.32.0]
LATEST=$(echo "$CHANGELOG" | grep -oE '## \[?[0-9]+\.[0-9]+\.[0-9]+\]?' | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')

if [[ -z "$LATEST" ]]; then
  echo "ERROR: Could not parse version from CHANGELOG for avm/${RAW_PATH}" >&2
  echo "       CHANGELOG content (first 20 lines):" >&2
  echo "$CHANGELOG" | head -20 >&2
  exit 1
fi

echo "$LATEST"

echo "" >&2
echo "Bicep reference:" >&2
echo "  'br/public:avm/${RAW_PATH}:${LATEST}'" >&2
