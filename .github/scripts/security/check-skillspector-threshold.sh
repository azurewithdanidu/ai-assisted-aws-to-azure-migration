#!/usr/bin/env bash
# Gate script: block merge if SkillSpector found HIGH or CRITICAL severity findings
# Usage: check-skillspector-threshold.sh <JSON_OUTPUT_FILE>
# Exits 1 (blocking) if HIGH or CRITICAL findings found; exits 0 otherwise

set -euo pipefail

JSON_FILE="${1:-${JSON_OUTPUT:-skillspector.json}}"
FAIL_ON="${SKILLSPECTOR_FAIL_ON:-HIGH,CRITICAL}"

if [[ ! -f "$JSON_FILE" ]]; then
  echo "ERROR: SkillSpector JSON output not found: $JSON_FILE"
  exit 1
fi

echo "Checking SkillSpector results against threshold: $FAIL_ON"

# Convert comma-separated fail levels to jq array filter
SEVERITIES=$(echo "$FAIL_ON" | tr ',' '\n' | jq -R . | jq -s .)

BLOCKED_COUNT=$(jq --argjson sevs "$SEVERITIES" \
  '[.findings[]? | select(.severity as $s | $sevs | index($s) != null)] | length' \
  "$JSON_FILE" 2>/dev/null || echo "0")

if [[ "$BLOCKED_COUNT" -gt 0 ]]; then
  echo ""
  echo "❌ SkillSpector gate FAILED: $BLOCKED_COUNT finding(s) at or above threshold ($FAIL_ON)"
  echo ""
  # Print the blocking findings
  jq --argjson sevs "$SEVERITIES" \
    '.findings[]? | select(.severity as $s | $sevs | index($s) != null) | "[\(.severity)] \(.rule_id // .check_id // "unknown"): \(.message // .description // "")"' \
    -r "$JSON_FILE" 2>/dev/null || true
  echo ""
  echo "Fix the above findings before merging. See the SARIF report for full details."
  exit 1
fi

echo "✅ SkillSpector gate PASSED: no HIGH or CRITICAL findings"
