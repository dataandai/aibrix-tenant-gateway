#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=./lib.sh
source "$ROOT_DIR/scripts/aws-danger/lib.sh"
load_danger_env "$ROOT_DIR"
require_danger_consent
ensure_tools aws

: "${AWS_REGION:=eu-west-1}"
: "${CLUSTER_NAME:=aibrix-gateway-full-stack}"
: "${ARTIFACT_BUCKET_PREFIX:=aibrix-llm-artifacts}"
: "${BILLING_OBJECT_LOCK_DAYS:=30}"
: "${APP_AWS_BILLING_DYNAMODB_TABLE:=aibrix-gateway-billing-${CLUSTER_NAME}}"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
SAFE_CLUSTER="$(echo "$CLUSTER_NAME" | tr '[:upper:]_' '[:lower:]-')"
BILLING_BUCKET="${ARTIFACT_BUCKET_PREFIX}-${ACCOUNT_ID}-${AWS_REGION}-${SAFE_CLUSTER}-billing"

if ! aws s3api head-bucket --bucket "$BILLING_BUCKET" >/dev/null 2>&1; then
  if [ "$AWS_REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$BILLING_BUCKET" --object-lock-enabled-for-bucket >/dev/null
  else
    aws s3api create-bucket --bucket "$BILLING_BUCKET" --object-lock-enabled-for-bucket --create-bucket-configuration LocationConstraint="$AWS_REGION" >/dev/null
  fi
fi
aws s3api put-public-access-block --bucket "$BILLING_BUCKET" --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true >/dev/null
aws s3api put-bucket-versioning --bucket "$BILLING_BUCKET" --versioning-configuration Status=Enabled >/dev/null
aws s3api put-bucket-encryption --bucket "$BILLING_BUCKET" --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' >/dev/null
aws s3api put-object-lock-configuration --bucket "$BILLING_BUCKET" --object-lock-configuration "ObjectLockEnabled=Enabled,Rule={DefaultRetention={Mode=GOVERNANCE,Days=${BILLING_OBJECT_LOCK_DAYS}}}" >/dev/null

if ! aws dynamodb describe-table --region "$AWS_REGION" --table-name "$APP_AWS_BILLING_DYNAMODB_TABLE" >/dev/null 2>&1; then
  aws dynamodb create-table \
    --region "$AWS_REGION" \
    --table-name "$APP_AWS_BILLING_DYNAMODB_TABLE" \
    --attribute-definitions AttributeName=request_id,AttributeType=S \
    --key-schema AttributeName=request_id,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST >/dev/null
  aws dynamodb wait table-exists --region "$AWS_REGION" --table-name "$APP_AWS_BILLING_DYNAMODB_TABLE"
fi

cat > "$ROOT_DIR/.aws-danger-billing.env" <<ENV
APP_BILLING_MODE=aws_native_reference
APP_AWS_BILLING_S3_BUCKET=$BILLING_BUCKET
APP_AWS_BILLING_S3_PREFIX=billing-ledger/
APP_AWS_BILLING_DYNAMODB_TABLE=$APP_AWS_BILLING_DYNAMODB_TABLE
BILLING_OBJECT_LOCK_DAYS=$BILLING_OBJECT_LOCK_DAYS
ENV

echo "AWS-native reference billing bucket ready: s3://$BILLING_BUCKET/billing-ledger/"
echo "DynamoDB idempotency table ready: $APP_AWS_BILLING_DYNAMODB_TABLE"
