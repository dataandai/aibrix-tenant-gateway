#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=./lib.sh
source "$ROOT_DIR/scripts/aws-danger/lib.sh"
load_danger_env "$ROOT_DIR"
require_danger_consent
ensure_tools aws kubectl docker

: "${AWS_REGION:=eu-west-1}"
: "${CLUSTER_NAME:=aibrix-gateway-full-stack}"
: "${ECR_REPOSITORY:=aibrix-multitenant-llm-gateway}"
: "${IMAGE_TAG:=aws-full-stack}"
: "${SERVED_MODEL_NAME:=deepseek-r1-distill-llama-8b}"
: "${AWS_FULL_GATEWAY_SCHEME:=internal}"
: "${AWS_FULL_GATEWAY_LB_TYPE:=nlb}"

if [ -f "$ROOT_DIR/.aws-danger-oidc.env" ]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.aws-danger-oidc.env"
else
  echo "missing .aws-danger-oidc.env; run scripts/aws-danger/02-bootstrap-cognito-oidc.sh" >&2
  exit 1
fi
if [ -f "$ROOT_DIR/.aws-danger-artifacts.env" ]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.aws-danger-artifacts.env"
else
  echo "missing .aws-danger-artifacts.env; run scripts/aws-danger/03-create-artifact-buckets.sh" >&2
  exit 1
fi
if [ -f "$ROOT_DIR/.aws-danger-redis.env" ]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.aws-danger-redis.env"
else
  echo "WARNING: missing .aws-danger-redis.env; full-stack deploy will refuse in-memory quota unless APP_QUOTA_MODE is explicitly set to redis." >&2
fi
if [ -f "$ROOT_DIR/.aws-danger-billing.env" ]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.aws-danger-billing.env"
else
  echo "WARNING: missing .aws-danger-billing.env; using APP_BILLING_MODE=${APP_BILLING_MODE:-observability}." >&2
fi
if [ ! -f "$ROOT_DIR/.aws-danger-lbc.env" ]; then
  echo "missing .aws-danger-lbc.env; run scripts/aws-danger/04-install-load-balancer-controller.sh before deploying the LoadBalancer Service" >&2
  exit 1
fi
if [ -f "$ROOT_DIR/.aws-danger-pod-identity.env" ]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.aws-danger-pod-identity.env"
fi

aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" >/dev/null
if [ "$AWS_FULL_GATEWAY_SCHEME" != "internal" ] && [ "$AWS_FULL_GATEWAY_SCHEME" != "internet-facing" ]; then
  echo "AWS_FULL_GATEWAY_SCHEME must be internal or internet-facing" >&2
  exit 1
fi
if [ "$AWS_FULL_GATEWAY_SCHEME" = "internet-facing" ]; then
  cat >&2 <<MSG
WARNING: AWS_FULL_GATEWAY_SCHEME=internet-facing exposes the Tenant Policy Gateway through a public AWS LoadBalancer.
This is for throwaway tests only; keep AIBrix upstream private and delete the cluster afterwards.
MSG
fi
if [ "$AWS_FULL_GATEWAY_SCHEME" = "internal" ]; then
  AWS_FULL_GATEWAY_INTERNAL_LEGACY="true"
else
  AWS_FULL_GATEWAY_INTERNAL_LEGACY="false"
fi
: "${APP_QUOTA_MODE:=redis}"
: "${APP_REDIS_QUOTA_URL:=}"
: "${APP_BILLING_MODE:=observability}"
: "${APP_AWS_BILLING_S3_BUCKET:=}"
: "${APP_AWS_BILLING_S3_PREFIX:=billing-ledger/}"
: "${APP_AWS_BILLING_DYNAMODB_TABLE:=}"
: "${GATEWAY_IRSA_ROLE_ARN:=}"
: "${AWS_FULL_OPTIONAL_PUBLIC_HTTPS_EGRESS_CIDR:=0.0.0.0/0}"
: "${APP_ADAPTER_VERIFICATION_ENFORCEMENT:=required}"
if [ "$APP_QUOTA_MODE" != "redis" ]; then
  echo "Refusing full-stack deployment with APP_QUOTA_MODE=$APP_QUOTA_MODE. Use scripts/aws-danger/09-create-redis-quota-backend.sh or set a distributed backend." >&2
  exit 1
fi
if [ -z "$APP_REDIS_QUOTA_URL" ]; then
  echo "APP_REDIS_QUOTA_URL is required for full-stack Redis quota mode." >&2
  exit 1
fi
if [ "$APP_BILLING_MODE" = "aws_native_reference" ]; then
  if [ -z "$APP_AWS_BILLING_S3_BUCKET" ] || [ -z "$APP_AWS_BILLING_DYNAMODB_TABLE" ]; then
    echo "APP_BILLING_MODE=aws_native_reference requires S3 bucket and DynamoDB table from scripts/aws-danger/11-create-aws-native-billing-ledger.sh" >&2
    exit 1
  fi
  if [ -z "$GATEWAY_IRSA_ROLE_ARN" ]; then
    echo "APP_BILLING_MODE=aws_native_reference requires gateway Pod Identity/IRSA; run scripts/aws-danger/12-bootstrap-gateway-pod-identity.sh" >&2
    exit 1
  fi
fi
if [ "$APP_ADAPTER_VERIFICATION_ENFORCEMENT" = "required" ] && [ ! -f "$ROOT_DIR/.aws-danger-adapter-verification.env" ]; then
  echo "missing .aws-danger-adapter-verification.env; run scripts/aws-danger/10-verify-adapter-artifacts.sh before full-stack deploy" >&2
  exit 1
fi

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
IMAGE_URI="${REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"

aws ecr describe-repositories --region "$AWS_REGION" --repository-names "$ECR_REPOSITORY" >/dev/null 2>&1 || \
  aws ecr create-repository \
    --region "$AWS_REGION" \
    --repository-name "$ECR_REPOSITORY" \
    --image-scanning-configuration scanOnPush=true \
    --encryption-configuration encryptionType=AES256 >/dev/null
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$REGISTRY"

echo "building gateway image: $IMAGE_URI"
docker build -t "$IMAGE_URI" "$ROOT_DIR"
docker push "$IMAGE_URI"

# Discover the AIBrix Envoy Gateway service created by AIBrix/Envoy Gateway. The hash suffix can vary.
AIBRIX_ENVOY_SERVICE="${AIBRIX_ENVOY_SERVICE:-}"
if [ -z "$AIBRIX_ENVOY_SERVICE" ]; then
  AIBRIX_ENVOY_SERVICE="$(kubectl -n envoy-gateway-system get svc -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep '^envoy-aibrix-system-aibrix-eg' | head -n1 || true)"
fi
if [ -z "$AIBRIX_ENVOY_SERVICE" ]; then
  echo "could not discover AIBrix Envoy service in namespace envoy-gateway-system" >&2
  echo "set AIBRIX_ENVOY_SERVICE manually after inspecting: kubectl -n envoy-gateway-system get svc" >&2
  exit 1
fi
AIBRIX_UPSTREAM_BASE_URL="http://${AIBRIX_ENVOY_SERVICE}.envoy-gateway-system.svc.cluster.local"

export COGNITO_ISSUER COGNITO_CLIENT_ID COGNITO_REQUIRED_GROUP LORA_ARTIFACT_BUCKET TENANT_A_LORA_SHA256 TENANT_B_LORA_SHA256 LORA_SIGNING_REFERENCE SERVED_MODEL_NAME
TENANT_REGISTRY_RENDERED="$ROOT_DIR/.aws-danger-tenants.yaml"
render_template "$ROOT_DIR/config/templates/tenants.aws-danger.yaml.tpl" "$TENANT_REGISTRY_RENDERED"

kubectl create namespace tenant-gateway --dry-run=client -o yaml | kubectl apply -f -
kubectl -n tenant-gateway create configmap tenant-registry \
  --from-file=tenants.yaml="$TENANT_REGISTRY_RENDERED" \
  --dry-run=client -o yaml | kubectl apply -f -

export IMAGE_URI AIBRIX_UPSTREAM_BASE_URL AWS_FULL_GATEWAY_SCHEME AWS_FULL_GATEWAY_LB_TYPE AWS_FULL_GATEWAY_INTERNAL_LEGACY APP_QUOTA_MODE APP_REDIS_QUOTA_URL APP_BILLING_MODE APP_AWS_BILLING_S3_BUCKET APP_AWS_BILLING_S3_PREFIX APP_AWS_BILLING_DYNAMODB_TABLE AWS_REGION GATEWAY_IRSA_ROLE_ARN AWS_FULL_OPTIONAL_PUBLIC_HTTPS_EGRESS_CIDR
RENDERED_GATEWAY="$ROOT_DIR/.aws-danger-tenant-gateway.yaml"
render_template "$ROOT_DIR/k8s/overlays/aws-danger/tenant-gateway-full-stack.yaml.tpl" "$RENDERED_GATEWAY"
kubectl apply -f "$RENDERED_GATEWAY"
kubectl -n tenant-gateway rollout status deployment/tenant-policy-gateway --timeout=300s

cat > "$ROOT_DIR/.aws-danger-gateway.env" <<ENV
AWS_REGION=$AWS_REGION
CLUSTER_NAME=$CLUSTER_NAME
IMAGE_URI=$IMAGE_URI
AIBRIX_ENVOY_SERVICE=$AIBRIX_ENVOY_SERVICE
AIBRIX_UPSTREAM_BASE_URL=$AIBRIX_UPSTREAM_BASE_URL
AWS_FULL_GATEWAY_SCHEME=$AWS_FULL_GATEWAY_SCHEME
AWS_FULL_GATEWAY_LB_TYPE=$AWS_FULL_GATEWAY_LB_TYPE
SERVED_MODEL_NAME=$SERVED_MODEL_NAME
APP_QUOTA_MODE=$APP_QUOTA_MODE
APP_REDIS_QUOTA_URL=$APP_REDIS_QUOTA_URL
APP_BILLING_MODE=$APP_BILLING_MODE
APP_AWS_BILLING_S3_BUCKET=$APP_AWS_BILLING_S3_BUCKET
APP_AWS_BILLING_DYNAMODB_TABLE=$APP_AWS_BILLING_DYNAMODB_TABLE
GATEWAY_IRSA_ROLE_ARN=$GATEWAY_IRSA_ROLE_ARN
ENV

LB_HOST="$(kubectl -n tenant-gateway get svc tenant-policy-gateway-full-stack -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
if [ -n "$LB_HOST" ]; then
  echo "verifying NLB scheme for $LB_HOST"
  ACTUAL_SCHEME="$(aws elbv2 describe-load-balancers --region "$AWS_REGION" --query "LoadBalancers[?DNSName=='$LB_HOST'].Scheme | [0]" --output text 2>/dev/null || true)"
  echo "LoadBalancer scheme: $ACTUAL_SCHEME"
  if [ "$AWS_FULL_GATEWAY_SCHEME" = "internal" ] && [ "$ACTUAL_SCHEME" != "internal" ]; then
    echo "ERROR: expected internal NLB but observed $ACTUAL_SCHEME" >&2
    exit 1
  fi
else
  echo "WARNING: LoadBalancer hostname is not assigned yet; run scripts/aws-danger/08-verify-private-networking.sh later." >&2
fi

echo "gateway deployed with real OIDC, distributed quota, and private AIBrix upstream: $AIBRIX_UPSTREAM_BASE_URL"
echo "saved $ROOT_DIR/.aws-danger-gateway.env"
