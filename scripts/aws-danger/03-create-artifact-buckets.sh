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
: "${SERVED_MODEL_NAME:=deepseek-r1-distill-llama-8b}"
: "${MODEL_ID:=deepseek-ai/DeepSeek-R1-Distill-Llama-8B}"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
SAFE_CLUSTER="$(echo "$CLUSTER_NAME" | tr '[:upper:]_' '[:lower:]-')"
MODEL_REGISTRY_BUCKET="${ARTIFACT_BUCKET_PREFIX}-${ACCOUNT_ID}-${AWS_REGION}-${SAFE_CLUSTER}-models"
LORA_ARTIFACT_BUCKET="${ARTIFACT_BUCKET_PREFIX}-${ACCOUNT_ID}-${AWS_REGION}-${SAFE_CLUSTER}-lora"

create_bucket() {
  local bucket="$1"
  if aws s3api head-bucket --bucket "$bucket" >/dev/null 2>&1; then
    return 0
  fi
  if [ "$AWS_REGION" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$bucket" >/dev/null
  else
    aws s3api create-bucket --bucket "$bucket" --create-bucket-configuration LocationConstraint="$AWS_REGION" >/dev/null
  fi
  aws s3api put-public-access-block --bucket "$bucket" --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true >/dev/null
  aws s3api put-bucket-versioning --bucket "$bucket" --versioning-configuration Status=Enabled >/dev/null
  aws s3api put-bucket-encryption --bucket "$bucket" --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' >/dev/null
}

create_bucket "$MODEL_REGISTRY_BUCKET"
create_bucket "$LORA_ARTIFACT_BUCKET"

TMP_DIR="$(mktemp -d)"
cat > "$TMP_DIR/models.json" <<JSON
{
  "warning": "reference model registry only; not a production model catalog",
  "models": [
    {
      "served_model_name": "$SERVED_MODEL_NAME",
      "source_model_id": "$MODEL_ID",
      "runtime": "vllm",
      "gateway": "aibrix",
      "kv_cache_isolation_proven": false
    }
  ]
}
JSON
cat > "$TMP_DIR/lora-readme.txt" <<TXT
This bucket is created by the AWS full-stack danger-zone path.
Upload real LoRA artifacts here only after you implement signing, scanning, and lifecycle controls.
The reference gateway catalog can point to s3://$LORA_ARTIFACT_BUCKET/<tenant>/<adapter>/<version>/adapter.safetensors.
TXT

aws s3 cp "$TMP_DIR/models.json" "s3://${MODEL_REGISTRY_BUCKET}/registry/models.json" >/dev/null
aws s3 cp "$TMP_DIR/lora-readme.txt" "s3://${LORA_ARTIFACT_BUCKET}/README.txt" >/dev/null

cat > "$TMP_DIR/tenant-a-adapter.safetensors" <<TXT
tenant-a reference LoRA placeholder for verification only
TXT
cat > "$TMP_DIR/tenant-b-adapter.safetensors" <<TXT
tenant-b reference LoRA placeholder for verification only
TXT
TENANT_A_LORA_SHA256="$(sha256sum "$TMP_DIR/tenant-a-adapter.safetensors" | awk '{print $1}')"
TENANT_B_LORA_SHA256="$(sha256sum "$TMP_DIR/tenant-b-adapter.safetensors" | awk '{print $1}')"
aws s3 cp "$TMP_DIR/tenant-a-adapter.safetensors" "s3://${LORA_ARTIFACT_BUCKET}/tenant-a/support/v1/adapter.safetensors" >/dev/null
aws s3 cp "$TMP_DIR/tenant-b-adapter.safetensors" "s3://${LORA_ARTIFACT_BUCKET}/tenant-b/support/v1/adapter.safetensors" >/dev/null
rm -rf "$TMP_DIR"

cat > "$ROOT_DIR/.aws-danger-artifacts.env" <<ENV
MODEL_REGISTRY_BUCKET=$MODEL_REGISTRY_BUCKET
LORA_ARTIFACT_BUCKET=$LORA_ARTIFACT_BUCKET
TENANT_A_LORA_SHA256=$TENANT_A_LORA_SHA256
TENANT_B_LORA_SHA256=$TENANT_B_LORA_SHA256
LORA_SIGNING_REFERENCE=reference-only-no-real-signature-verification
ENV

echo "S3 artifact buckets ready:"
echo "  model registry: s3://$MODEL_REGISTRY_BUCKET/registry/models.json"
echo "  LoRA artifacts:  s3://$LORA_ARTIFACT_BUCKET/"
echo "saved $ROOT_DIR/.aws-danger-artifacts.env"
