from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import datetime, timezone
import json
from pathlib import Path
from threading import Lock
from typing import Any

from .config import BillingMode


@dataclass(frozen=True)
class UsageTokens:
    prompt_tokens: int
    completion_tokens: int
    total_tokens: int
    source: str


@dataclass(frozen=True)
class BillingLedgerEntry:
    request_id: str
    tenant_id: str
    user_id: str
    model: str
    adapter: str | None
    prompt_tokens: int
    completion_tokens: int
    total_tokens: int
    source: str
    billing_grade_reference: bool
    sink: str


class BillingLedger:
    """Reference ledger with local JSONL and AWS-native S3/Object Lock modes.

    AWS-native mode intentionally uses boto3 instead of shelling out to the AWS
    CLI. This makes the container runtime smaller and forces the deployment to
    use Pod Identity/IRSA credentials. Optional DynamoDB idempotency prevents
    duplicate request IDs from producing duplicate ledger objects.
    """

    def __init__(
        self,
        *,
        mode: BillingMode,
        jsonl_path: Path | None = None,
        aws_s3_bucket: str | None = None,
        aws_s3_prefix: str = "billing-ledger/",
        aws_dynamodb_table: str | None = None,
        aws_region: str | None = None,
    ) -> None:
        self.mode = mode
        self.jsonl_path = jsonl_path
        self.aws_s3_bucket = aws_s3_bucket
        self.aws_s3_prefix = aws_s3_prefix.strip("/") + "/"
        self.aws_dynamodb_table = aws_dynamodb_table
        self.aws_region = aws_region
        self._seen_request_ids: set[str] = set()
        self._lock = Lock()
        self._s3_client: Any | None = None
        self._dynamodb_client: Any | None = None
        if self.mode == BillingMode.LEDGER_REQUIRED and self.jsonl_path is None:
            raise ValueError("ledger_required mode requires jsonl_path")
        if self.mode == BillingMode.AWS_NATIVE_REFERENCE and not self.aws_s3_bucket:
            raise ValueError("aws_native_reference mode requires aws_s3_bucket")
        if self.jsonl_path is not None:
            self.jsonl_path.parent.mkdir(parents=True, exist_ok=True)

    def require_usage_tokens(self, response_body: Any) -> UsageTokens | None:
        if not isinstance(response_body, dict):
            return None
        usage = response_body.get("usage")
        if not isinstance(usage, dict):
            return None
        prompt_tokens = usage.get("prompt_tokens")
        completion_tokens = usage.get("completion_tokens")
        total_tokens = usage.get("total_tokens")
        if not all(isinstance(value, int) and value >= 0 for value in [prompt_tokens, completion_tokens, total_tokens]):
            return None
        if prompt_tokens + completion_tokens != total_tokens:
            return None
        return UsageTokens(
            prompt_tokens=prompt_tokens,
            completion_tokens=completion_tokens,
            total_tokens=total_tokens,
            source="upstream_usage_required",
        )

    def append(
        self,
        *,
        request_id: str,
        tenant_id: str,
        user_id: str,
        model: str,
        adapter: str | None,
        usage: UsageTokens,
    ) -> None:
        if self.mode not in {BillingMode.LEDGER_REQUIRED, BillingMode.AWS_NATIVE_REFERENCE}:
            return
        sink = "s3_object_lock_reference" if self.mode == BillingMode.AWS_NATIVE_REFERENCE else "local_jsonl_reference"
        entry = BillingLedgerEntry(
            request_id=request_id,
            tenant_id=tenant_id,
            user_id=user_id,
            model=model,
            adapter=adapter,
            prompt_tokens=usage.prompt_tokens,
            completion_tokens=usage.completion_tokens,
            total_tokens=usage.total_tokens,
            source=usage.source,
            billing_grade_reference=True,
            sink=sink,
        )
        payload = json.dumps(asdict(entry), sort_keys=True, separators=(",", ":")) + "\n"
        with self._lock:
            if request_id in self._seen_request_ids:
                return
            if self.mode == BillingMode.AWS_NATIVE_REFERENCE:
                if not self._claim_aws_request_id(request_id=request_id, tenant_id=tenant_id):
                    self._seen_request_ids.add(request_id)
                    return
                self._append_s3_object(payload=payload, tenant_id=tenant_id, request_id=request_id)
                self._mark_aws_request_complete(request_id=request_id)
                self._seen_request_ids.add(request_id)
                return
            self._seen_request_ids.add(request_id)
            assert self.jsonl_path is not None
            with self.jsonl_path.open("a", encoding="utf-8") as handle:
                handle.write(payload)

    def _claim_aws_request_id(self, *, request_id: str, tenant_id: str) -> bool:
        if not self.aws_dynamodb_table:
            return True
        client = self._dynamodb()
        try:
            client.put_item(
                TableName=self.aws_dynamodb_table,
                Item={
                    "request_id": {"S": request_id},
                    "tenant_id": {"S": tenant_id},
                    "status": {"S": "writing"},
                    "created_at": {"S": datetime.now(timezone.utc).isoformat()},
                },
                ConditionExpression="attribute_not_exists(request_id)",
            )
            return True
        except Exception as exc:  # boto3 conditional failure classes vary by generated client.
            if exc.__class__.__name__ == "ConditionalCheckFailedException" or "ConditionalCheckFailed" in str(exc):
                return False
            raise

    def _mark_aws_request_complete(self, *, request_id: str) -> None:
        if not self.aws_dynamodb_table:
            return
        self._dynamodb().update_item(
            TableName=self.aws_dynamodb_table,
            Key={"request_id": {"S": request_id}},
            UpdateExpression="SET #s = :complete, completed_at = :completed_at",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={
                ":complete": {"S": "complete"},
                ":completed_at": {"S": datetime.now(timezone.utc).isoformat()},
            },
        )

    def _append_s3_object(self, *, payload: str, tenant_id: str, request_id: str) -> None:
        assert self.aws_s3_bucket is not None
        now = datetime.now(timezone.utc)
        key = (
            f"{self.aws_s3_prefix}tenant_id={tenant_id}/"
            f"date={now.strftime('%Y-%m-%d')}/{request_id}.jsonl"
        )
        self._s3().put_object(
            Bucket=self.aws_s3_bucket,
            Key=key,
            Body=payload.encode("utf-8"),
            ContentType="application/jsonl",
            ServerSideEncryption="AES256",
            Metadata={"request_id": request_id, "tenant_id": tenant_id},
        )

    def _s3(self) -> Any:
        if self._s3_client is None:
            self._s3_client = _boto3_client("s3", self.aws_region)
        return self._s3_client

    def _dynamodb(self) -> Any:
        if self._dynamodb_client is None:
            self._dynamodb_client = _boto3_client("dynamodb", self.aws_region)
        return self._dynamodb_client


def _boto3_client(service: str, region_name: str | None) -> Any:
    try:
        import boto3  # type: ignore
    except ImportError as exc:  # pragma: no cover - only selected in AWS-native mode without dependency
        raise RuntimeError("APP_BILLING_MODE=aws_native_reference requires boto3 in the gateway image") from exc
    kwargs = {"region_name": region_name} if region_name else {}
    return boto3.client(service, **kwargs)
