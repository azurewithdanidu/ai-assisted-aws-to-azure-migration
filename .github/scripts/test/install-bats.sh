#!/usr/bin/env bash
# Install bats-core and jq for Bash unit testing in CI
# Usage: bash install-bats.sh

set -euo pipefail

echo "Installing bats-core..."
npm install -g bats

echo "Verifying bats..."
bats --version

echo "Installing jq..."
sudo apt-get install -y --no-install-recommends jq 2>/dev/null \
  || brew install jq 2>/dev/null \
  || echo "jq already available or install manually"

echo "Verifying jq..."
jq --version

echo "✅ bats and jq ready"
