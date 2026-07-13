#!/usr/bin/env bash
# Run evals for all skill suites.
# Usage: bash tests/evals/run-all-skill-evals.sh [model]

set -euo pipefail

MODEL="${1:-}"

while IFS= read -r skill; do
  if [[ -n "$MODEL" ]]; then
    bash tests/evals/run-skill-eval.sh "$skill" "$MODEL"
  else
    bash tests/evals/run-skill-eval.sh "$skill"
  fi
done < <(ls -1 skills/*/SKILL.md | sed 's#skills/##;s#/SKILL.md##' | sort)
