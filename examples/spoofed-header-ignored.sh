#!/usr/bin/env bash
set -euo pipefail
BASE_URL="${BASE_URL:-http://localhost:8080}"

# This request is allowed as tenant-a, but the spoofed tenant-b routing headers are stripped and ignored.
# The mock upstream response shows only gateway-derived trusted tenant-a headers.
curl -sS -X POST "$BASE_URL/v1/chat/completions" \
  -H 'Host: tenant-a.example.local' \
  -H 'Authorization: Bearer mock:tenant-a:user-123' \
  -H 'external-filter: tenant=tenant-b' \
  -H 'user: tenant-b:evil' \
  -H 'config-profile: platinum' \
  -H 'x-internal-tenant-id: tenant-b' \
  -H 'x-internal-user-id: evil-user' \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "meta-llama/Llama-3.1-8B-Instruct",
    "lora_adapter": "tenant-a-support",
    "messages": [{"role": "user", "content": "Spoofed headers should not steer routing"}],
    "temperature": 0
  }' | python -m json.tool
