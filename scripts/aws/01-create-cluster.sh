#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${AWS_REGION:=eu-west-1}"
: "${CLUSTER_NAME:=aibrix-gateway-demo}"

"$ROOT_DIR/scripts/aws/00-check-prereqs.sh"

RENDERED="$ROOT_DIR/.aws-demo-eksctl-cluster.yaml"
python - <<PY
from pathlib import Path
from string import Template
import os
src = Path("$ROOT_DIR/infra/aws/eksctl/cluster.yaml").read_text()
Path("$RENDERED").write_text(Template(src).safe_substitute(os.environ | {"AWS_REGION": "$AWS_REGION", "CLUSTER_NAME": "$CLUSTER_NAME"}))
PY

echo "creating EKS demo cluster: $CLUSTER_NAME in $AWS_REGION"
eksctl create cluster -f "$RENDERED"

echo "writing kubeconfig"
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME"

echo "cluster ready"
