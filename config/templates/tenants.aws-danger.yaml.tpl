tenants:
  - tenant_id: tenant-a
    domains:
      - tenant-a.example.local
    oidc_issuer: ${COGNITO_ISSUER}
    oidc_audience: ${COGNITO_CLIENT_ID}
    oidc_jwks_url: ${COGNITO_ISSUER}/.well-known/jwks.json
    tenant_claim: custom:tenant_id
    user_claim: sub
    routing_external_filter: tenant={tenant_id}
    config_profile: gold-gpu
    user_header_template: "{tenant_id}:{user_id}"
    limits:
      requests_per_minute: 20
      input_tokens_per_minute: 50000
      output_tokens_per_minute: 50000
      concurrent_requests: 4
    runtime_isolation:
      mode: aws_full_stack_aibrix_vllm_gpu
      kv_cache_isolation_required: true
      kv_cache_isolation_proven: false
      evidence: null
    adapter_artifacts:
      tenant-a-support:
        artifact_uri: s3://${LORA_ARTIFACT_BUCKET}/tenant-a/support/v1/adapter.safetensors
        sha256: ${TENANT_A_LORA_SHA256}
        signed_by: ${LORA_SIGNING_REFERENCE}
        status: active
        compatible_models:
          - ${SERVED_MODEL_NAME}
    allowed_models:
      ${SERVED_MODEL_NAME}:
        allowed_lora_adapters:
          - tenant-a-support
  - tenant_id: tenant-b
    domains:
      - tenant-b.example.local
    oidc_issuer: ${COGNITO_ISSUER}
    oidc_audience: ${COGNITO_CLIENT_ID}
    oidc_jwks_url: ${COGNITO_ISSUER}/.well-known/jwks.json
    tenant_claim: custom:tenant_id
    user_claim: sub
    routing_external_filter: tenant={tenant_id}
    config_profile: silver-gpu
    user_header_template: "{tenant_id}:{user_id}"
    limits:
      requests_per_minute: 10
      input_tokens_per_minute: 25000
      output_tokens_per_minute: 25000
      concurrent_requests: 2
    runtime_isolation:
      mode: aws_full_stack_aibrix_vllm_gpu
      kv_cache_isolation_required: true
      kv_cache_isolation_proven: false
      evidence: null
    adapter_artifacts:
      tenant-b-support:
        artifact_uri: s3://${LORA_ARTIFACT_BUCKET}/tenant-b/support/v1/adapter.safetensors
        sha256: ${TENANT_B_LORA_SHA256}
        signed_by: ${LORA_SIGNING_REFERENCE}
        status: active
        compatible_models:
          - ${SERVED_MODEL_NAME}
    allowed_models:
      ${SERVED_MODEL_NAME}:
        allowed_lora_adapters:
          - tenant-b-support
