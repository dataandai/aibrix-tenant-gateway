from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def test_aws_demo_runbook_exists_and_is_explicitly_non_production() -> None:
    text = (ROOT / "docs/09-aws-demo-runbook.md").read_text()
    assert "CPU-only AWS demo" in text
    assert "not production-secure" in text
    assert "scripts/aws/99-destroy-demo.sh" in text


def test_aws_demo_manifest_uses_explicit_mock_demo_guardrails() -> None:
    manifest = (ROOT / "k8s/overlays/aws-demo/tenant-gateway-aws-demo.yaml").read_text()
    assert "APP_AUTH_MODE" in manifest
    assert "value: mock" in manifest
    assert "APP_UNSAFE_ALLOW_MOCK_AUTH_OUTSIDE_LOCAL" in manifest
    assert 'value: "true"' in manifest
    assert "APP_MOCK_UPSTREAM" in manifest
    assert "APP_SECURITY_POSTURE_MODE" in manifest
    assert "value: audit" in manifest
    assert "tenant-policy-gateway-public" in manifest
    assert "type: LoadBalancer" in manifest


def test_aws_scripts_exist_and_are_executable() -> None:
    scripts = [
        "00-check-prereqs.sh",
        "01-create-cluster.sh",
        "02-build-push-ecr.sh",
        "03-deploy-demo.sh",
        "04-smoke-test.sh",
        "05-logs.sh",
        "99-destroy-demo.sh",
    ]
    for name in scripts:
        path = ROOT / "scripts/aws" / name
        assert path.exists(), name
        assert path.stat().st_mode & 0o111, name
