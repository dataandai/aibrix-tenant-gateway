#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=./lib.sh
source "$ROOT_DIR/scripts/aws-danger/lib.sh"
load_danger_env "$ROOT_DIR"
require_danger_consent
ensure_tools aws kubectl

: "${AWS_REGION:=eu-west-1}"
: "${CLUSTER_NAME:=aibrix-gateway-full-stack}"
: "${GATEWAY_POD_IDENTITY_ROLE_NAME:=AibrixGatewayBillingRole-${CLUSTER_NAME}}"
: "${GATEWAY_POD_IDENTITY_POLICY_NAME:=AibrixGatewayBillingPolicy-${CLUSTER_NAME}}"
: "${APP_AWS_BILLING_S3_BUCKET:=}"
: "${APP_AWS_BILLING_S3_PREFIX:=billing-ledger/}"
: "${APP_AWS_BILLING_DYNAMODB_TABLE:=}"

if [ -f "$ROOT_DIR/.aws-danger-billing.env" ]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.aws-danger-billing.env"
fi
if [ -z "${APP_AWS_BILLING_S3_BUCKET:-}" ] || [ -z "${APP_AWS_BILLING_DYNAMODB_TABLE:-}" ]; then
  echo "missing APP_AWS_BILLING_S3_BUCKET or APP_AWS_BILLING_DYNAMODB_TABLE; run scripts/aws-danger/11-create-aws-native-billing-ledger.sh first" >&2
  exit 1
fi

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${GATEWAY_POD_IDENTITY_ROLE_NAME}"
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${GATEWAY_POD_IDENTITY_POLICY_NAME}"

TRUST_DOC="$(mktemp)"
cat > "$TRUST_DOC" <<'JSON'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {"Service": "pods.eks.amazonaws.com"},
      "Action": ["sts:AssumeRole", "sts:TagSession"]
    }
  ]
}
JSON

if ! aws iam get-role --role-name "$GATEWAY_POD_IDENTITY_ROLE_NAME" >/dev/null 2>&1; then
  aws iam create-role \
    --role-name "$GATEWAY_POD_IDENTITY_ROLE_NAME" \
    --assume-role-policy-document "file://$TRUST_DOC" >/dev/null
else
  aws iam update-assume-role-policy \
    --role-name "$GATEWAY_POD_IDENTITY_ROLE_NAME" \
    --policy-document "file://$TRUST_DOC" >/dev/null
fi
rm -f "$TRUST_DOC"

POLICY_DOC="$(mktemp)"
cat > "$POLICY_DOC" <<JSON
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "WriteBillingLedgerObjects",
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:PutObjectRetention", "s3:PutObjectTagging"],
      "Resource": "arn:aws:s3:::${APP_AWS_BILLING_S3_BUCKET}/${APP_AWS_BILLING_S3_PREFIX%/}/*"
    },
    {
      "Sid": "DynamoDbIdempotency",
      "Effect": "Allow",
      "Action": ["dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:GetItem"],
      "Resource": "arn:aws:dynamodb:${AWS_REGION}:${ACCOUNT_ID}:table/${APP_AWS_BILLING_DYNAMODB_TABLE}"
    }
  ]
}
JSON

if aws iam get-policy --policy-arn "$POLICY_ARN" >/dev/null 2>&1; then
  VERSION_ID="$(aws iam create-policy-version --policy-arn "$POLICY_ARN" --policy-document "file://$POLICY_DOC" --set-as-default --query PolicyVersion.VersionId --output text)"
  echo "created new IAM policy version $VERSION_ID for $POLICY_ARN"
else
  aws iam create-policy --policy-name "$GATEWAY_POD_IDENTITY_POLICY_NAME" --policy-document "file://$POLICY_DOC" >/dev/null
fi
rm -f "$POLICY_DOC"
aws iam attach-role-policy --role-name "$GATEWAY_POD_IDENTITY_ROLE_NAME" --policy-arn "$POLICY_ARN" >/dev/null || true

aws eks describe-addon --region "$AWS_REGION" --cluster-name "$CLUSTER_NAME" --addon-name eks-pod-identity-agent >/dev/null 2>&1 || \
  aws eks create-addon --region "$AWS_REGION" --cluster-name "$CLUSTER_NAME" --addon-name eks-pod-identity-agent >/dev/null

aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" >/dev/null
kubectl create namespace tenant-gateway --dry-run=client -o yaml | kubectl apply -f -
kubectl -n tenant-gateway create serviceaccount tenant-policy-gateway --dry-run=client -o yaml | kubectl apply -f -

ASSOCIATION_ID="$(aws eks list-pod-identity-associations \
  --region "$AWS_REGION" \
  --cluster-name "$CLUSTER_NAME" \
  --namespace tenant-gateway \
  --service-account tenant-policy-gateway \
  --query 'associations[0].associationId' \
  --output text 2>/dev/null || true)"
if [ -z "$ASSOCIATION_ID" ] || [ "$ASSOCIATION_ID" = "None" ]; then
  ASSOCIATION_ID="$(aws eks create-pod-identity-association \
    --region "$AWS_REGION" \
    --cluster-name "$CLUSTER_NAME" \
    --namespace tenant-gateway \
    --service-account tenant-policy-gateway \
    --role-arn "$ROLE_ARN" \
    --query 'association.associationId' \
    --output text)"
else
  aws eks update-pod-identity-association \
    --region "$AWS_REGION" \
    --cluster-name "$CLUSTER_NAME" \
    --association-id "$ASSOCIATION_ID" \
    --role-arn "$ROLE_ARN" >/dev/null
fi

cat > "$ROOT_DIR/.aws-danger-pod-identity.env" <<ENV
GATEWAY_POD_IDENTITY_ROLE_ARN=$ROLE_ARN
GATEWAY_POD_IDENTITY_ASSOCIATION_ID=$ASSOCIATION_ID
APP_AWS_BILLING_DYNAMODB_TABLE=$APP_AWS_BILLING_DYNAMODB_TABLE
ENV

echo "Gateway Pod Identity ready: $ROLE_ARN"
echo "saved $ROOT_DIR/.aws-danger-pod-identity.env"
