#!/usr/bin/env bash
# Run evals for a single skill suite.
# Usage: bash tests/evals/run-skill-eval.sh <skill-name> [model]

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: bash tests/evals/run-skill-eval.sh <skill-name> [model]"
  exit 1
fi

SKILL="$1"
MODEL="${2:-}"
EVAL_FILE="tests/evals/cloud-avengers/skills/${SKILL}/eval.yaml"

if [[ ! -f "$EVAL_FILE" ]]; then
  echo "❌ Skill eval file not found: $EVAL_FILE"
  exit 1
fi

ARGS=("$EVAL_FILE")
if [[ -n "$MODEL" ]]; then
  ARGS+=(--model "$MODEL")
fi

echo "Running eval for skill: $SKILL"
waza run "${ARGS[@]}"
