#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${AWS_REGION:=eu-west-1}"
: "${ECR_REPOSITORY:=aibrix-multitenant-llm-gateway}"
: "${IMAGE_TAG:=aws-demo}"

"$ROOT_DIR/scripts/aws/00-check-prereqs.sh"

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

echo "building image: $IMAGE_URI"
docker build -t "$IMAGE_URI" "$ROOT_DIR"
docker push "$IMAGE_URI"

cat > "$ROOT_DIR/.aws-demo.env" <<ENV
AWS_REGION=$AWS_REGION
ECR_REPOSITORY=$ECR_REPOSITORY
IMAGE_TAG=$IMAGE_TAG
IMAGE_URI=$IMAGE_URI
ENV

echo "pushed image: $IMAGE_URI"
echo "saved $ROOT_DIR/.aws-demo.env"
