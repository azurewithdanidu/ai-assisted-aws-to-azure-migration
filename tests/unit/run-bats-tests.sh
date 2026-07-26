#!/usr/bin/env bash
# Run all bats tests for Bash skill scripts
# Usage: bash run-bats-tests.sh

set -euo pipefail

TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0

echo "Running bats tests..."
for test_file in "$TESTS_DIR"/*.bats; do
  if [[ -f "$test_file" ]]; then
    if bats "$test_file"; then
      PASS=$((PASS + 1))
    else
      FAIL=$((FAIL + 1))
    fi
  fi
done

echo ""
if [[ $FAIL -gt 0 ]]; then
  echo "❌ $FAIL bats test file(s) failed (passed: $PASS)"
  exit 1
fi

echo "✅ All $PASS bats test file(s) passed"
