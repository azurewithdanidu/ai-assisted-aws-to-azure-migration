#!/usr/bin/env bash
# validate-inventory.sh — Validate aws-inventory.json before downstream agents consume it.
#
# Usage:
#   ./validate-inventory.sh [path-to-aws-inventory.json]
#
# Default path:
#   outputs/aws-migration-artifacts/aws-inventory.json
#
# Requirements:
#   - jq
#
# Exit codes:
#   0 = inventory valid
#   1 = validation failed

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: ./validate-inventory.sh [path-to-aws-inventory.json]

Validate an AWS inventory JSON file before downstream agents consume it.

Checks:
  - File exists and is non-empty
  - JSON parses successfully
  - Top-level keys exist: discovery_timestamp, aws_account_id, aws_region, services
  - services object contains at least one service
  - Each service has service_type, count, and resources[]
  - Each resource has name (or id), arn (or equivalent), and region
USAGE
}

fail() {
  echo "❌ $1" >&2
  exit 1
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if ! command -v jq >/dev/null 2>&1; then
  fail "jq is required but was not found on PATH."
fi

INVENTORY_PATH="${1:-outputs/aws-migration-artifacts/aws-inventory.json}"

echo "==> Validating inventory file: ${INVENTORY_PATH}"

if [[ ! -f "${INVENTORY_PATH}" ]]; then
  fail "Inventory file not found: ${INVENTORY_PATH}"
fi

if [[ ! -s "${INVENTORY_PATH}" ]]; then
  fail "Inventory file is empty: ${INVENTORY_PATH}"
fi

echo "==> Checking JSON syntax"
if ! jq -e . "${INVENTORY_PATH}" >/dev/null; then
  fail "Inventory file is not valid JSON: ${INVENTORY_PATH}"
fi

echo "==> Checking top-level schema"
for key in discovery_timestamp aws_account_id aws_region services; do
  if ! jq -e --arg key "$key" '.[$key] != null and .[$key] != ""' "${INVENTORY_PATH}" >/dev/null; then
    fail "Missing required top-level key: ${key}"
  fi
done

if ! jq -e '.services | type == "object"' "${INVENTORY_PATH}" >/dev/null; then
  fail "Top-level key 'services' must be a JSON object."
fi

mapfile -t SERVICE_KEYS < <(jq -r '.services | keys[]' "${INVENTORY_PATH}")
if [[ "${#SERVICE_KEYS[@]}" -eq 0 ]]; then
  fail "The services object must contain at least one service entry."
fi

echo "==> Checking service entries"
for service_name in "${SERVICE_KEYS[@]}"; do
  if ! jq -e --arg service "$service_name" '.services[$service].service_type | type == "string" and length > 0' "${INVENTORY_PATH}" >/dev/null; then
    fail "Service '${service_name}' is missing required field: service_type"
  fi

  if ! jq -e --arg service "$service_name" '.services[$service].count | type == "number" and . >= 0' "${INVENTORY_PATH}" >/dev/null; then
    fail "Service '${service_name}' is missing a valid numeric count field."
  fi

  if ! jq -e --arg service "$service_name" '.services[$service].resources | type == "array"' "${INVENTORY_PATH}" >/dev/null; then
    fail "Service '${service_name}' must include a resources array."
  fi

  name_error=$(jq -r --arg service "$service_name" '
    first(
      .services[$service].resources
      | to_entries[]
      | select(((.value.name // .value.id // .value.identifier // "") | tostring | length) == 0)
      | "Service \($service) resource[\(.key)] is missing name or id"
    ) // empty
  ' "${INVENTORY_PATH}")
  if [[ -n "$name_error" ]]; then
    fail "$name_error"
  fi

  arn_error=$(jq -r --arg service "$service_name" '
    first(
      .services[$service].resources
      | to_entries[]
      | select(((.value.arn // .value.resource_arn // .value.resource_id // .value.identifier // .value.url // "") | tostring | length) == 0)
      | "Service \($service) resource[\(.key)] is missing arn or equivalent identifier"
    ) // empty
  ' "${INVENTORY_PATH}")
  if [[ -n "$arn_error" ]]; then
    fail "$arn_error"
  fi

  region_error=$(jq -r --arg service "$service_name" '
    first(
      .services[$service].resources
      | to_entries[]
      | select(((.value.region // "") | tostring | length) == 0)
      | "Service \($service) resource[\(.key)] is missing region"
    ) // empty
  ' "${INVENTORY_PATH}")
  if [[ -n "$region_error" ]]; then
    fail "$region_error"
  fi
done

service_count=$(jq '.services | keys | length' "${INVENTORY_PATH}")
resource_count=$(jq '[.services[]?.resources | length] | add // 0' "${INVENTORY_PATH}")

echo "✅ Inventory valid: ${service_count} services, ${resource_count} total resources"
exit 0
