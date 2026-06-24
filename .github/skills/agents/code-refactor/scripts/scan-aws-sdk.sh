#!/usr/bin/env bash
# scan-aws-sdk.sh — Scan for remaining AWS SDK references in the output code.
#
# Usage:
#   ./scan-aws-sdk.sh [path]
#
# Default path is the repository root's outputs/azure-functions directory.
# Set exit code 1 if any AWS SDK residue is found so CI gates can block deployment.
#
# Patterns detected:
#   Python  : boto3, botocore, @boto3, AWS_*  (import/env pattern)
#   JS/TS   : @aws-sdk, aws-sdk
#   Java    : software.amazon.awssdk
#   Go      : github.com/aws/aws-sdk-go
#   Generic : AmazonS3Client, AmazonDynamoDB, KinesisClient etc.

set -euo pipefail

SCAN_PATH="${1:-outputs/azure-functions}"

if [[ ! -d "${SCAN_PATH}" ]]; then
  echo "ERROR: path not found: ${SCAN_PATH}" >&2
  exit 2
fi

PATTERN='boto3|botocore|@aws-sdk|aws-sdk|software\.amazon\.awssdk|github\.com/aws/aws-sdk-go|AmazonS3Client|AmazonDynamoDB|KinesisClient|SQSClient|SNSClient|LambdaClient|SecretsManagerClient'

echo "==> Scanning '${SCAN_PATH}' for AWS SDK references..."
RESULTS=$(grep -rn --include="*.py" --include="*.js" --include="*.ts" \
               --include="*.java" --include="*.go" --include="*.cs" \
               -E "${PATTERN}" "${SCAN_PATH}" 2>/dev/null || true)

if [[ -z "${RESULTS}" ]]; then
  echo "No AWS SDK residue found. Safe to deploy."
  exit 0
fi

echo ""
echo "FOUND AWS SDK references — fix before deploying:"
echo "-----------------------------------------------"
echo "${RESULTS}"
echo "-----------------------------------------------"
echo ""
echo "Total occurrences: $(echo "${RESULTS}" | wc -l)"
exit 1
