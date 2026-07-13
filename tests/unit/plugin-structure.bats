#!/usr/bin/env bats
# Structural validation tests for the plugin layout
# Ensures all required files exist and have valid content before merge

REPO_ROOT="$BATS_TEST_DIRNAME/../.."

@test "plugin.json exists and has required fields" {
  FILE="$REPO_ROOT/.claude-plugin/plugin.json"
  [ -f "$FILE" ]
  run bash -c "jq -e '.name and .version and .description and .author' '$FILE' > /dev/null 2>&1"
  [ "$status" -eq 0 ]
}

@test "plugin.json version matches semver format" {
  FILE="$REPO_ROOT/.claude-plugin/plugin.json"
  run bash -c "jq -r '.version' '$FILE' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$'"
  [ "$status" -eq 0 ]
}

@test "all 10 agent files exist" {
  for agent in \
    "aws-discovery.agent.md" \
    "azure-architect.agent.md" \
    "azure-deployer.agent.md" \
    "code-refactor.agent.md" \
    "deployment-validation.agent.md" \
    "iac-transformation.agent.md" \
    "migration-project-manager.agent.md" \
    "pipeline-builder-agent.agent.md" \
    "skill-evolution-engine.agent.md" \
    "skill-generator-agent.agent.md"; do
    [ -f "$REPO_ROOT/agents/$agent" ]
  done
}

@test "run-migration command exists and has agent field" {
  FILE="$REPO_ROOT/commands/run-migration.md"
  [ -f "$FILE" ]
  run grep -q "^agent:" "$FILE"
  [ "$status" -eq 0 ]
}

@test "all skill files are named SKILL.md" {
  FAIL=0
  while IFS= read -r f; do
    basename "$f" | grep -q "^SKILL\.md$" || { echo "WRONG NAME: $f"; FAIL=1; }
  done < <(find "$REPO_ROOT/skills" -name "*.md" ! -path "*/scripts/*")
  [ "$FAIL" -eq 0 ]
}

@test "all skill SKILL.md files have required frontmatter fields" {
  FAIL=0
  while IFS= read -r f; do
    for field in "name:" "description:"; do
      grep -q "^$field" "$f" || { echo "MISSING $field in $f"; FAIL=1; }
    done
  done < <(find "$REPO_ROOT/skills" -name "SKILL.md")
  [ "$FAIL" -eq 0 ]
}

@test "no stale .github/agents paths in agents/ files" {
  run bash -c "grep -r '\.github/agents' '$REPO_ROOT/agents/' 2>/dev/null || true"
  [ -z "$output" ]
}

@test "no stale .github/skills paths in agents/ files" {
  run bash -c "grep -r '\.github/skills' '$REPO_ROOT/agents/' 2>/dev/null || true"
  [ -z "$output" ]
}
