#!/usr/bin/env bash
set -euo pipefail

repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
}

load_danger_env() {
  local root="$1"
  if [ -f "$root/.aws-danger.env" ]; then
    # shellcheck disable=SC1090
    source "$root/.aws-danger.env"
  fi
}

require_danger_consent() {
  if [ "${I_UNDERSTAND_AWS_GPU_COST_AND_QUOTAS:-}" != "yes" ]; then
    cat >&2 <<'MSG'
Refusing to run the AWS DANGER ZONE path.

This path can create paid EKS, LoadBalancer, EBS, ECR, S3, Cognito, and GPU resources.
It can fail if your account has no GPU quota or if the selected model does not fit the GPU.

Export this exact variable only if you accept that risk:

  export I_UNDERSTAND_AWS_GPU_COST_AND_QUOTAS=yes

For a cheap reviewer demo, use the normal AWS path instead:

  make aws-create-cluster aws-build-push aws-deploy aws-smoke
MSG
    exit 2
  fi
}

require_non_default_cognito_password() {
  if [ -z "${COGNITO_TEST_PASSWORD:-}" ]; then
    cat >&2 <<'MSG'
Refusing to bootstrap Cognito without COGNITO_TEST_PASSWORD.

Set a temporary but non-default password in .aws-danger.env or export it explicitly.
Do not commit .aws-danger.env.
MSG
    exit 2
  fi
  case "$COGNITO_TEST_PASSWORD" in
    ChangeMe-12345\!*|ChangeMe*|Password*|password*|changeme*)
      cat >&2 <<'MSG'
Refusing to use the placeholder/default Cognito test password.

Generate a throwaway password, for example:

  export COGNITO_TEST_PASSWORD="$(openssl rand -base64 24)Aa1!"

Then re-run the bootstrap step.
MSG
      exit 2
      ;;
  esac
}

render_template() {
  local template="$1"
  local output="$2"
  python - "$template" "$output" <<'PY'
from pathlib import Path
from string import Template
import os
import sys
src = Path(sys.argv[1]).read_text(encoding="utf-8")
missing = []
for name in sorted(set(part[1] for part in Template.pattern.findall(src) if part[1])):
    if name not in os.environ:
        missing.append(name)
if missing:
    raise SystemExit(f"template {sys.argv[1]} missing environment variables: {', '.join(missing)}")
Path(sys.argv[2]).write_text(Template(src).substitute(os.environ), encoding="utf-8")
PY
}

ensure_tools() {
  local missing=0
  for bin in "$@"; do
    if ! command -v "$bin" >/dev/null 2>&1; then
      echo "missing required tool: $bin" >&2
      missing=1
    fi
  done
  if [ "$missing" -ne 0 ]; then
    exit 1
  fi
}


download_remote_manifest() {
  local url="$1"
  local output="$2"
  local sha_var_name="${3:-}"
  local expected_sha=""
  mkdir -p "$(dirname "$output")"
  curl -fsSL "$url" -o "$output"
  if [ -n "$sha_var_name" ]; then
    expected_sha="${!sha_var_name:-}"
  fi
  if [ -n "$expected_sha" ]; then
    echo "${expected_sha}  ${output}" | sha256sum -c - >/dev/null
  else
    echo "WARNING: no checksum configured for $url. Version is pinned, but manifest integrity is not cryptographically verified." >&2
  fi
}

apply_remote_manifest() {
  local url="$1"
  local output="$2"
  local sha_var_name="${3:-}"
  local expected_sha=""
  mkdir -p "$(dirname "$output")"
  curl -fsSL "$url" -o "$output"
  if [ -n "$sha_var_name" ]; then
    expected_sha="${!sha_var_name:-}"
  fi
  if [ -n "$expected_sha" ]; then
    echo "${expected_sha}  ${output}" | sha256sum -c - >/dev/null
  else
    echo "WARNING: no checksum configured for $url. Version is pinned, but manifest integrity is not cryptographically verified." >&2
  fi
  kubectl apply -f "$output" --server-side
}

wait_for_gpu_resource() {
  local timeout_seconds="${1:-600}"
  local deadline=$((SECONDS + timeout_seconds))
  echo "waiting for nvidia.com/gpu resource to appear on a Ready node..."
  while [ "$SECONDS" -lt "$deadline" ]; do
    if kubectl get nodes -o json | python -c 'import json,sys; obj=json.load(sys.stdin);
for node in obj.get("items", []):
    alloc=node.get("status", {}).get("allocatable", {}); ready=any(c.get("type")=="Ready" and c.get("status")=="True" for c in node.get("status", {}).get("conditions", []));
    if ready and alloc.get("nvidia.com/gpu"): sys.exit(0)
sys.exit(1)'
    then
      echo "GPU resource is visible."
      return 0
    fi
    sleep 10
  done
  echo "Timed out waiting for nvidia.com/gpu. Check accelerated AMI/device plugin/GPU quota." >&2
  kubectl get nodes -o wide >&2 || true
  kubectl describe nodes >&2 || true
  return 1
}
