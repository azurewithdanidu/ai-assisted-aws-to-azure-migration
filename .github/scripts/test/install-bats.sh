#!/usr/bin/env bash
# Install bats-core and jq for Bash unit testing in CI
# Usage: bash install-bats.sh

set -euo pipefail

echo "Installing bats-core..."
if command -v apt-get &>/dev/null; then
  # Ubuntu/Debian (GitHub Actions ubuntu-latest)
  sudo apt-get update -qq
  sudo apt-get install -y --no-install-recommends bats
elif command -v brew &>/dev/null; then
  # macOS
  brew install bats-core
else
  # Fallback: clone and install from source
  git clone --depth 1 https://github.com/bats-core/bats-core.git /tmp/bats-core
  sudo /tmp/bats-core/install.sh /usr/local
  rm -rf /tmp/bats-core
fi

echo "Verifying bats..."
bats --version

# jq is pre-installed on ubuntu-latest runners, but install if missing
if ! command -v jq &>/dev/null; then
  echo "Installing jq..."
  if command -v apt-get &>/dev/null; then
    sudo apt-get install -y --no-install-recommends jq
  elif command -v brew &>/dev/null; then
    brew install jq
  fi
fi

echo "Verifying jq..."
jq --version

echo "✅ bats and jq ready"
