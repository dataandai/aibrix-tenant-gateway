# Reference image. For production, replace BASE_IMAGE with a digest-pinned image
# such as python:3.11-slim@sha256:<reviewed-digest> and sign the resulting image.
ARG BASE_IMAGE=python:3.11-slim
FROM ${BASE_IMAGE} AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/app/src

WORKDIR /app

RUN groupadd --system --gid 10001 app && \
    useradd --system --uid 10001 --gid app --home-dir /app app

COPY requirements.lock ./requirements.lock
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.lock

COPY src ./src
COPY config ./config

RUN mkdir -p /app/var && chown -R app:app /app

USER 10001:10001

EXPOSE 8080

CMD ["uvicorn", "tenant_policy_gateway.main:app", "--host", "0.0.0.0", "--port", "8080"]
