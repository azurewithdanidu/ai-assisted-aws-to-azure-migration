#!/usr/bin/env bats
# Unit tests for smoke-test.sh

SCRIPT="$BATS_TEST_DIRNAME/../../skills/smoke-testing/scripts/smoke-test.sh"

@test "smoke-test.sh exists" {
  [ -f "$SCRIPT" ]
}

@test "smoke-test.sh is executable" {
  [ -x "$SCRIPT" ]
}

@test "smoke-test.sh fails with no args" {
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
}

@test "smoke-test.sh fails without --function-app-name" {
  run bash "$SCRIPT" --resource-group myRG --environment dev --key-vault-name myKV
  [ "$status" -ne 0 ]
  [[ "$output" == *"function-app-name"* ]]
}

@test "smoke-test.sh fails without --key-vault-name" {
  run bash "$SCRIPT" --resource-group myRG --environment dev --function-app-name myFA
  [ "$status" -ne 0 ]
  [[ "$output" == *"key-vault-name"* ]]
}

@test "smoke-test.sh rejects unknown flags" {
  run bash "$SCRIPT" --nonsense true
  [ "$status" -ne 0 ]
}

@test "smoke-test.sh checks Key Vault in source" {
  grep -qi "keyvault\|key-vault\|KeyVault" "$SCRIPT"
}

@test "smoke-test.sh checks HTTP health in source" {
  grep -qi "http\|health\|curl" "$SCRIPT"
}
