apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: ${SERVED_MODEL_NAME}
  namespace: ${AIBRIX_MODEL_NAMESPACE}
  labels:
    app.kubernetes.io/name: vllm-openai
    app.kubernetes.io/part-of: aibrix-full-stack-danger-zone
spec:
  minAvailable: 1
  selector:
    matchLabels:
      model.aibrix.ai/name: ${SERVED_MODEL_NAME}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${SERVED_MODEL_NAME}
  namespace: ${AIBRIX_MODEL_NAMESPACE}
  labels:
    app.kubernetes.io/name: vllm-openai
    app.kubernetes.io/part-of: aibrix-full-stack-danger-zone
    model.aibrix.ai/name: ${SERVED_MODEL_NAME}
    model.aibrix.ai/port: "8000"
    model.aibrix.ai/engine: vllm
spec:
  replicas: 1
  selector:
    matchLabels:
      model.aibrix.ai/name: ${SERVED_MODEL_NAME}
      model.aibrix.ai/port: "8000"
  template:
    metadata:
      labels:
        app.kubernetes.io/name: vllm-openai
        app.kubernetes.io/part-of: aibrix-full-stack-danger-zone
        model.aibrix.ai/name: ${SERVED_MODEL_NAME}
        model.aibrix.ai/port: "8000"
        model.aibrix.ai/engine: vllm
    spec:
      securityContext:
        seccompProfile:
          type: RuntimeDefault
      tolerations:
        - key: nvidia.com/gpu
          operator: Equal
          value: "true"
          effect: NoSchedule
      nodeSelector:
        workload: llm-inference
      containers:
        - name: vllm-openai
          image: ${VLLM_IMAGE}
          imagePullPolicy: IfNotPresent
          command:
            - vllm
            - serve
            - --host
            - "0.0.0.0"
            - --port
            - "8000"
            - --uvicorn-log-level
            - warning
            - --model
            - ${MODEL_ID}
            - --served-model-name
            - ${SERVED_MODEL_NAME}
            - --max-model-len
            - "${MAX_MODEL_LEN}"
            - --gpu-memory-utilization
            - "${GPU_MEMORY_UTILIZATION}"
            - --download-dir
            - /models
          env:
            - name: HF_TOKEN
              valueFrom:
                secretKeyRef:
                  name: hf-token
                  key: token
                  optional: true
          ports:
            - containerPort: 8000
              name: http
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
          resources:
            requests:
              cpu: "2"
              memory: 12Gi
              ephemeral-storage: 80Gi
              nvidia.com/gpu: "1"
            limits:
              cpu: "8"
              memory: 48Gi
              ephemeral-storage: 220Gi
              nvidia.com/gpu: "1"
          startupProbe:
            httpGet:
              path: /health
              port: http
            failureThreshold: 180
            periodSeconds: 10
            timeoutSeconds: 3
          readinessProbe:
            httpGet:
              path: /health
              port: http
            failureThreshold: 6
            periodSeconds: 10
            timeoutSeconds: 3
          livenessProbe:
            httpGet:
              path: /health
              port: http
            failureThreshold: 6
            periodSeconds: 20
            timeoutSeconds: 3
          volumeMounts:
            - name: model-cache
              mountPath: /models
      volumes:
        - name: model-cache
          ${MODEL_CACHE_VOLUME_SPEC}
