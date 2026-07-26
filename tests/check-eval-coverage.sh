#!/usr/bin/env bash
# Check that every changed skill/agent file has at least one corresponding eval task
# Usage: bash tests/check-eval-coverage.sh
# Called by eval.yml on PRs to dev

set -euo pipefail

EVALS_DIR="tests/evals/cloud-avengers"
PASS=0
FAIL=0
MISSING=()

# Get changed SKILL.md files only (not scripts) relative to repo root
CHANGED_SKILLS=$(git diff --name-only origin/dev...HEAD -- 'skills/**/SKILL.md' 2>/dev/null || \
                 git diff --name-only HEAD~1 -- 'skills/**/SKILL.md' 2>/dev/null || true)
CHANGED_AGENTS=$(git diff --name-only origin/dev...HEAD -- 'agents/*.agent.md' 2>/dev/null || \
                 git diff --name-only HEAD~1 -- 'agents/*.agent.md' 2>/dev/null || true)

if [[ -z "$CHANGED_SKILLS" && -z "$CHANGED_AGENTS" ]]; then
  echo "No skill/agent files changed — coverage check skipped"
  exit 0
fi

echo "Checking eval coverage for changed skills/agents..."

while IFS= read -r skill_file; do
  [[ -z "$skill_file" ]] && continue
  # Extract skill name from path (skills/<skill-name>/SKILL.md)
  skill_name=$(echo "$skill_file" | cut -d'/' -f2)

  # Look for an eval task tagged with this skill
  FOUND=$(grep -RIl -- "skill:${skill_name}" "$EVALS_DIR" 2>/dev/null | wc -l)

  if [[ "$FOUND" -gt 0 ]]; then
    echo "  ✅ $skill_file — eval coverage found"
    ((PASS++))
  else
    echo "  ⚠️  $skill_file — no eval task found (add a task tagged skill:${skill_name})"
    MISSING+=("$skill_file")
    ((FAIL++))
  fi
done <<< "$CHANGED_SKILLS"

while IFS= read -r agent_file; do
  [[ -z "$agent_file" ]] && continue
  # Extract agent name from path (agents/<agent-name>.agent.md)
  agent_name=$(basename "$agent_file" .agent.md)

  # Look for an eval task tagged with this agent
  FOUND=$(grep -RIl -- "agent:${agent_name}" "$EVALS_DIR" 2>/dev/null | wc -l)

  if [[ "$FOUND" -gt 0 ]]; then
    echo "  ✅ $agent_file — eval coverage found"
    ((PASS++))
  else
    echo "  ⚠️  $agent_file — no eval task found (add a task tagged agent:${agent_name})"
    MISSING+=("$agent_file")
    ((FAIL++))
  fi
done <<< "$CHANGED_AGENTS"

echo ""
echo "Coverage: $PASS covered, $FAIL missing"

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo ""
  echo "Missing eval coverage for:"
  printf '  - %s\n' "${MISSING[@]}"
  echo ""
  echo "Add eval tasks in $EVALS_DIR/ tagged with skill:<skill-name> or agent:<agent-name>."
  echo "This is a warning only — not blocking merge."
fi
