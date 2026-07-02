#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=./lib.sh
source "$ROOT_DIR/scripts/aws-danger/lib.sh"
load_danger_env "$ROOT_DIR"
require_danger_consent
ensure_tools aws kubectl curl

: "${AWS_REGION:=eu-west-1}"
: "${CLUSTER_NAME:=aibrix-gateway-full-stack}"
: "${SERVED_MODEL_NAME:=deepseek-r1-distill-llama-8b}"
: "${AWS_FULL_GATEWAY_SCHEME:=internal}"

if [ -f "$ROOT_DIR/.aws-danger-oidc.env" ]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.aws-danger-oidc.env"
else
  echo "missing .aws-danger-oidc.env; run scripts/aws-danger/02-bootstrap-cognito-oidc.sh" >&2
  exit 1
fi
if [ -f "$ROOT_DIR/.aws-danger-gateway.env" ]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.aws-danger-gateway.env"
fi

aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" >/dev/null

get_id_token() {
  local username="$1"
  aws cognito-idp initiate-auth \
    --region "$AWS_REGION" \
    --client-id "$COGNITO_CLIENT_ID" \
    --auth-flow USER_PASSWORD_AUTH \
    --auth-parameters USERNAME="$username",PASSWORD="$COGNITO_TEST_PASSWORD" \
    --query 'AuthenticationResult.IdToken' \
    --output text
}

TENANT_A_TOKEN="$(get_id_token "$TENANT_A_USERNAME")"
TENANT_B_TOKEN="$(get_id_token "$TENANT_B_USERNAME")"

PORT_FORWARD_PID=""
cleanup() {
  if [ -n "$PORT_FORWARD_PID" ]; then
    kill "$PORT_FORWARD_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if [ "${AWS_FULL_GATEWAY_SCHEME:-internal}" = "internal" ]; then
  kubectl -n tenant-gateway port-forward service/tenant-policy-gateway-full-stack 18080:80 >/tmp/aibrix-full-stack-port-forward.log 2>&1 &
  PORT_FORWARD_PID="$!"
  sleep 3
  BASE_URL="http://127.0.0.1:18080"
else
  LB_HOST="$(kubectl -n tenant-gateway get svc tenant-policy-gateway-full-stack -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
  BASE_URL="http://${LB_HOST}"
fi

echo "testing full-stack gateway at $BASE_URL"
curl -fsS "$BASE_URL/healthz" && echo
curl -fsS "$BASE_URL/readyz" && echo

echo "tenant-a real OIDC request through gateway to AIBrix/vLLM:"
curl -fsS \
  -H 'Host: tenant-a.example.local' \
  -H "Authorization: Bearer ${TENANT_A_TOKEN}" \
  -H 'Content-Type: application/json' \
  -d "{\"model\":\"${SERVED_MODEL_NAME}\",\"messages\":[{\"role\":\"user\",\"content\":\"Say hello in one short sentence.\"}],\"max_tokens\":32,\"temperature\":0}" \
  "$BASE_URL/v1/chat/completions" && echo

echo "cross-tenant token must be denied before AIBrix:"
set +e
status="$(curl -sS -o /tmp/aibrix-full-stack-cross-tenant.json -w '%{http_code}' \
  -H 'Host: tenant-b.example.local' \
  -H "Authorization: Bearer ${TENANT_A_TOKEN}" \
  -H 'Content-Type: application/json' \
  -d "{\"model\":\"${SERVED_MODEL_NAME}\",\"messages\":[{\"role\":\"user\",\"content\":\"wrong tenant\"}],\"max_tokens\":16}" \
  "$BASE_URL/v1/chat/completions")"
set -e
cat /tmp/aibrix-full-stack-cross-tenant.json && echo
if [ "$status" != "403" ]; then
  echo "expected 403 for cross-tenant request, got $status" >&2
  exit 1
fi

echo "tenant-b token generated successfully too; not used above except to prove both users exist: ${#TENANT_B_TOKEN} bytes"
echo "full-stack smoke test passed"
