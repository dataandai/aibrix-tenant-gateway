#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${AWS_REGION:=eu-west-1}"
: "${CLUSTER_NAME:=aibrix-gateway-demo}"
: "${DELETE_ECR_REPOSITORY:=false}"
: "${ECR_REPOSITORY:=aibrix-multitenant-llm-gateway}"

if command -v kubectl >/dev/null 2>&1; then
  kubectl delete -f "$ROOT_DIR/k8s/overlays/aws-demo/tenant-gateway-aws-demo.yaml" --ignore-not-found=true || true
fi

eksctl delete cluster --region "$AWS_REGION" --name "$CLUSTER_NAME" --wait

if [ "$DELETE_ECR_REPOSITORY" = "true" ]; then
  aws ecr delete-repository --region "$AWS_REGION" --repository-name "$ECR_REPOSITORY" --force || true
fi

rm -f "$ROOT_DIR/.aws-demo.env" "$ROOT_DIR/.aws-demo-lb.env" "$ROOT_DIR/.aws-demo-eksctl-cluster.yaml"
echo "destroy complete"
