from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def test_danger_zone_runbook_exists_and_warns() -> None:
    runbook = ROOT / "docs" / "11-aws-full-stack-danger-zone.md"
    assert runbook.exists()
    text = runbook.read_text(encoding="utf-8")
    assert "DANGER ZONE" in text
    assert "I_UNDERSTAND_AWS_GPU_COST_AND_QUOTAS=yes" in text
    assert "GPU service quota" in text
    assert "not a production platform" in text
    assert "Audit fixes" in text


def test_danger_zone_env_example_does_not_preaccept_consent_or_password() -> None:
    text = (ROOT / "infra" / "aws" / "full-stack" / "full-stack.env.example").read_text(encoding="utf-8")
    assert "\nI_UNDERSTAND_AWS_GPU_COST_AND_QUOTAS=yes" not in text
    assert "\nI_UNDERSTAND_AWS_GPU_COST_AND_QUOTAS=\n" in text
    assert "COGNITO_TEST_PASSWORD='ChangeMe-12345!'" not in text
    assert "COGNITO_TEST_PASSWORD=" in text


def test_danger_zone_make_targets_exist() -> None:
    makefile = (ROOT / "Makefile").read_text(encoding="utf-8")
    for target in [
        "aws-danger-create-gpu-cluster",
        "aws-danger-oidc",
        "aws-danger-artifacts",
        "aws-danger-install-aibrix",
        "aws-danger-deploy",
        "aws-danger-smoke",
        "aws-danger-destroy",
    ]:
        assert f"{target}:" in makefile


def test_danger_zone_scripts_are_gated_and_executable() -> None:
    script_dir = ROOT / "scripts" / "aws-danger"
    scripts = sorted(script_dir.glob("*.sh"))
    assert scripts
    for script in scripts:
        text = script.read_text(encoding="utf-8")
        assert "require_danger_consent" in text or script.name == "lib.sh"
        assert script.stat().st_mode & 0o111, f"{script} is not executable"


def test_cognito_bootstrap_hardens_tenant_claim() -> None:
    text = (ROOT / "scripts" / "aws-danger" / "02-bootstrap-cognito-oidc.sh").read_text(encoding="utf-8")
    assert "require_non_default_cognito_password" in text
    assert "Mutable=false" in text
    assert "--write-attributes email" in text
    assert "custom:tenant_id is writable" in text
    assert "existing user pool has mutable tenant_id" in text


def test_runtime_install_fails_fast_on_critical_steps() -> None:
    text = (ROOT / "scripts" / "aws-danger" / "04-install-aibrix-platform.sh").read_text(encoding="utf-8")
    assert "rollout status deployment/eg --timeout=300s" in text
    assert "wait_for_gpu_resource" in text
    assert "download_remote_manifest" in text
    assert "kubectl apply -f \"$DEVICE_PLUGIN_MANIFEST\"" in text
    assert "|| true" not in text


def test_generated_aws_danger_secrets_are_gitignored_and_dockerignored() -> None:
    gitignore = (ROOT / ".gitignore").read_text(encoding="utf-8")
    dockerignore = (ROOT / ".dockerignore").read_text(encoding="utf-8")
    for pattern in [".aws-danger.env", ".aws-danger-*.env", ".aws-danger-*.yaml", ".aws-danger-manifests/"]:
        assert pattern in gitignore
        assert pattern in dockerignore


def test_gpu_cluster_manifest_contains_gpu_node_group_taint_and_private_networking() -> None:
    text = (ROOT / "infra" / "aws" / "eksctl" / "cluster-gpu.yaml").read_text(encoding="utf-8")
    assert "gpu-inference" in text
    assert "${GPU_INSTANCE_TYPE}" in text
    assert "nvidia.com/gpu" in text
    assert "DANGER ZONE" in text
    assert "privateNetworking: ${AWS_DANGER_PRIVATE_NETWORKING}" in text


def test_full_stack_templates_wire_oidc_private_upstream_and_real_vllm() -> None:
    tenant_template = (ROOT / "config" / "templates" / "tenants.aws-danger.yaml.tpl").read_text(encoding="utf-8")
    gateway_template = (ROOT / "k8s" / "overlays" / "aws-danger" / "tenant-gateway-full-stack.yaml.tpl").read_text(encoding="utf-8")
    model_template = (ROOT / "k8s" / "aibrix" / "full-stack" / "base-model-deployment.yaml.tpl").read_text(encoding="utf-8")

    assert "${COGNITO_ISSUER}/.well-known/jwks.json" in tenant_template
    assert "tenant_claim: custom:tenant_id" in tenant_template
    assert "APP_AUTH_MODE" in gateway_template and "oidc" in gateway_template
    assert "APP_MOCK_UPSTREAM" in gateway_template and "false" in gateway_template
    assert "${AIBRIX_UPSTREAM_BASE_URL}" in gateway_template
    assert "service.beta.kubernetes.io/aws-load-balancer-type: external" in gateway_template
    assert "service.beta.kubernetes.io/aws-load-balancer-scheme: ${AWS_FULL_GATEWAY_SCHEME}" in gateway_template
    assert "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip" in gateway_template
    assert "service.beta.kubernetes.io/aws-load-balancer-internal" in gateway_template
    assert "model.aibrix.ai/name: ${SERVED_MODEL_NAME}" in model_template
    assert "nvidia.com/gpu" in model_template
    assert "vllm" in model_template
    assert "PodDisruptionBudget" in model_template
    assert "${MODEL_CACHE_VOLUME_SPEC}" in model_template


def test_pr9_pod_identity_and_billing_scripts_exist() -> None:
    script = ROOT / "scripts" / "aws-danger" / "12-bootstrap-gateway-pod-identity.sh"
    assert script.exists()
    text = script.read_text(encoding="utf-8")
    assert "eks-pod-identity-agent" in text
    assert "create-pod-identity-association" in text
    assert "dynamodb:PutItem" in text
    billing = (ROOT / "scripts" / "aws-danger" / "11-create-aws-native-billing-ledger.sh").read_text(encoding="utf-8")
    assert "dynamodb create-table" in billing
    assert "APP_AWS_BILLING_DYNAMODB_TABLE" in billing


def test_pr9_network_policy_allows_required_aws_egress_with_caveat() -> None:
    text = (ROOT / "k8s" / "overlays" / "aws-danger" / "tenant-gateway-full-stack.yaml.tpl").read_text(encoding="utf-8")
    assert "port: 6379" in text
    assert "APP_AWS_BILLING_DYNAMODB_TABLE" in text
    assert "APP_ALLOW_STREAMING_WITHOUT_BILLING_USAGE" in text
    assert "AWS_FULL_OPTIONAL_PUBLIC_HTTPS_EGRESS_CIDR" in text
    assert "Standard Kubernetes NetworkPolicy cannot express FQDN egress" in text


def test_pr9_adapter_verification_evidence_is_required_before_deploy() -> None:
    deploy = (ROOT / "scripts" / "aws-danger" / "05-deploy-gateway-full-stack.sh").read_text(encoding="utf-8")
    verify = (ROOT / "scripts" / "aws-danger" / "10-verify-adapter-artifacts.sh").read_text(encoding="utf-8")
    assert ".aws-danger-adapter-verification.env" in deploy
    assert "APP_ADAPTER_VERIFICATION_ENFORCEMENT" in deploy
    assert "python -m tenant_policy_gateway.adapter_artifact_verifier" in verify
    assert "ADAPTER_VERIFICATION_EVIDENCE_PATH" in verify
