#!/usr/bin/env bash
set -euo pipefail

missing=0
for bin in aws eksctl kubectl docker curl; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "missing required tool: $bin" >&2
    missing=1
  fi
done

if [ "$missing" -ne 0 ]; then
  cat >&2 <<'MSG'
Install the missing tools first:
  - AWS CLI v2
  - eksctl
  - kubectl
  - Docker
  - curl

Then authenticate to AWS:
  aws configure
  aws sts get-caller-identity
MSG
  exit 1
fi

aws sts get-caller-identity >/dev/null

echo "prerequisites ok"
