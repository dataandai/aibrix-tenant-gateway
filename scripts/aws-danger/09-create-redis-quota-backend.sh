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
: "${REDIS_NODE_TYPE:=cache.t4g.micro}"
: "${REDIS_ENGINE_VERSION:=7.1}"
: "${REDIS_REPLICATION_GROUP_ID:=${CLUSTER_NAME}-quota}"
: "${REDIS_PORT:=6379}"

VPC_ID="$(aws eks describe-cluster --region "$AWS_REGION" --name "$CLUSTER_NAME" --query 'cluster.resourcesVpcConfig.vpcId' --output text)"
SUBNETS="$(aws eks describe-cluster --region "$AWS_REGION" --name "$CLUSTER_NAME" --query 'cluster.resourcesVpcConfig.subnetIds' --output text)"
SG_ID="$(aws ec2 create-security-group --region "$AWS_REGION" --group-name "${CLUSTER_NAME}-redis-quota" --description "Redis quota backend for ${CLUSTER_NAME}" --vpc-id "$VPC_ID" --query GroupId --output text 2>/dev/null || aws ec2 describe-security-groups --region "$AWS_REGION" --filters Name=group-name,Values="${CLUSTER_NAME}-redis-quota" Name=vpc-id,Values="$VPC_ID" --query 'SecurityGroups[0].GroupId' --output text)"
CLUSTER_SG="$(aws eks describe-cluster --region "$AWS_REGION" --name "$CLUSTER_NAME" --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)"
aws ec2 authorize-security-group-ingress --region "$AWS_REGION" --group-id "$SG_ID" --protocol tcp --port "$REDIS_PORT" --source-group "$CLUSTER_SG" >/dev/null 2>&1 || true

SUBNET_GROUP="${CLUSTER_NAME}-redis-subnets"
aws elasticache create-cache-subnet-group --region "$AWS_REGION" --cache-subnet-group-name "$SUBNET_GROUP" --cache-subnet-group-description "Redis quota subnets for ${CLUSTER_NAME}" --subnet-ids $SUBNETS >/dev/null 2>&1 || true

if ! aws elasticache describe-replication-groups --region "$AWS_REGION" --replication-group-id "$REDIS_REPLICATION_GROUP_ID" >/dev/null 2>&1; then
  aws elasticache create-replication-group \
    --region "$AWS_REGION" \
    --replication-group-id "$REDIS_REPLICATION_GROUP_ID" \
    --replication-group-description "Tenant Policy Gateway quota backend" \
    --engine redis \
    --engine-version "$REDIS_ENGINE_VERSION" \
    --cache-node-type "$REDIS_NODE_TYPE" \
    --num-cache-clusters 1 \
    --cache-subnet-group-name "$SUBNET_GROUP" \
    --security-group-ids "$SG_ID" \
    --at-rest-encryption-enabled \
    --transit-encryption-enabled >/dev/null
fi

aws elasticache wait replication-group-available --region "$AWS_REGION" --replication-group-id "$REDIS_REPLICATION_GROUP_ID"
REDIS_HOST="$(aws elasticache describe-replication-groups --region "$AWS_REGION" --replication-group-id "$REDIS_REPLICATION_GROUP_ID" --query 'ReplicationGroups[0].NodeGroups[0].PrimaryEndpoint.Address' --output text)"
REDIS_URL="rediss://${REDIS_HOST}:${REDIS_PORT}/0"
cat > "$ROOT_DIR/.aws-danger-redis.env" <<ENV
APP_QUOTA_MODE=redis
APP_REDIS_QUOTA_URL=$REDIS_URL
REDIS_REPLICATION_GROUP_ID=$REDIS_REPLICATION_GROUP_ID
ENV

echo "Redis quota backend available: $REDIS_URL"
