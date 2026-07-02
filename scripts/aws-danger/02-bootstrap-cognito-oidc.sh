#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=./lib.sh
source "$ROOT_DIR/scripts/aws-danger/lib.sh"
load_danger_env "$ROOT_DIR"
require_danger_consent
ensure_tools aws python

: "${AWS_REGION:=eu-west-1}"
: "${CLUSTER_NAME:=aibrix-gateway-full-stack}"
: "${TENANT_A_USERNAME:=tenant-a-alice}"
: "${TENANT_B_USERNAME:=tenant-b-bob}"
: "${COGNITO_REQUIRED_GROUP:=llm-gateway-users}"
require_non_default_cognito_password

POOL_NAME="${CLUSTER_NAME}-tenant-oidc"
CLIENT_NAME="${CLUSTER_NAME}-gateway-client"

USER_POOL_ID="$(aws cognito-idp list-user-pools --region "$AWS_REGION" --max-results 60 \
  --query "UserPools[?Name=='${POOL_NAME}'].Id | [0]" --output text)"
if [ "$USER_POOL_ID" = "None" ] || [ -z "$USER_POOL_ID" ]; then
  USER_POOL_ID="$(aws cognito-idp create-user-pool \
    --region "$AWS_REGION" \
    --pool-name "$POOL_NAME" \
    --mfa-configuration OFF \
    --policies 'PasswordPolicy={MinimumLength=14,RequireUppercase=true,RequireLowercase=true,RequireNumbers=true,RequireSymbols=true,TemporaryPasswordValidityDays=1}' \
    --schema Name=tenant_id,AttributeDataType=String,Mutable=false,Required=false \
    --query 'UserPool.Id' \
    --output text)"
else
  aws cognito-idp describe-user-pool --region "$AWS_REGION" --user-pool-id "$USER_POOL_ID" --output json | python -c 'import json, sys; pool=json.load(sys.stdin)["UserPool"]; attrs=pool.get("SchemaAttributes", []); found=[a for a in attrs if a.get("Name") in {"tenant_id", "custom:tenant_id"}];
if not found: raise SystemExit("existing user pool is missing tenant_id custom attribute; delete it or choose another CLUSTER_NAME");
attr=found[0];
if attr.get("Mutable") is not False: raise SystemExit("existing user pool has mutable tenant_id; delete it or choose another CLUSTER_NAME before using it as a tenant security claim")'
fi

CLIENT_ID="$(aws cognito-idp list-user-pool-clients --region "$AWS_REGION" --user-pool-id "$USER_POOL_ID" --max-results 60 \
  --query "UserPoolClients[?ClientName=='${CLIENT_NAME}'].ClientId | [0]" --output text)"
CLIENT_COMMON_ARGS=(
  --region "$AWS_REGION"
  --user-pool-id "$USER_POOL_ID"
  --client-name "$CLIENT_NAME"
  --explicit-auth-flows ALLOW_USER_PASSWORD_AUTH ALLOW_REFRESH_TOKEN_AUTH
  --prevent-user-existence-errors ENABLED
  --read-attributes email email_verified custom:tenant_id
  --write-attributes email
)
if [ "$CLIENT_ID" = "None" ] || [ -z "$CLIENT_ID" ]; then
  CLIENT_ID="$(aws cognito-idp create-user-pool-client \
    "${CLIENT_COMMON_ARGS[@]}" \
    --no-generate-secret \
    --query 'UserPoolClient.ClientId' \
    --output text)"
else
  aws cognito-idp update-user-pool-client \
    "${CLIENT_COMMON_ARGS[@]}" \
    --client-id "$CLIENT_ID" >/dev/null
fi

validate_client_write_attributes() {
  aws cognito-idp describe-user-pool-client \
    --region "$AWS_REGION" \
    --user-pool-id "$USER_POOL_ID" \
    --client-id "$CLIENT_ID" \
    --output json | python -c 'import json, sys; client=json.load(sys.stdin)["UserPoolClient"]; write=set(client.get("WriteAttributes", [])); read=set(client.get("ReadAttributes", []));
if "custom:tenant_id" in write or "tenant_id" in write: raise SystemExit("unsafe Cognito client: custom:tenant_id is writable");
if "custom:tenant_id" not in read: raise SystemExit("unsafe Cognito client: custom:tenant_id is not readable for tokens")'
}
validate_client_write_attributes

create_or_update_user() {
  local username="$1"
  local tenant="$2"
  aws cognito-idp admin-create-user \
    --region "$AWS_REGION" \
    --user-pool-id "$USER_POOL_ID" \
    --username "$username" \
    --user-attributes Name=email,Value="${username}@example.local" Name=email_verified,Value=true Name=custom:tenant_id,Value="$tenant" \
    --message-action SUPPRESS >/dev/null 2>&1 || true
  aws cognito-idp admin-set-user-password \
    --region "$AWS_REGION" \
    --user-pool-id "$USER_POOL_ID" \
    --username "$username" \
    --password "$COGNITO_TEST_PASSWORD" \
    --permanent >/dev/null
}

aws cognito-idp create-group --region "$AWS_REGION" --user-pool-id "$USER_POOL_ID" --group-name "$COGNITO_REQUIRED_GROUP" >/dev/null 2>&1 || true

create_or_update_user "$TENANT_A_USERNAME" tenant-a
create_or_update_user "$TENANT_B_USERNAME" tenant-b
aws cognito-idp admin-add-user-to-group --region "$AWS_REGION" --user-pool-id "$USER_POOL_ID" --username "$TENANT_A_USERNAME" --group-name "$COGNITO_REQUIRED_GROUP" >/dev/null
aws cognito-idp admin-add-user-to-group --region "$AWS_REGION" --user-pool-id "$USER_POOL_ID" --username "$TENANT_B_USERNAME" --group-name "$COGNITO_REQUIRED_GROUP" >/dev/null

COGNITO_ISSUER="https://cognito-idp.${AWS_REGION}.amazonaws.com/${USER_POOL_ID}"
cat > "$ROOT_DIR/.aws-danger-oidc.env" <<ENV
AWS_REGION=$AWS_REGION
CLUSTER_NAME=$CLUSTER_NAME
COGNITO_USER_POOL_ID=$USER_POOL_ID
COGNITO_CLIENT_ID=$CLIENT_ID
COGNITO_ISSUER=$COGNITO_ISSUER
COGNITO_TEST_PASSWORD='$COGNITO_TEST_PASSWORD'
TENANT_A_USERNAME=$TENANT_A_USERNAME
TENANT_B_USERNAME=$TENANT_B_USERNAME
COGNITO_REQUIRED_GROUP=$COGNITO_REQUIRED_GROUP
ENV

chmod 600 "$ROOT_DIR/.aws-danger-oidc.env"
echo "Cognito OIDC bootstrap complete. Sensitive env saved to $ROOT_DIR/.aws-danger-oidc.env"
echo "Issuer: $COGNITO_ISSUER"
echo "Cognito guardrail: custom:tenant_id is immutable and excluded from client WriteAttributes."
