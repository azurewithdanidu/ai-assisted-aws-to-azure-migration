#!/usr/bin/env bash
# Extract the changelog section matching the current version and write to /tmp/release-body.md
# Usage: extract-changelog.sh <VERSION>
# Expects VERSION like "1.0.0" (without the v prefix)

set -euo pipefail

VERSION="${1:-}"

if [[ -z "$VERSION" ]]; then
  echo "ERROR: version argument required (e.g. 1.0.0)"
  exit 1
fi

CHANGELOG="CHANGELOG.md"

if [[ ! -f "$CHANGELOG" ]]; then
  echo "ERROR: $CHANGELOG not found"
  exit 1
fi

OUTPUT="/tmp/release-body.md"

# Extract the block between ## [VERSION] and the next ## [
awk -v ver="$VERSION" '
  /^## \['"$VERSION"'\]/ { found=1; next }
  found && /^## \[/ { exit }
  found { print }
' "$CHANGELOG" > "$OUTPUT"

if [[ ! -s "$OUTPUT" ]]; then
  echo "ERROR: No changelog entry found for version $VERSION in $CHANGELOG"
  echo "Add a '## [$VERSION]' section to $CHANGELOG before releasing"
  exit 1
fi

echo "Extracted changelog for v$VERSION → $OUTPUT"
cat "$OUTPUT"
