from __future__ import annotations

from dataclasses import dataclass
import json
from typing import Any, AsyncIterator

import httpx

from .config import AppSettings


@dataclass(frozen=True)
class UpstreamResponse:
    status_code: int
    body: Any
    headers: dict[str, str]


@dataclass(frozen=True)
class StreamChunk:
    data: bytes
    is_first_token: bool = False
    token_count_hint: int = 0


@dataclass(frozen=True)
class UpstreamStream:
    status_code: int
    headers: dict[str, str]
    chunks: AsyncIterator[StreamChunk]


_TRUSTED_HEADER_NAMES = {
    "user",
    "external-filter",
    "config-profile",
    "x-internal-tenant-id",
    "x-internal-user-id",
    "x-internal-kv-cache-isolation-required",
    "x-internal-runtime-isolation-mode",
}


def _visible_mock_headers(headers: dict[str, str]) -> dict[str, str]:
    return {key: value for key, value in headers.items() if key.lower() in _TRUSTED_HEADER_NAMES}


async def forward_to_upstream(
    *,
    path: str,
    body: dict[str, Any],
    headers: dict[str, str],
    settings: AppSettings,
) -> UpstreamResponse:
    if settings.mock_upstream:
        return UpstreamResponse(
            status_code=200,
            body={
                "id": "mock-aibrix-response",
                "object": "mock.upstream.response",
                "model": body.get("model"),
                "upstream": "mock",
                "received_headers": _visible_mock_headers(headers),
                "received_body": body,
                "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2},
            },
            headers={"content-type": "application/json"},
        )

    url = f"{settings.upstream_base_url}{path}"
    async with httpx.AsyncClient(timeout=settings.upstream_timeout_seconds) as client:
        response = await client.post(url, json=body, headers=headers)
    try:
        response_body: Any = response.json()
    except ValueError:
        response_body = {"upstream_text": response.text}
    return UpstreamResponse(
        status_code=response.status_code,
        body=response_body,
        headers={"content-type": response.headers.get("content-type", "application/json")},
    )


async def open_upstream_stream(
    *,
    path: str,
    body: dict[str, Any],
    headers: dict[str, str],
    settings: AppSettings,
) -> UpstreamStream:
    """Open a stream and return the upstream status before downstream streaming starts.

    PR8 forwarded bytes from an iterator that could only expose failures after
    FastAPI had already emitted a 200. This wrapper lets the gateway propagate
    upstream 4xx/5xx status codes on streaming requests.
    """

    if settings.mock_upstream:
        async def mock_chunks() -> AsyncIterator[StreamChunk]:
            payload = {
                "id": "mock-aibrix-stream",
                "object": "chat.completion.chunk",
                "model": body.get("model"),
                "choices": [{"index": 0, "delta": {"content": "hello"}, "finish_reason": None}],
                "received_headers": _visible_mock_headers(headers),
            }
            yield StreamChunk(data=f"data: {json.dumps(payload, separators=(',', ':'))}\n\n".encode("utf-8"), is_first_token=True, token_count_hint=1)
            done = {"choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]}
            yield StreamChunk(data=f"data: {json.dumps(done, separators=(',', ':'))}\n\n".encode("utf-8"))
            yield StreamChunk(data=b"data: [DONE]\n\n")
        return UpstreamStream(status_code=200, headers={"content-type": "text/event-stream"}, chunks=mock_chunks())

    url = f"{settings.upstream_base_url}{path}"
    client = httpx.AsyncClient(timeout=settings.upstream_timeout_seconds)
    stream_context = client.stream("POST", url, json=body, headers=headers)
    response = await stream_context.__aenter__()

    async def real_chunks() -> AsyncIterator[StreamChunk]:
        first = True
        try:
            async for chunk in response.aiter_bytes():
                if not chunk:
                    continue
                yield StreamChunk(data=chunk, is_first_token=first, token_count_hint=1 if first else 0)
                first = False
        finally:
            await stream_context.__aexit__(None, None, None)
            await client.aclose()

    return UpstreamStream(
        status_code=response.status_code,
        headers={"content-type": response.headers.get("content-type", "text/event-stream")},
        chunks=real_chunks(),
    )


async def stream_to_upstream(
    *,
    path: str,
    body: dict[str, Any],
    headers: dict[str, str],
    settings: AppSettings,
) -> AsyncIterator[StreamChunk]:
    """Backward-compatible wrapper used by older tests/integrations."""
    stream = await open_upstream_stream(path=path, body=body, headers=headers, settings=settings)
    async for chunk in stream.chunks:
        yield chunk
