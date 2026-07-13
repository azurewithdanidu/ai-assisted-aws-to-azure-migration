#!/usr/bin/env bash
# Run NVIDIA SkillSpector scan on the skills/ directory.
# Produces both JSON and SARIF output.
# Usage: run-skillspector-scan.sh
# Env vars consumed: SKILL_PATH, JSON_OUTPUT, SARIF_OUTPUT
#
# SkillSpector is assumed to already be installed in the current environment.
# The CI workflow installs it before calling this script.

set -euo pipefail

SKILL_PATH="${SKILL_PATH:-skills}"
JSON_OUTPUT="${JSON_OUTPUT:-skillspector.json}"
SARIF_OUTPUT="${SARIF_OUTPUT:-skillspector.sarif}"

echo "Running SkillSpector JSON scan on $SKILL_PATH..."
skillspector scan "$SKILL_PATH" \
  --format json \
  --output "$JSON_OUTPUT" \
  --no-llm

echo "Running SkillSpector SARIF scan on $SKILL_PATH..."
skillspector scan "$SKILL_PATH" \
  --format sarif \
  --output "$SARIF_OUTPUT" \
  --no-llm

echo "Scan complete. Outputs: $JSON_OUTPUT, $SARIF_OUTPUT"
