#!/usr/bin/env bash
# Extract and validate the version from .claude-plugin/plugin.json
# Usage: extract-version.sh
# Outputs: VERSION env var written to $GITHUB_ENV (if in CI), and echoed to stdout
# Exits non-zero if version is invalid or tag already exists

set -euo pipefail

PLUGIN_JSON=".claude-plugin/plugin.json"

if [[ ! -f "$PLUGIN_JSON" ]]; then
  echo "ERROR: $PLUGIN_JSON not found"
  exit 1
fi

VERSION=$(jq -er '.version' "$PLUGIN_JSON")

# Validate semver (X.Y.Z only — no pre-release or build metadata)
if ! echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "ERROR: version '$VERSION' in $PLUGIN_JSON is not valid semver (expected X.Y.Z)"
  exit 1
fi

TAG="v${VERSION}"

# Check that the tag doesn't already exist
if git tag --list "$TAG" | grep -q "$TAG"; then
  echo "ERROR: tag $TAG already exists — bump the version in $PLUGIN_JSON before releasing"
  exit 1
fi

echo "VERSION=$VERSION"
echo "TAG=$TAG"

# Write to GITHUB_ENV if running in CI
if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "VERSION=$VERSION" >> "$GITHUB_ENV"
  echo "TAG=$TAG" >> "$GITHUB_ENV"
fi
