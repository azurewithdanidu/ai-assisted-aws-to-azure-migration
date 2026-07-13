#!/usr/bin/env bash
# Check that every changed skill file has at least one corresponding eval task
# Usage: bash tests/check-eval-coverage.sh
# Called by eval.yml on PRs to dev

set -euo pipefail

EVALS_DIR="tests/evals/aws-to-azure-migrator"
PASS=0
FAIL=0
MISSING=()

# Get changed skill files (relative to repo root)
CHANGED_SKILLS=$(git diff --name-only origin/dev...HEAD -- 'skills/**' 2>/dev/null || \
                 git diff --name-only HEAD~1 -- 'skills/**' 2>/dev/null || true)

if [[ -z "$CHANGED_SKILLS" ]]; then
  echo "No skill files changed — coverage check skipped"
  exit 0
fi

echo "Checking eval coverage for changed skills..."

while IFS= read -r skill_file; do
  # Extract skill name from path (skills/<skill-name>/SKILL.md)
  skill_name=$(echo "$skill_file" | cut -d'/' -f2)
  skill_group="$skill_name"

  # Look for an eval task tagged with this skill or group
  FOUND=$(grep -rl "skill:${skill_name}\|skill:${skill_group}\|agent:${skill_group}" \
    "$EVALS_DIR" 2>/dev/null | wc -l)

  if [[ "$FOUND" -gt 0 ]]; then
    echo "  ✅ $skill_file — eval coverage found"
    ((PASS++))
  else
    echo "  ⚠️  $skill_file — no eval task found (add a task tagged skill:${skill_name} or agent:${skill_group})"
    MISSING+=("$skill_file")
    ((FAIL++))
  fi
done <<< "$CHANGED_SKILLS"

echo ""
echo "Coverage: $PASS covered, $FAIL missing"

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo ""
  echo "Missing eval coverage for:"
  printf '  - %s\n' "${MISSING[@]}"
  echo ""
  echo "Add eval tasks in $EVALS_DIR/ tagged with the skill or agent name."
  echo "This is a warning only — not blocking merge."
fi
