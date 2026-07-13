#!/usr/bin/env bash
# Check that scorecard.yaml has a one-to-one mapping with eval task IDs
# and required criteria fields for each mapped task.
# Usage: bash tests/check-eval-scorecard.sh

set -euo pipefail

TASK_DIR="tests/evals/cloud-avengers/tasks"
SCORECARD_FILE="tests/evals/cloud-avengers/scorecard.yaml"

if [[ ! -f "$SCORECARD_FILE" ]]; then
  echo "❌ Missing scorecard file: $SCORECARD_FILE"
  exit 1
fi

task_ids=$(find "$TASK_DIR" -type f -name '*.yaml' -print0 | \
  xargs -0 -r grep -hs '^id:' | sed 's/^id:[[:space:]]*//' | sort -u)
scorecard_ids=$(grep -E '^[[:space:]]+- task_id:' "$SCORECARD_FILE" | sed 's/^[[:space:]]*- task_id:[[:space:]]*//' | sort -u)

if [[ -z "$task_ids" ]]; then
  echo "❌ No eval task IDs found under $TASK_DIR"
  exit 1
fi

if [[ -z "$scorecard_ids" ]]; then
  echo "❌ No task_scorecard entries found in $SCORECARD_FILE"
  exit 1
fi

missing_in_scorecard=$(comm -23 <(printf '%s\n' "$task_ids") <(printf '%s\n' "$scorecard_ids") || true)
extra_in_scorecard=$(comm -13 <(printf '%s\n' "$task_ids") <(printf '%s\n' "$scorecard_ids") || true)

if [[ -n "$missing_in_scorecard" ]]; then
  echo "❌ Missing task_scorecard entries for:"
  printf '  - %s\n' $missing_in_scorecard
  exit 1
fi

if [[ -n "$extra_in_scorecard" ]]; then
  echo "❌ task_scorecard has entries not present in eval tasks:"
  printf '  - %s\n' $extra_in_scorecard
  exit 1
fi

awk '
  BEGIN {
    in_task = 0
    has_owner_type = 0
    has_owner_id = 0
    has_metric = 0
    has_expected = 0
    has_target = 0
  }
  /^[[:space:]]+- task_id:/ {
    if (in_task == 1 && (!has_owner_type || !has_owner_id || !has_metric || !has_expected || !has_target)) {
      print "❌ Incomplete criteria mapping near previous task_id entry"
      exit 1
    }
    in_task = 1
    has_owner_type = 0
    has_owner_id = 0
    has_metric = 0
    has_expected = 0
    has_target = 0
  }
  in_task == 1 && /^[[:space:]]+owner_type:/ { has_owner_type = 1 }
  in_task == 1 && /^[[:space:]]+owner_id:/ { has_owner_id = 1 }
  in_task == 1 && /^[[:space:]]+metric:/ { has_metric = 1 }
  in_task == 1 && /^[[:space:]]+expected_outcome:/ { has_expected = 1 }
  in_task == 1 && /^[[:space:]]+target:/ { has_target = 1 }
  END {
    if (in_task == 1 && (!has_owner_type || !has_owner_id || !has_metric || !has_expected || !has_target)) {
      print "❌ Incomplete criteria mapping near final task_id entry"
      exit 1
    }
    print "✅ Scorecard 1:1 mapping and required criteria fields are valid"
  }
' "$SCORECARD_FILE"
