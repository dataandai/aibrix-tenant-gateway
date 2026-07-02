#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=./lib.sh
source "$ROOT_DIR/scripts/aws-danger/lib.sh"
load_danger_env "$ROOT_DIR"
require_danger_consent
ensure_tools python

if [ -f "$ROOT_DIR/.aws-danger-oidc.env" ]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.aws-danger-oidc.env"
fi
if [ -f "$ROOT_DIR/.aws-danger-artifacts.env" ]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.aws-danger-artifacts.env"
fi
: "${SERVED_MODEL_NAME:=deepseek-r1-distill-llama-8b}"
: "${TENANT_REGISTRY_PATH:=$ROOT_DIR/.aws-danger-tenants.yaml}"
if [ ! -f "$TENANT_REGISTRY_PATH" ]; then
  export COGNITO_ISSUER COGNITO_CLIENT_ID LORA_ARTIFACT_BUCKET TENANT_A_LORA_SHA256 TENANT_B_LORA_SHA256 LORA_SIGNING_REFERENCE SERVED_MODEL_NAME
  render_template "$ROOT_DIR/config/templates/tenants.aws-danger.yaml.tpl" "$TENANT_REGISTRY_PATH"
fi
EVIDENCE_PATH="$ROOT_DIR/.aws-danger-adapter-verification.json"
PYTHONPATH="$ROOT_DIR/src" python -m tenant_policy_gateway.adapter_artifact_verifier \
  --registry "$TENANT_REGISTRY_PATH" \
  --evidence-out "$EVIDENCE_PATH"
cat > "$ROOT_DIR/.aws-danger-adapter-verification.env" <<ENV
APP_ADAPTER_VERIFICATION_ENFORCEMENT=required
ADAPTER_VERIFICATION_EVIDENCE_PATH=$EVIDENCE_PATH
ENV

echo "adapter verification evidence saved: $EVIDENCE_PATH"
