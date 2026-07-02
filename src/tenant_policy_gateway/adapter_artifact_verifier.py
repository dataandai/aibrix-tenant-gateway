from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass
from hashlib import sha256
import json
from pathlib import Path
import tempfile
from urllib.parse import urlparse

from .tenant_registry import AdapterArtifactPolicy, TenantRegistry


@dataclass(frozen=True)
class ArtifactVerificationResult:
    ok: bool
    reason: str
    uri: str
    expected_sha256: str | None = None
    actual_sha256: str | None = None


def verify_adapter_artifact(policy: AdapterArtifactPolicy) -> ArtifactVerificationResult:
    """Verify adapter artifact bytes against catalog metadata.

    Supports local file paths and s3:// URIs through boto3. Signature metadata is
    required, but cryptographic KMS/cosign verification is still a future step.
    Use this as a deployment/admission guard, not as a full supply-chain proof.
    """

    if not policy.sha256:
        return ArtifactVerificationResult(False, "adapter_checksum_missing", policy.artifact_uri)
    if not policy.signed_by:
        return ArtifactVerificationResult(False, "adapter_signature_metadata_missing", policy.artifact_uri, policy.sha256)

    parsed = urlparse(policy.artifact_uri)
    if parsed.scheme in {"", "file"}:
        path = Path(parsed.path if parsed.scheme == "file" else policy.artifact_uri)
        if not path.exists():
            return ArtifactVerificationResult(False, "artifact_not_found", policy.artifact_uri, policy.sha256)
        actual = _sha256_file(path)
        return ArtifactVerificationResult(actual == policy.sha256, "sha256_match" if actual == policy.sha256 else "sha256_mismatch", policy.artifact_uri, policy.sha256, actual)

    if parsed.scheme == "s3":
        with tempfile.NamedTemporaryFile(delete=False) as handle:
            temp_path = Path(handle.name)
        try:
            _download_s3_artifact(parsed.netloc, parsed.path.lstrip("/"), temp_path)
            actual = _sha256_file(temp_path)
            return ArtifactVerificationResult(actual == policy.sha256, "sha256_match" if actual == policy.sha256 else "sha256_mismatch", policy.artifact_uri, policy.sha256, actual)
        except Exception as exc:
            return ArtifactVerificationResult(False, f"s3_download_failed:{exc.__class__.__name__}", policy.artifact_uri, policy.sha256)
        finally:
            temp_path.unlink(missing_ok=True)

    return ArtifactVerificationResult(False, "unsupported_artifact_uri_scheme", policy.artifact_uri, policy.sha256)


def verify_registry_adapters(*, registry_path: Path, tenant_id: str | None = None, model: str | None = None) -> list[ArtifactVerificationResult]:
    registry = TenantRegistry.load(registry_path)
    results: list[ArtifactVerificationResult] = []
    tenants = [registry.tenants_by_id[tenant_id]] if tenant_id else list(registry.tenants_by_id.values())
    for tenant in tenants:
        for adapter_name, policy in tenant.adapter_artifacts.items():
            if model is not None and model not in policy.compatible_models:
                continue
            results.append(verify_adapter_artifact(policy))
    return results


def _download_s3_artifact(bucket: str, key: str, output_path: Path) -> None:
    try:
        import boto3  # type: ignore
    except ImportError as exc:  # pragma: no cover
        raise RuntimeError("S3 adapter verification requires boto3") from exc
    boto3.client("s3").download_file(bucket, key, str(output_path))


def _sha256_file(path: Path) -> str:
    digest = sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify adapter artifact checksums from a tenant registry.")
    parser.add_argument("--registry", required=True, type=Path)
    parser.add_argument("--tenant", default=None)
    parser.add_argument("--model", default=None)
    parser.add_argument("--evidence-out", default=None, type=Path)
    args = parser.parse_args()
    results = verify_registry_adapters(registry_path=args.registry, tenant_id=args.tenant, model=args.model)
    payload = {"event": "adapter_artifact_verification", "results": [asdict(result) for result in results]}
    text = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    print(text)
    if args.evidence_out:
        args.evidence_out.parent.mkdir(parents=True, exist_ok=True)
        args.evidence_out.write_text(text + "\n", encoding="utf-8")
    return 0 if results and all(result.ok for result in results) else 1


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
