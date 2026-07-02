from __future__ import annotations

from dataclasses import asdict, dataclass
import json
import logging
from typing import Any

logger = logging.getLogger("tenant_policy_gateway.metering")


@dataclass(frozen=True)
class TokenEstimate:
    """Token count plus provenance.

    `billing_grade` is deliberately false in this MVP. Even when an optional
    tokenizer is available, production billing still needs durable ledgers,
    reconciliation, idempotency, and model-specific tokenizer/version controls.
    """

    value: int
    source: str
    billing_grade: bool = False


@dataclass(frozen=True)
class MeteringEvent:
    request_id: str
    tenant_id: str | None
    user_id: str | None
    domain: str | None
    model: str | None
    adapter: str | None
    decision: str
    status_code: int
    reason: str
    latency_ms: float
    estimated_input_tokens: int | None = None
    estimated_input_token_source: str | None = None
    estimated_input_tokens_billing_grade: bool = False
    estimated_output_tokens: int | None = None
    estimated_output_token_source: str | None = None
    estimated_output_tokens_billing_grade: bool = False
    upstream_status_code: int | None = None


def _collect_text_parts(request_body: dict[str, Any]) -> list[str]:
    text_parts: list[str] = []
    prompt = request_body.get("prompt")
    if isinstance(prompt, str):
        text_parts.append(prompt)
    messages = request_body.get("messages")
    if isinstance(messages, list):
        for item in messages:
            if not isinstance(item, dict):
                continue
            content = item.get("content")
            if isinstance(content, str):
                text_parts.append(content)
            elif isinstance(content, list):
                # Multimodal/chat content is API-shaped but not normalized in this MVP.
                # Keep a deterministic JSON representation for observability only.
                text_parts.append(json.dumps(content, sort_keys=True, separators=(",", ":")))
    return text_parts


def estimate_input_tokens(request_body: dict[str, Any]) -> TokenEstimate | None:
    """Return a best-effort local token estimate for observability.

    This is not billing-grade. If `tiktoken` is installed, the function uses
    `cl100k_base` as a better demo estimate; otherwise it falls back to the
    classic ~4 chars/token heuristic and labels the source accordingly.
    """

    text_parts = _collect_text_parts(request_body)
    if not text_parts:
        return None
    combined = "\n".join(text_parts)
    try:
        import tiktoken  # type: ignore[import-not-found]

        encoder = tiktoken.get_encoding("cl100k_base")
        return TokenEstimate(
            value=max(1, len(encoder.encode(combined))),
            source="optional_tiktoken_cl100k_base_observability_estimate",
        )
    except Exception:
        return TokenEstimate(
            value=max(1, len(combined) // 4),
            source="heuristic_chars_div_4_observability_estimate",
        )


def estimate_input_tokens_from_upstream(response_body: Any) -> TokenEstimate | None:
    if not isinstance(response_body, dict):
        return None
    usage = response_body.get("usage")
    if isinstance(usage, dict):
        prompt_tokens = usage.get("prompt_tokens")
        if isinstance(prompt_tokens, int):
            return TokenEstimate(
                value=prompt_tokens,
                source="upstream_usage_prompt_tokens_unverified",
            )
    return None


def estimate_output_tokens(response_body: Any) -> TokenEstimate | None:
    if not isinstance(response_body, dict):
        return None
    usage = response_body.get("usage")
    if isinstance(usage, dict):
        completion_tokens = usage.get("completion_tokens")
        if isinstance(completion_tokens, int):
            return TokenEstimate(
                value=completion_tokens,
                source="upstream_usage_completion_tokens_unverified",
            )
    return None


def event_fields_from_token_estimate(prefix: str, estimate: TokenEstimate | None) -> dict[str, Any]:
    if estimate is None:
        return {
            f"estimated_{prefix}_tokens": None,
            f"estimated_{prefix}_token_source": None,
            f"estimated_{prefix}_tokens_billing_grade": False,
        }
    return {
        f"estimated_{prefix}_tokens": estimate.value,
        f"estimated_{prefix}_token_source": estimate.source,
        f"estimated_{prefix}_tokens_billing_grade": estimate.billing_grade,
    }


def emit_metering_event(event: MeteringEvent) -> None:
    logger.info(json.dumps(asdict(event), sort_keys=True, separators=(",", ":")))
