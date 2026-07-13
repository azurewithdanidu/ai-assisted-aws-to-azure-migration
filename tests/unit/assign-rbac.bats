#!/usr/bin/env bats
# Unit tests for assign-rbac.sh

SCRIPT="$BATS_TEST_DIRNAME/../../skills/shared/scripts/assign-rbac.sh"

@test "assign-rbac.sh exists" {
  [ -f "$SCRIPT" ]
}

@test "assign-rbac.sh is executable" {
  [ -x "$SCRIPT" ]
}

@test "assign-rbac.sh fails with no args" {
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
}

@test "assign-rbac.sh fails without --principal-id" {
  run bash "$SCRIPT" --scope /subscriptions/00000000 --role Reader
  [ "$status" -ne 0 ]
  [[ "$output" == *"principal-id"* ]]
}

@test "assign-rbac.sh fails without --scope" {
  run bash "$SCRIPT" --principal-id abc123 --role Reader
  [ "$status" -ne 0 ]
  [[ "$output" == *"scope"* ]]
}

@test "assign-rbac.sh fails without --role" {
  run bash "$SCRIPT" --principal-id abc123 --scope /subscriptions/00000000
  [ "$status" -ne 0 ]
  [[ "$output" == *"role"* ]]
}

@test "assign-rbac.sh contains StorageBlobDataContributor GUID" {
  grep -q "ba92f5b4-2d11-453d-a403-e96b0029c9fe" "$SCRIPT"
}

@test "assign-rbac.sh contains KeyVaultSecretsUser GUID" {
  grep -q "4633458b-17de-408a-b874-0445c86b69e6" "$SCRIPT"
}

@test "assign-rbac.sh contains Contributor GUID" {
  grep -q "b24988ac-6180-42a0-ab88-20f7382dd24c" "$SCRIPT"
}

@test "assign-rbac.sh is idempotent — checks existing assignments in source" {
  grep -q "role assignment list" "$SCRIPT"
}
