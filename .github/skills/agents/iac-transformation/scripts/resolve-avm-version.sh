#!/usr/bin/env bash
# resolve-avm-version.sh — Fetch the latest published version for an AVM Bicep module.
#
# Usage:   ./resolve-avm-version.sh <module-path>
# Example: ./resolve-avm-version.sh storage/storage-account
#          ./resolve-avm-version.sh web/site
#
# Output:  Prints the latest version tag, e.g. "0.32.0"
# Exit 0 on success, exit 1 on network error or missing module.

set -euo pipefail

MODULE="${1:?Usage: $0 <module-path> (e.g. storage/storage-account)}"

CHANGELOG_URL="https://raw.githubusercontent.com/Azure/bicep-registry-modules/main/avm/res/${MODULE}/CHANGELOG.md"

echo "Fetching CHANGELOG for avm/res/${MODULE} ..." >&2

CONTENT=$(curl -fsSL "${CHANGELOG_URL}" 2>/dev/null) || {
  echo "ERROR: Could not fetch ${CHANGELOG_URL}" >&2
  echo "  Check the module path is correct:  https://github.com/Azure/bicep-registry-modules/tree/main/avm/res" >&2
  exit 1
}

# Extract the first ## X.Y.Z heading
VERSION=$(echo "${CONTENT}" | grep -m1 -oP '(?<=^## )\d+\.\d+\.\d+')

if [[ -z "${VERSION}" ]]; then
  echo "ERROR: No version heading found in CHANGELOG for ${MODULE}" >&2
  exit 1
fi

echo "${VERSION}"
