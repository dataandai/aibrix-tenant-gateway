#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=./lib.sh
source "$ROOT_DIR/scripts/aws-danger/lib.sh"
load_danger_env "$ROOT_DIR"
require_danger_consent
ensure_tools aws kubectl helm curl python

: "${AWS_REGION:=eu-west-1}"
: "${CLUSTER_NAME:=aibrix-gateway-full-stack}"
: "${AIBRIX_VERSION:=v0.7.0}"
: "${AIBRIX_MANIFEST_BASE_URL:=https://github.com/vllm-project/aibrix/releases/download}"
: "${ENVOY_GATEWAY_HELM_VERSION:=v1.2.8}"
: "${NVIDIA_DEVICE_PLUGIN_VERSION:=v0.16.2}"
: "${SKIP_NVIDIA_DEVICE_PLUGIN:=false}"
: "${VLLM_IMAGE:=vllm/vllm-openai:v0.11.0}"
: "${MODEL_ID:=deepseek-ai/DeepSeek-R1-Distill-Llama-8B}"
: "${SERVED_MODEL_NAME:=deepseek-r1-distill-llama-8b}"
: "${MAX_MODEL_LEN:=12288}"
: "${GPU_MEMORY_UTILIZATION:=0.90}"
: "${AIBRIX_MODEL_NAMESPACE:=default}"
: "${MODEL_ROLLOUT_TIMEOUT:=1800s}"
: "${MODEL_CACHE_VOLUME_MODE:=emptyDir}"
: "${MODEL_CACHE_PVC_NAME:=}"

aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" >/dev/null

cat >&2 <<MSG
Installing full-stack runtime components:
  Envoy Gateway chart: $ENVOY_GATEWAY_HELM_VERSION
  AIBrix release:      $AIBRIX_VERSION
  vLLM image:          $VLLM_IMAGE
  model:               $MODEL_ID as $SERVED_MODEL_NAME
  cache mode:          $MODEL_CACHE_VOLUME_MODE

This downloads large images/model weights and requires a working NVIDIA GPU node.
MSG

helm upgrade --install eg oci://docker.io/envoyproxy/gateway-helm \
  --version "$ENVOY_GATEWAY_HELM_VERSION" \
  -n envoy-gateway-system --create-namespace

kubectl apply -f - <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: envoy-gateway-config
  namespace: envoy-gateway-system
data:
  envoy-gateway.yaml: |
    apiVersion: gateway.envoyproxy.io/v1alpha1
    kind: EnvoyGateway
    provider:
      type: Kubernetes
    gateway:
      controllerName: gateway.envoyproxy.io/gatewayclass-controller
    extensionApis:
      enableEnvoyPatchPolicy: true
YAML
kubectl -n envoy-gateway-system rollout restart deployment/eg
kubectl -n envoy-gateway-system rollout status deployment/eg --timeout=300s

MANIFEST_DIR="$ROOT_DIR/.aws-danger-manifests/${AIBRIX_VERSION}"
mkdir -p "$MANIFEST_DIR"
AIBRIX_DEPENDENCY_URL="${AIBRIX_MANIFEST_BASE_URL}/${AIBRIX_VERSION}/aibrix-dependency-${AIBRIX_VERSION}.yaml"
AIBRIX_CRDS_URL="${AIBRIX_MANIFEST_BASE_URL}/${AIBRIX_VERSION}/aibrix-core-crds-${AIBRIX_VERSION}.yaml"
AIBRIX_CORE_URL="${AIBRIX_MANIFEST_BASE_URL}/${AIBRIX_VERSION}/aibrix-core-${AIBRIX_VERSION}.yaml"

download_remote_manifest "$AIBRIX_DEPENDENCY_URL" "$MANIFEST_DIR/aibrix-dependency.yaml" AIBRIX_DEPENDENCY_SHA256
kubectl apply -f "$MANIFEST_DIR/aibrix-dependency.yaml" --server-side

download_remote_manifest "$AIBRIX_CRDS_URL" "$MANIFEST_DIR/aibrix-core-crds.yaml" AIBRIX_CORE_CRDS_SHA256
kubectl apply -f "$MANIFEST_DIR/aibrix-core-crds.yaml" --server-side

download_remote_manifest "$AIBRIX_CORE_URL" "$MANIFEST_DIR/aibrix-core.yaml" AIBRIX_CORE_SHA256
kubectl apply -f "$MANIFEST_DIR/aibrix-core.yaml"

kubectl -n aibrix-system rollout status deployment/aibrix-controller-manager --timeout=300s
kubectl -n aibrix-system get pods

if [ "$SKIP_NVIDIA_DEVICE_PLUGIN" != "true" ]; then
  DEVICE_PLUGIN_MANIFEST="$MANIFEST_DIR/nvidia-device-plugin.yaml"
  download_remote_manifest \
    "https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/${NVIDIA_DEVICE_PLUGIN_VERSION}/deployments/static/nvidia-device-plugin.yml" \
    "$DEVICE_PLUGIN_MANIFEST" \
    NVIDIA_DEVICE_PLUGIN_SHA256
  kubectl apply -f "$DEVICE_PLUGIN_MANIFEST"
else
  echo "SKIP_NVIDIA_DEVICE_PLUGIN=true; assuming the cluster already exposes nvidia.com/gpu." >&2
fi
wait_for_gpu_resource 900

if [ "$AIBRIX_MODEL_NAMESPACE" != "default" ]; then
  kubectl create namespace "$AIBRIX_MODEL_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
fi

if [ -n "${HF_TOKEN:-}" ]; then
  kubectl -n "$AIBRIX_MODEL_NAMESPACE" create secret generic hf-token \
    --from-literal=token="$HF_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -
fi

case "$MODEL_CACHE_VOLUME_MODE" in
  emptyDir)
    MODEL_CACHE_VOLUME_SPEC=$'emptyDir: {}'
    ;;
  efs_pvc|pvc)
    if [ -z "$MODEL_CACHE_PVC_NAME" ]; then
      echo "MODEL_CACHE_VOLUME_MODE=$MODEL_CACHE_VOLUME_MODE requires MODEL_CACHE_PVC_NAME" >&2
      exit 1
    fi
    MODEL_CACHE_VOLUME_SPEC=$'persistentVolumeClaim:\n            claimName: '"$MODEL_CACHE_PVC_NAME"
    ;;
  *)
    echo "unsupported MODEL_CACHE_VOLUME_MODE=$MODEL_CACHE_VOLUME_MODE; use emptyDir or efs_pvc" >&2
    exit 1
    ;;
esac

export VLLM_IMAGE MODEL_ID SERVED_MODEL_NAME MAX_MODEL_LEN GPU_MEMORY_UTILIZATION AIBRIX_MODEL_NAMESPACE MODEL_CACHE_VOLUME_SPEC
RENDERED_MODEL="$ROOT_DIR/.aws-danger-vllm-model.yaml"
render_template "$ROOT_DIR/k8s/aibrix/full-stack/base-model-deployment.yaml.tpl" "$RENDERED_MODEL"
kubectl apply -f "$RENDERED_MODEL"

kubectl -n "$AIBRIX_MODEL_NAMESPACE" rollout status deployment/"$SERVED_MODEL_NAME" --timeout="$MODEL_ROLLOUT_TIMEOUT"

echo "AIBrix/vLLM platform install step complete."
