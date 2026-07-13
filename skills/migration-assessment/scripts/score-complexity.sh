#!/usr/bin/env bash
# score-complexity.sh — Print a quick migration complexity summary from aws-inventory.json.
#
# Usage:
#   ./score-complexity.sh [path-to-aws-inventory.json]
#
# Default path:
#   outputs/aws-migration-artifacts/aws-inventory.json
#
# Behaviour:
#   - Reads aws-inventory.json
#   - If migration-assessment.md exists, parses the Service Complexity Matrix
#   - Otherwise applies default complexity rules by AWS service type
#   - Prints a per-service summary table and overall totals
#
# Exit codes:
#   Always exits 0 (reporting only)

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: ./score-complexity.sh [path-to-aws-inventory.json]

Read aws-inventory.json and print a quick migration complexity summary.
If migration-assessment.md exists beside the inventory file, the script parses the
Service Complexity Matrix. Otherwise it applies default complexity rules.
USAGE
}

normalize_service() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]'
}

service_display_name() {
  local service_key="$1"
  local service_type="$2"
  local normalized
  normalized=$(normalize_service "$service_key")

  case "$normalized" in
    lambda) echo "Lambda" ;;
    s3) echo "S3" ;;
    rds) echo "RDS" ;;
    dynamodb) echo "DynamoDB" ;;
    cognito) echo "Cognito" ;;
    ecs) echo "ECS" ;;
    eks) echo "EKS" ;;
    elasticache) echo "ElastiCache" ;;
    sqs) echo "SQS" ;;
    sns) echo "SNS" ;;
    eventbridge) echo "EventBridge" ;;
    apigateway) echo "API Gateway" ;;
    cloudfront) echo "CloudFront" ;;
    route53) echo "Route53" ;;
    vpc) echo "VPC" ;;
    iam) echo "IAM" ;;
    *)
      if [[ -n "$service_type" && "$service_type" != "$service_key" ]]; then
        echo "$service_type"
      else
        echo "$service_key"
      fi
      ;;
  esac
}

tier_rank() {
  case "$1" in
    Low) echo 1 ;;
    Medium) echo 2 ;;
    High) echo 3 ;;
    Critical) echo 4 ;;
    *) echo 0 ;;
  esac
}

normalize_tier() {
  local raw_tier
  raw_tier=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$raw_tier" in
    low) echo "Low" ;;
    medium) echo "Medium" ;;
    high) echo "High" ;;
    critical) echo "Critical" ;;
    *) echo "$1" ;;
  esac
}

max_tier() {
  local current="$1"
  local candidate="$2"

  current=$(normalize_tier "$current")
  candidate=$(normalize_tier "$candidate")

  if [[ $(tier_rank "$candidate") -gt $(tier_rank "$current") ]]; then
    echo "$candidate"
  else
    echo "$current"
  fi
}

default_tier_for_service() {
  local service_key="$1"
  local service_type="$2"
  local candidate
  local normalized

  for candidate in "$service_key" "$service_type"; do
    normalized=$(normalize_service "$candidate")
    case "$normalized" in
      lambda|awslambda|lambdafunction) echo "Low"; return ;;
      s3|amazons3) echo "Low"; return ;;
      rds|amazonrds) echo "Medium"; return ;;
      dynamodb|amazondynamodb) echo "Medium"; return ;;
      cognito|amazoncognito) echo "High"; return ;;
      ecs|amazonecs) echo "High"; return ;;
      eks|amazoneks) echo "Critical"; return ;;
      elasticache|amazonelasticache) echo "Medium"; return ;;
      sqs|amazonsqs) echo "Low"; return ;;
      sns|amazonsns) echo "Low"; return ;;
      eventbridge|amazoneventbridge|cloudwatchevents) echo "Medium"; return ;;
      apigateway|amazonapigateway|restapi|httpapi|websocketapi) echo "Medium"; return ;;
      cloudfront|amazoncloudfront) echo "Low"; return ;;
      route53|amazonroute53) echo "Low"; return ;;
      vpc|amazonvpc) echo "Medium"; return ;;
      iam|awsiam) echo "High"; return ;;
    esac
  done

  echo "Medium"
}

effort_for_tier() {
  case "$1" in
    Low) echo 2 ;;
    Medium) echo 5 ;;
    High) echo 10 ;;
    Critical) echo 15 ;;
    *) echo 5 ;;
  esac
}

sum_numbers() {
  awk -v left="$1" -v right="$2" 'BEGIN { printf "%.1f", left + right }'
}

format_number() {
  awk -v value="$1" 'BEGIN { if (value == int(value)) printf "%d", value; else printf "%.1f", value }'
}

effort_from_cell() {
  local cell="$1"
  local normalized_cell
  normalized_cell=$(printf '%s' "$cell" | tr '–—' '--')

  mapfile -t numbers < <(printf '%s' "$normalized_cell" | grep -oE '[0-9]+(\.[0-9]+)?' || true)
  if [[ "${#numbers[@]}" -eq 0 ]]; then
    echo 0
  elif [[ "${#numbers[@]}" -eq 1 ]]; then
    echo "${numbers[0]}"
  else
    awk -v first="${numbers[0]}" -v second="${numbers[1]}" 'BEGIN { printf "%.1f", (first + second) / 2 }'
  fi
}

main() {
  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    return 0
  fi

  if ! command -v jq >/dev/null 2>&1; then
    echo "❌ jq is required but was not found on PATH." >&2
    return 1
  fi

  local inventory_path assessment_path matrix_found parsed_rows
  inventory_path="${1:-outputs/aws-migration-artifacts/aws-inventory.json}"
  assessment_path="$(dirname "$inventory_path")/migration-assessment.md"

  echo "==> Reading AWS inventory: ${inventory_path}"
  if [[ ! -f "$inventory_path" ]]; then
    echo "❌ Inventory file not found: ${inventory_path}" >&2
    return 1
  fi

  if ! jq -e . "$inventory_path" >/dev/null; then
    echo "❌ Inventory file is not valid JSON: ${inventory_path}" >&2
    return 1
  fi

  if ! jq -e '.services | type == "object" and (keys | length) > 0' "$inventory_path" >/dev/null; then
    echo "❌ Inventory file must contain a non-empty services object." >&2
    return 1
  fi

  declare -A SERVICE_COUNTS=()
  declare -A SERVICE_COMPLEXITY=()
  declare -A SERVICE_EFFORTS=()
  parsed_rows=0

  if [[ -f "$assessment_path" && -s "$assessment_path" ]] && grep -q '^## Service Complexity Matrix' "$assessment_path"; then
    echo "==> Parsing Service Complexity Matrix: ${assessment_path}"

    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      [[ "$line" =~ ^\|[[:space:]]*Service[[:space:]]*\| ]] && continue
      [[ "$line" =~ ^\|[[:space:]]*- ]] && continue

      IFS='|' read -r _ service _logical count complexity effort _rest <<< "$line"
      service=$(printf '%s' "$service" | xargs)
      count=$(printf '%s' "$count" | xargs)
      complexity=$(normalize_tier "$(printf '%s' "$complexity" | xargs)")
      effort=$(printf '%s' "$effort" | xargs)

      [[ -z "$service" || -z "$count" || -z "$complexity" ]] && continue
      [[ ! "$count" =~ ^[0-9]+$ ]] && continue

      SERVICE_COUNTS["$service"]=$(( ${SERVICE_COUNTS["$service"]:-0} + count ))
      SERVICE_COMPLEXITY["$service"]=$(max_tier "${SERVICE_COMPLEXITY["$service"]:-Low}" "$complexity")
      SERVICE_EFFORTS["$service"]=$(sum_numbers "${SERVICE_EFFORTS["$service"]:-0}" "$(effort_from_cell "$effort")")
      parsed_rows=$((parsed_rows + 1))
    done < <(awk '
      /^## Service Complexity Matrix/ { in_table = 1; next }
      in_table && /^## / { exit }
      in_table && /^\|/ { print }
    ' "$assessment_path")
  fi

  if [[ "$parsed_rows" -eq 0 ]]; then
    echo "==> No usable Service Complexity Matrix found; applying default complexity rules"
    while IFS=$'\t' read -r service_key service_type count; do
      local service_name tier total_effort
      service_name=$(service_display_name "$service_key" "$service_type")
      tier=$(default_tier_for_service "$service_key" "$service_type")
      total_effort=$(awk -v base="$(effort_for_tier "$tier")" -v amount="$count" 'BEGIN { printf "%.1f", base * amount }')

      SERVICE_COUNTS["$service_name"]=$count
      SERVICE_COMPLEXITY["$service_name"]=$tier
      SERVICE_EFFORTS["$service_name"]=$total_effort
      parsed_rows=$((parsed_rows + 1))
    done < <(jq -r '.services | to_entries[] | [ .key, (.value.service_type // .key), ((.value.count // (.value.resources | length) // 0) | tostring) ] | @tsv' "$inventory_path")
  fi

  if [[ "$parsed_rows" -eq 0 ]]; then
    echo "❌ No service entries were found to score." >&2
    return 1
  fi

  local total_services total_effort overall_risk low_count medium_count high_count critical_count
  total_services=0
  total_effort=0
  overall_risk="Low"
  low_count=0
  medium_count=0
  high_count=0
  critical_count=0

  echo
  echo "| Service | Count | Complexity | Estimated Effort (days) |"
  echo "|---|---:|---|---:|"
  while IFS= read -r service_name; do
    local count complexity effort
    count="${SERVICE_COUNTS["$service_name"]}"
    complexity="${SERVICE_COMPLEXITY["$service_name"]}"
    effort="${SERVICE_EFFORTS["$service_name"]}"

    printf '| %s | %s | %s | %s |\n' "$service_name" "$count" "$complexity" "$(format_number "$effort")"

    total_services=$((total_services + 1))
    total_effort=$(sum_numbers "$total_effort" "$effort")
    overall_risk=$(max_tier "$overall_risk" "$complexity")

    case "$complexity" in
      Low) low_count=$((low_count + 1)) ;;
      Medium) medium_count=$((medium_count + 1)) ;;
      High) high_count=$((high_count + 1)) ;;
      Critical) critical_count=$((critical_count + 1)) ;;
    esac
  done < <(printf '%s\n' "${!SERVICE_COUNTS[@]}" | sort)

  echo
  echo "Complexity tiers: Low=${low_count}, Medium=${medium_count}, High=${high_count}, Critical=${critical_count}"
  echo "Total services: ${total_services}"
  echo "Total effort estimate: $(format_number "$total_effort") days"
  echo "Overall risk level: ${overall_risk}"
  return 0
}

if ! main "$@"; then
  exit 0
fi

exit 0
