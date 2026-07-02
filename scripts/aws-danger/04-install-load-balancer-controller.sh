#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=./lib.sh
source "$ROOT_DIR/scripts/aws-danger/lib.sh"
load_danger_env "$ROOT_DIR"
require_danger_consent
ensure_tools aws eksctl helm kubectl curl

: "${AWS_REGION:=eu-west-1}"
: "${CLUSTER_NAME:=aibrix-gateway-full-stack}"
: "${AWS_LOAD_BALANCER_CONTROLLER_VERSION:=1.8.4}"
: "${AWS_LBC_POLICY_URL:=https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v${AWS_LOAD_BALANCER_CONTROLLER_VERSION}/docs/install/iam_policy.json}"
: "${AWS_LBC_POLICY_NAME:=AWSLoadBalancerControllerIAMPolicy-${CLUSTER_NAME}}"

aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" >/dev/null
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/${AWS_LBC_POLICY_NAME}"
MANIFEST_DIR="$ROOT_DIR/.aws-danger-manifests/aws-load-balancer-controller"
POLICY_FILE="$MANIFEST_DIR/iam_policy.json"
mkdir -p "$MANIFEST_DIR"

curl -fsSL "$AWS_LBC_POLICY_URL" -o "$POLICY_FILE"
if ! aws iam get-policy --policy-arn "$POLICY_ARN" >/dev/null 2>&1; then
  aws iam create-policy \
    --policy-name "$AWS_LBC_POLICY_NAME" \
    --policy-document "file://${POLICY_FILE}" >/dev/null
fi

eksctl utils associate-iam-oidc-provider \
  --cluster "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --approve

eksctl create iamserviceaccount \
  --cluster "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --attach-policy-arn "$POLICY_ARN" \
  --override-existing-serviceaccounts \
  --approve

helm repo add eks https://aws.github.io/eks-charts >/dev/null
helm repo update >/dev/null
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="$CLUSTER_NAME" \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region="$AWS_REGION" \
  --set vpcId="$(aws eks describe-cluster --region "$AWS_REGION" --name "$CLUSTER_NAME" --query 'cluster.resourcesVpcConfig.vpcId' --output text)"

kubectl -n kube-system rollout status deployment/aws-load-balancer-controller --timeout=300s
kubectl -n kube-system get deployment aws-load-balancer-controller -o wide

cat > "$ROOT_DIR/.aws-danger-lbc.env" <<ENV
AWS_LOAD_BALANCER_CONTROLLER_VERSION=$AWS_LOAD_BALANCER_CONTROLLER_VERSION
AWS_LBC_POLICY_ARN=$POLICY_ARN
ENV

echo "AWS Load Balancer Controller installed and IAM-bound: $POLICY_ARN"
