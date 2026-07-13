#!/usr/bin/env bash
# Run NVIDIA SkillSpector scan on the skills/ directory.
# Produces both JSON and SARIF output.
# Usage: run-skillspector-scan.sh
# Env vars consumed: SKILL_PATH, JSON_OUTPUT, SARIF_OUTPUT
#
# SkillSpector exits 1 when it finds security findings — that is its normal
# behavior. The threshold gate is handled by check-skillspector-threshold.sh.
# This script exits non-zero only if SkillSpector failed to produce output.

set -uo pipefail   # intentionally no -e: scanner exits 1 on findings

SKILL_PATH="${SKILL_PATH:-skills}"
JSON_OUTPUT="${JSON_OUTPUT:-skillspector.json}"
SARIF_OUTPUT="${SARIF_OUTPUT:-skillspector.sarif}"

echo "Running SkillSpector JSON scan on $SKILL_PATH..."
skillspector scan "$SKILL_PATH" \
  --format json \
  --output "$JSON_OUTPUT" \
  --no-llm || true   # exit 1 on findings is expected; file is still written

if [[ ! -f "$JSON_OUTPUT" ]]; then
  echo "ERROR: SkillSpector failed to produce JSON output — check install and flags"
  exit 1
fi
echo "  JSON report: $JSON_OUTPUT"

echo "Running SkillSpector SARIF scan on $SKILL_PATH..."
skillspector scan "$SKILL_PATH" \
  --format sarif \
  --output "$SARIF_OUTPUT" \
  --no-llm || true

if [[ -f "$SARIF_OUTPUT" ]]; then
  echo "  SARIF report: $SARIF_OUTPUT"
else
  echo "  WARN: SARIF output not produced (non-blocking)"
fi

echo "Scan complete."
