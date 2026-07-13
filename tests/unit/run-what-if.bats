#!/usr/bin/env bats
# Unit tests for run-what-if.sh

SCRIPT="$BATS_TEST_DIRNAME/../../skills/what-if-validation/scripts/run-what-if.sh"

@test "run-what-if.sh exists" {
  [ -f "$SCRIPT" ]
}

@test "run-what-if.sh is executable" {
  [ -x "$SCRIPT" ]
}

@test "run-what-if.sh fails with no args" {
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
}

@test "run-what-if.sh fails without --resource-group" {
  run bash "$SCRIPT" --environment dev
  [ "$status" -ne 0 ]
  [[ "$output" == *"resource-group"* ]]
}

@test "run-what-if.sh fails without --environment" {
  run bash "$SCRIPT" --resource-group myRG
  [ "$status" -ne 0 ]
  [[ "$output" == *"environment"* ]]
}

@test "run-what-if.sh rejects invalid --environment value" {
  run bash "$SCRIPT" --resource-group myRG --environment production
  [ "$status" -ne 0 ]
  [[ "$output" == *"dev, staging, or prod"* ]]
}

@test "run-what-if.sh rejects unknown flags" {
  run bash "$SCRIPT" --unknown-flag value
  [ "$status" -ne 0 ]
}

@test "run-what-if.sh references outputs/deployment-validation in source" {
  grep -q "outputs/deployment-validation" "$SCRIPT"
}
