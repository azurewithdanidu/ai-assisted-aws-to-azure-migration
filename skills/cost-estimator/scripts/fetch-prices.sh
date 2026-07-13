#!/usr/bin/env bash
# fetch-prices.sh — Query the Azure Retail Prices API for a service, region, and optional SKU.
#
# Usage:
#   ./fetch-prices.sh <SERVICE_NAME> [ARM_REGION] [SKU_NAME]
#
# Examples:
#   ./fetch-prices.sh "Azure Functions" australiaeast
#   ./fetch-prices.sh "Azure Database for PostgreSQL" australiaeast "Flexible Server"
#
# Requirements:
#   - curl
#   - jq
#
# Exit codes:
#   0 = pricing data returned
#   1 = API call failed or returned no results

set -euo pipefail

API_BASE_URL="https://prices.azure.com/api/retail/prices"
API_VERSION="2023-01-01-preview"

usage() {
  cat <<'USAGE'
Usage: ./fetch-prices.sh <SERVICE_NAME> [ARM_REGION] [SKU_NAME]

Query the Azure Retail Prices API for a service, region, and optional SKU filter.

Examples:
  ./fetch-prices.sh "Azure Functions" australiaeast
  ./fetch-prices.sh "Azure Database for PostgreSQL" australiaeast "Flexible Server"
USAGE
}

fail() {
  echo "❌ $1" >&2
  exit 1
}

escape_odata_literal() {
  printf '%s' "$1" | sed "s/'/''/g"
}

build_filter() {
  local service_name="$1"
  local arm_region="$2"
  local sku_name="$3"
  local escaped_service escaped_region escaped_sku

  escaped_service=$(escape_odata_literal "$service_name")
  escaped_region=$(escape_odata_literal "$arm_region")

  local filter="serviceName eq '${escaped_service}' and armRegionName eq '${escaped_region}'"
  if [[ -n "$sku_name" ]]; then
    escaped_sku=$(escape_odata_literal "$sku_name")
    filter+=" and contains(skuName,'${escaped_sku}')"
  fi

  printf '%s' "$filter"
}

fetch_all_items() {
  local filter="$1"
  local request_url response page_items
  local all_items='[]'
  local page=1

  request_url="${API_BASE_URL}?api-version=${API_VERSION}&\$filter=$(jq -rn --arg value "$filter" '$value | @uri')"

  echo "==> Filter: ${filter}" >&2
  while [[ -n "$request_url" ]]; do
    echo "==> Fetching page ${page}" >&2
    if ! response=$(curl --silent --show-error --fail --location "$request_url"); then
      return 1
    fi

    page_items=$(jq '.Items // []' <<<"$response")
    all_items=$(jq -cs '.[0] + .[1]' <(printf '%s' "$all_items") <(printf '%s' "$page_items"))
    request_url=$(jq -r '.NextPageLink // empty' <<<"$response")
    page=$((page + 1))
  done

  printf '%s' "$all_items"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 1 || -z "${1:-}" ]]; then
  usage
  fail "SERVICE_NAME is required."
fi

if ! command -v curl >/dev/null 2>&1; then
  fail "curl is required but was not found on PATH."
fi

if ! command -v jq >/dev/null 2>&1; then
  fail "jq is required but was not found on PATH."
fi

SERVICE_NAME="$1"
ARM_REGION="${2:-australiaeast}"
SKU_NAME="${3:-}"

if [[ -z "$ARM_REGION" ]]; then
  fail "ARM_REGION must not be empty."
fi

filter=$(build_filter "$SERVICE_NAME" "$ARM_REGION" "$SKU_NAME")

echo "==> Querying Azure Retail Prices API"
if ! all_items=$(fetch_all_items "$filter"); then
  fail "Azure Retail Prices API request failed."
fi

result_count=$(jq 'length' <<<"$all_items")
if [[ "$result_count" -eq 0 ]]; then
  if [[ "$SERVICE_NAME" == Azure\ * ]]; then
    fallback_service="${SERVICE_NAME#Azure }"
    echo "==> No results for '${SERVICE_NAME}'. Retrying with '${fallback_service}'."
    filter=$(build_filter "$fallback_service" "$ARM_REGION" "$SKU_NAME")
    if ! all_items=$(fetch_all_items "$filter"); then
      fail "Azure Retail Prices API request failed during fallback lookup."
    fi
    result_count=$(jq 'length' <<<"$all_items")
  fi
fi

if [[ "$result_count" -eq 0 ]]; then
  fail "No pricing results returned for service '${SERVICE_NAME}' in region '${ARM_REGION}'."
fi

echo
printf '| SKU | Meter | Retail Price (USD) | Unit |\n'
printf '|---|---|---:|---|\n'
jq -r '
  sort_by(.retailPrice // 1e99)[]
  | "| \(.skuName // "-") | \(.meterName // "-") | \((.retailPrice // 0) | tostring) | \(.unitOfMeasure // "-") |"
' <<<"$all_items"

echo
echo "✅ Retrieved ${result_count} price meter(s)."
exit 0
