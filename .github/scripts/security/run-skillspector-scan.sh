#!/usr/bin/env bash
# Run NVIDIA SkillSpector scan on the skills/ directory
# Produces both JSON and SARIF output
# Usage: run-skillspector-scan.sh
# Env vars required: SKILL_PATH, SKILLSPECTOR_REF, JSON_OUTPUT, SARIF_OUTPUT

set -euo pipefail

SKILL_PATH="${SKILL_PATH:-skills}"
SKILLSPECTOR_REF="${SKILLSPECTOR_REF:-2eb844780ab163f01468ecf142c40a2ec0fcaec0}"
JSON_OUTPUT="${JSON_OUTPUT:-skillspector.json}"
SARIF_OUTPUT="${SARIF_OUTPUT:-skillspector.sarif}"

echo "Installing SkillSpector (ref: $SKILLSPECTOR_REF)..."
python -m pip install --quiet \
  "git+https://github.com/NVIDIA/skillspector@${SKILLSPECTOR_REF}"

echo "Running SkillSpector JSON scan on $SKILL_PATH..."
python -m skillspector scan \
  --path "$SKILL_PATH" \
  --output-format json \
  --output-file "$JSON_OUTPUT" || true

echo "Running SkillSpector SARIF scan on $SKILL_PATH..."
python -m skillspector scan \
  --path "$SKILL_PATH" \
  --output-format sarif \
  --output-file "$SARIF_OUTPUT" || true

echo "Scan complete. Outputs: $JSON_OUTPUT, $SARIF_OUTPUT"
