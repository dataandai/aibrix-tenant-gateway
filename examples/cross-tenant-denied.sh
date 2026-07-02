#!/usr/bin/env bash
set -euo pipefail
BASE_URL="${BASE_URL:-http://localhost:8080}"

curl -sS -i -X POST "$BASE_URL/v1/chat/completions" \
  -H 'Host: tenant-b.example.local' \
  -H 'Authorization: Bearer mock:tenant-a:user-123' \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "meta-llama/Llama-3.1-8B-Instruct",
    "lora_adapter": "tenant-b-support",
    "messages": [{"role": "user", "content": "This should fail"}],
    "temperature": 0
  }'
