#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=./lib.sh
source "$ROOT_DIR/scripts/aws-danger/lib.sh"
load_danger_env "$ROOT_DIR"
require_danger_consent
ensure_tools aws kubectl

: "${AWS_REGION:=eu-west-1}"
: "${CLUSTER_NAME:=aibrix-gateway-full-stack}"
aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" >/dev/null

BAD_NODES="$(kubectl get nodes -o json | python -c 'import json,sys; obj=json.load(sys.stdin); bad=[]
for item in obj.get("items",[]):
    name=item["metadata"]["name"]
    for addr in item.get("status",{}).get("addresses",[]):
        if addr.get("type") == "ExternalIP": bad.append(name)
print("\n".join(sorted(set(bad))))')"
if [ -n "$BAD_NODES" ]; then
  echo "ERROR: nodes expose ExternalIP addresses:" >&2
  echo "$BAD_NODES" >&2
  exit 1
fi

echo "OK: Kubernetes nodes have no ExternalIP addresses."

LB_HOST="$(kubectl -n tenant-gateway get svc tenant-policy-gateway-full-stack -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
if [ -n "$LB_HOST" ]; then
  SCHEME="$(aws elbv2 describe-load-balancers --region "$AWS_REGION" --query "LoadBalancers[?DNSName=='$LB_HOST'].Scheme | [0]" --output text 2>/dev/null || true)"
  echo "Tenant gateway LB: $LB_HOST scheme=$SCHEME"
  if [ "${AWS_FULL_GATEWAY_SCHEME:-internal}" = "internal" ] && [ "$SCHEME" != "internal" ]; then
    echo "ERROR: expected internal LoadBalancer scheme but saw $SCHEME" >&2
    exit 1
  fi
else
  echo "WARNING: tenant-policy-gateway-full-stack LoadBalancer has no hostname yet." >&2
fi

if [ -f "$ROOT_DIR/.aws-danger-pod-identity.env" ]; then
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.aws-danger-pod-identity.env"
  aws eks describe-pod-identity-association \
    --region "$AWS_REGION" \
    --cluster-name "$CLUSTER_NAME" \
    --association-id "$GATEWAY_POD_IDENTITY_ASSOCIATION_ID" \
    --query 'association.{namespace:namespace,serviceAccount:serviceAccount,roleArn:roleArn}' \
    --output table
else
  echo "WARNING: missing .aws-danger-pod-identity.env; AWS-native billing pods may lack S3/DynamoDB identity." >&2
fi

VPC_ID="$(aws eks describe-cluster --region "$AWS_REGION" --name "$CLUSTER_NAME" --query 'cluster.resourcesVpcConfig.vpcId' --output text)"
aws ec2 describe-vpc-endpoints --region "$AWS_REGION" --filters Name=vpc-id,Values="$VPC_ID" --query 'VpcEndpoints[].ServiceName' --output table || true

echo "Private networking evidence check complete. This does not prove a complete enterprise private landing zone."
