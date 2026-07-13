#!/usr/bin/env bats
# Unit tests for verify-security.sh

SCRIPT="$BATS_TEST_DIRNAME/../../skills/shared/scripts/verify-security.sh"

@test "verify-security.sh exists" {
  [ -f "$SCRIPT" ]
}

@test "verify-security.sh is executable" {
  [ -x "$SCRIPT" ]
}

@test "verify-security.sh fails with no args" {
  run bash "$SCRIPT"
  [ "$status" -ne 0 ]
}

@test "verify-security.sh fails without --resource-group" {
  run bash "$SCRIPT" --subscription 00000000
  [ "$status" -ne 0 ]
  [[ "$output" == *"resource-group"* ]]
}

@test "verify-security.sh checks publicNetworkAccess in source" {
  grep -q "publicNetworkAccess" "$SCRIPT"
}

@test "verify-security.sh checks allowBlobPublicAccess in source" {
  grep -q "allowBlobPublicAccess" "$SCRIPT"
}

@test "verify-security.sh checks Key Vault softDelete in source" {
  grep -q "enableSoftDelete" "$SCRIPT"
}

@test "verify-security.sh checks Key Vault purgeProtection in source" {
  grep -q "enablePurgeProtection" "$SCRIPT"
}

@test "verify-security.sh checks Function App httpsOnly in source" {
  grep -q "httpsOnly" "$SCRIPT"
}

@test "verify-security.sh checks TLS version in source" {
  grep -qi "minTlsVersion\|tls" "$SCRIPT"
}

@test "verify-security.sh writes a security report" {
  grep -q "security-report" "$SCRIPT"
}

@test "verify-security.sh rejects unknown flags" {
  run bash "$SCRIPT" --totally-wrong-flag
  [ "$status" -ne 0 ]
}
