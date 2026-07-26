#!/usr/bin/env bash
# Create an annotated git tag and GitHub Release for the current version
# Usage: create-tag-and-release.sh <VERSION> <RELEASE_BODY_FILE>
# Requires: gh CLI authenticated, GH_TOKEN or GITHUB_TOKEN in env

set -euo pipefail

VERSION="${1:-}"
RELEASE_BODY_FILE="${2:-/tmp/release-body.md}"

if [[ -z "$VERSION" ]]; then
  echo "ERROR: version argument required (e.g. 1.0.0)"
  exit 1
fi

if [[ ! -f "$RELEASE_BODY_FILE" ]]; then
  echo "ERROR: release body file not found: $RELEASE_BODY_FILE"
  exit 1
fi

TAG="v${VERSION}"

echo "Creating annotated git tag $TAG..."
git config user.name  "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"
git tag -a "$TAG" -m "Release $TAG"
git push origin "$TAG"

echo "Creating GitHub Release $TAG..."
gh release create "$TAG" \
  --title "Release $TAG" \
  --notes-file "$RELEASE_BODY_FILE" \
  --latest

echo "✅ Released $TAG"
