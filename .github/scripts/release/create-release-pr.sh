#!/usr/bin/env bash
# Create a release PR from the version branch → main when a version: PR merges to main
# Usage: create-release-pr.sh
# Requires: GH_TOKEN env var; run from repo root on main branch

set -euo pipefail

PLUGIN_JSON=".claude-plugin/plugin.json"
VERSION=$(jq -er '.version' "$PLUGIN_JSON")
TAG="v${VERSION}"

echo "Preparing release PR for $TAG..."

# Check tag doesn't already exist
if git ls-remote --tags origin "$TAG" | grep -q "$TAG"; then
  echo "Tag $TAG already exists on origin — skipping release PR creation"
  exit 0
fi

# Check release PR doesn't already exist
EXISTING=$(gh pr list --state open --label release --json title --jq ".[].title" | grep "release: $TAG" || true)
if [[ -n "$EXISTING" ]]; then
  echo "Release PR for $TAG already open — skipping"
  exit 0
fi

# Extract changelog section for the PR body
bash "$(dirname "$0")/extract-changelog.sh" "$VERSION"
CHANGELOG_SECTION=$(cat /tmp/release-body.md)

PR_BODY_CONTENT="## Release $TAG

$CHANGELOG_SECTION

---
*This PR was created automatically. Merging it to \`main\` will tag and publish the release.*"

gh pr create \
  --base main \
  --head "version/$VERSION" \
  --title "release: $TAG" \
  --body "$PR_BODY_CONTENT" \
  --label "release"

echo "✅ Release PR created: release: $TAG (version/$VERSION → main)"
