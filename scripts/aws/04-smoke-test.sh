#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${AWS_REGION:=eu-west-1}"
: "${CLUSTER_NAME:=aibrix-gateway-demo}"

if [ -f "$ROOT_DIR/.aws-demo-lb.env" ]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.aws-demo-lb.env"
fi

if [ -z "${LB_HOST:-}" ]; then
  aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" >/dev/null
  LB_HOST="$(kubectl -n tenant-gateway get svc tenant-policy-gateway-public -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
fi

BASE_URL="http://${LB_HOST}"
echo "testing $BASE_URL"

echo "healthz:"
curl -fsS "$BASE_URL/healthz" && echo

echo "readyz:"
curl -fsS "$BASE_URL/readyz" && echo

echo "tenant-a valid request:"
curl -fsS \
  -H 'Host: tenant-a.example.local' \
  -H 'Authorization: Bearer mock:tenant-a:alice' \
  -H 'Content-Type: application/json' \
  -d '{"model":"meta-llama/Llama-3.1-8B-Instruct","messages":[{"role":"user","content":"hello from AWS demo"}],"lora_adapter":"tenant-a-support"}' \
  "$BASE_URL/v1/chat/completions" && echo

echo "cross-tenant request should return 403:"
set +e
status="$(curl -sS -o /tmp/aibrix-cross-tenant-response.json -w '%{http_code}' \
  -H 'Host: tenant-b.example.local' \
  -H 'Authorization: Bearer mock:tenant-a:alice' \
  -H 'Content-Type: application/json' \
  -d '{"model":"meta-llama/Llama-3.1-8B-Instruct","messages":[{"role":"user","content":"wrong tenant"}],"lora_adapter":"tenant-a-support"}' \
  "$BASE_URL/v1/chat/completions")"
set -e
cat /tmp/aibrix-cross-tenant-response.json && echo
if [ "$status" != "403" ]; then
  echo "expected 403, got $status" >&2
  exit 1
fi

echo "smoke test passed"
