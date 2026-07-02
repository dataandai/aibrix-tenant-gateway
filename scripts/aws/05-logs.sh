#!/usr/bin/env bash
set -euo pipefail
kubectl -n tenant-gateway logs deployment/tenant-policy-gateway --tail=200 -f
