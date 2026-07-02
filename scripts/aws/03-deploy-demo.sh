#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${AWS_REGION:=eu-west-1}"
: "${CLUSTER_NAME:=aibrix-gateway-demo}"

if [ -f "$ROOT_DIR/.aws-demo.env" ]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.aws-demo.env"
fi

: "${IMAGE_URI:?IMAGE_URI is required. Run scripts/aws/02-build-push-ecr.sh first or export IMAGE_URI.}"

aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" >/dev/null

TMP_MANIFEST="$(mktemp)"
sed "s|IMAGE_PLACEHOLDER|$IMAGE_URI|g" \
  "$ROOT_DIR/k8s/overlays/aws-demo/tenant-gateway-aws-demo.yaml" > "$TMP_MANIFEST"

kubectl apply -f "$TMP_MANIFEST"
rm -f "$TMP_MANIFEST"

kubectl -n tenant-gateway rollout status deployment/tenant-policy-gateway --timeout=180s

echo "waiting for AWS LoadBalancer hostname..."
for _ in $(seq 1 60); do
  LB_HOST="$(kubectl -n tenant-gateway get svc tenant-policy-gateway-public -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  if [ -n "$LB_HOST" ]; then
    echo "LB_HOST=$LB_HOST" | tee "$ROOT_DIR/.aws-demo-lb.env"
    echo "demo deployed"
    exit 0
  fi
  sleep 10
done

echo "LoadBalancer hostname was not assigned yet. Check: kubectl -n tenant-gateway get svc tenant-policy-gateway-public" >&2
exit 1
