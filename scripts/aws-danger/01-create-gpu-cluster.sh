#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=./lib.sh
source "$ROOT_DIR/scripts/aws-danger/lib.sh"
load_danger_env "$ROOT_DIR"
require_danger_consent

: "${AWS_REGION:=eu-west-1}"
: "${CLUSTER_NAME:=aibrix-gateway-full-stack}"
: "${CPU_INSTANCE_TYPE:=t3.large}"
: "${GPU_INSTANCE_TYPE:=g5.2xlarge}"
: "${GPU_DESIRED_CAPACITY:=1}"
: "${GPU_MAX_SIZE:=2}"
: "${GPU_VOLUME_SIZE_GB:=300}"
: "${AWS_DANGER_PRIVATE_NETWORKING:=true}"

"$ROOT_DIR/scripts/aws-danger/00-check-danger-prereqs.sh"

export AWS_REGION CLUSTER_NAME CPU_INSTANCE_TYPE GPU_INSTANCE_TYPE GPU_DESIRED_CAPACITY GPU_MAX_SIZE GPU_VOLUME_SIZE_GB AWS_DANGER_PRIVATE_NETWORKING
RENDERED="$ROOT_DIR/.aws-danger-eksctl-gpu-cluster.yaml"
render_template "$ROOT_DIR/infra/aws/eksctl/cluster-gpu.yaml" "$RENDERED"

cat >&2 <<MSG
Creating GPU EKS full-stack cluster:
  cluster: $CLUSTER_NAME
  region:  $AWS_REGION
  gpu:     $GPU_INSTANCE_TYPE desired=$GPU_DESIRED_CAPACITY max=$GPU_MAX_SIZE
  private networking: $AWS_DANGER_PRIVATE_NETWORKING

This can be expensive and can fail because of regional GPU capacity or service quotas.
MSG

eksctl create cluster -f "$RENDERED"
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

echo "cluster ready"
