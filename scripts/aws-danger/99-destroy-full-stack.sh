#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=./lib.sh
source "$ROOT_DIR/scripts/aws-danger/lib.sh"
load_danger_env "$ROOT_DIR"
require_danger_consent
ensure_tools aws eksctl kubectl

: "${AWS_REGION:=eu-west-1}"
: "${CLUSTER_NAME:=aibrix-gateway-full-stack}"
: "${DELETE_ECR_REPOSITORY:=false}"
: "${DELETE_COGNITO_USER_POOL:=false}"
: "${DELETE_ARTIFACT_BUCKETS:=false}"
: "${ECR_REPOSITORY:=aibrix-multitenant-llm-gateway}"

if [ -f "$ROOT_DIR/.aws-danger-oidc.env" ]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.aws-danger-oidc.env"
fi
if [ -f "$ROOT_DIR/.aws-danger-artifacts.env" ]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.aws-danger-artifacts.env"
fi

if command -v kubectl >/dev/null 2>&1; then
  kubectl delete -f "$ROOT_DIR/.aws-danger-tenant-gateway.yaml" --ignore-not-found=true || true
  kubectl delete -f "$ROOT_DIR/.aws-danger-vllm-model.yaml" --ignore-not-found=true || true
fi

eksctl delete cluster --region "$AWS_REGION" --name "$CLUSTER_NAME" --wait || true

if [ "$DELETE_ECR_REPOSITORY" = "true" ]; then
  aws ecr delete-repository --region "$AWS_REGION" --repository-name "$ECR_REPOSITORY" --force || true
fi

if [ "$DELETE_COGNITO_USER_POOL" = "true" ] && [ -n "${COGNITO_USER_POOL_ID:-}" ]; then
  aws cognito-idp delete-user-pool --region "$AWS_REGION" --user-pool-id "$COGNITO_USER_POOL_ID" || true
fi

if [ "$DELETE_ARTIFACT_BUCKETS" = "true" ]; then
  for bucket in ${MODEL_REGISTRY_BUCKET:-} ${LORA_ARTIFACT_BUCKET:-}; do
    if [ -n "$bucket" ]; then
      aws s3 rm "s3://${bucket}" --recursive || true
      aws s3api delete-bucket --bucket "$bucket" || true
    fi
  done
fi

rm -f "$ROOT_DIR"/.aws-danger-*.env "$ROOT_DIR"/.aws-danger-*.yaml
echo "full-stack danger-zone destroy complete"
echo "Note: set DELETE_ECR_REPOSITORY=true DELETE_COGNITO_USER_POOL=true DELETE_ARTIFACT_BUCKETS=true to remove optional persistent resources."
