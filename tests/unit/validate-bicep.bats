#!/usr/bin/env bats
# Unit tests for validate-bicep.sh

SCRIPT="$BATS_TEST_DIRNAME/../../skills/iac-transformation/scripts/validate-bicep.sh"

@test "validate-bicep.sh exists" {
  [ -f "$SCRIPT" ]
}

@test "validate-bicep.sh is executable" {
  [ -x "$SCRIPT" ]
}

@test "validate-bicep.sh fails when main.bicep is not found" {
  run bash "$SCRIPT" --bicep-root /nonexistent/path
  [ "$status" -ne 0 ]
  [[ "$output" == *"main.bicep not found"* ]]
}

@test "validate-bicep.sh rejects unknown flags" {
  run bash "$SCRIPT" --weird-flag
  [ "$status" -ne 0 ]
}

@test "validate-bicep.sh calls az bicep restore in source" {
  grep -q "bicep restore" "$SCRIPT"
}

@test "validate-bicep.sh calls az bicep build in source" {
  grep -q "bicep build" "$SCRIPT"
}

@test "validate-bicep.sh skips what-if when no resource-group is given" {
  grep -q "resource-group.*not supplied.*skipping what-if" "$SCRIPT"
}
