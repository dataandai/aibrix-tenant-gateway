apiVersion: v1
kind: Namespace
metadata:
  name: tenant-gateway
  labels:
    name: tenant-gateway
    app.kubernetes.io/part-of: aibrix-multitenant-llm-gateway
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tenant-policy-gateway
  namespace: tenant-gateway
  labels:
    app.kubernetes.io/name: tenant-policy-gateway
  annotations:
    eks.amazonaws.com/role-arn: "${GATEWAY_IRSA_ROLE_ARN}"
---
apiVersion: v1
kind: Secret
metadata:
  name: redis-quota-url
  namespace: tenant-gateway
type: Opaque
stringData:
  redis-url: ${APP_REDIS_QUOTA_URL}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tenant-policy-gateway
  namespace: tenant-gateway
  labels:
    app.kubernetes.io/name: tenant-policy-gateway
  annotations:
    eks.amazonaws.com/role-arn: "${GATEWAY_IRSA_ROLE_ARN}"
    app.kubernetes.io/part-of: aibrix-multitenant-llm-gateway
spec:
  replicas: 2
  selector:
    matchLabels:
      app.kubernetes.io/name: tenant-policy-gateway
  template:
    metadata:
      labels:
        app.kubernetes.io/name: tenant-policy-gateway
    spec:
      serviceAccountName: tenant-policy-gateway
      containers:
        - name: gateway
          image: ${IMAGE_URI}
          imagePullPolicy: Always
          ports:
            - name: http
              containerPort: 8080
          env:
            - name: APP_TENANT_REGISTRY_PATH
              value: /app/config/tenants.yaml
            - name: APP_AUTH_MODE
              value: oidc
            - name: APP_ENVIRONMENT
              value: staging
            - name: APP_MOCK_UPSTREAM
              value: "false"
            - name: APP_UPSTREAM_BASE_URL
              value: ${AIBRIX_UPSTREAM_BASE_URL}
            - name: APP_UPSTREAM_TIMEOUT_SECONDS
              value: "120"
            - name: APP_QUOTA_MODE
              value: ${APP_QUOTA_MODE}
            - name: APP_REDIS_QUOTA_URL
              valueFrom:
                secretKeyRef:
                  name: redis-quota-url
                  key: redis-url
            - name: APP_BILLING_MODE
              value: ${APP_BILLING_MODE}
            - name: APP_AWS_BILLING_S3_BUCKET
              value: ${APP_AWS_BILLING_S3_BUCKET}
            - name: APP_AWS_BILLING_S3_PREFIX
              value: ${APP_AWS_BILLING_S3_PREFIX}
            - name: APP_AWS_BILLING_DYNAMODB_TABLE
              value: ${APP_AWS_BILLING_DYNAMODB_TABLE}
            - name: AWS_REGION
              value: ${AWS_REGION}
            - name: APP_ALLOW_STREAMING_WITHOUT_BILLING_USAGE
              value: "false"
            - name: APP_OIDC_REQUIRED_TOKEN_USE
              value: id
            - name: APP_OIDC_REQUIRED_GROUPS
              value: ${COGNITO_REQUIRED_GROUP}
            - name: APP_OIDC_LEEWAY_SECONDS
              value: "60"
            - name: APP_OIDC_REQUIRE_NBF
              value: "false"
            - name: APP_JWKS_CACHE_TTL_SECONDS
              value: "300"
            - name: APP_AUDIT_SINK
              value: stdout
            - name: APP_ADAPTER_GOVERNANCE_MODE
              value: catalog_enforced
            - name: APP_SECURITY_POSTURE_MODE
              value: enforce
            - name: APP_REQUIRE_PRIVATE_UPSTREAM
              value: "true"
            - name: APP_LOG_LEVEL
              value: INFO
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            runAsNonRoot: true
            runAsUser: 10001
            capabilities:
              drop:
                - ALL
          volumeMounts:
            - name: tenant-registry
              mountPath: /app/config
              readOnly: true
            - name: runtime-var
              mountPath: /app/var
          readinessProbe:
            httpGet:
              path: /readyz
              port: http
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /healthz
              port: http
            initialDelaySeconds: 5
            periodSeconds: 20
          resources:
            requests:
              cpu: 500m
              memory: 512Mi
            limits:
              cpu: "2"
              memory: 1Gi
      securityContext:
        seccompProfile:
          type: RuntimeDefault
      volumes:
        - name: tenant-registry
          configMap:
            name: tenant-registry
        - name: runtime-var
          emptyDir:
            medium: Memory
---
apiVersion: v1
kind: Service
metadata:
  name: tenant-policy-gateway-full-stack
  namespace: tenant-gateway
  labels:
    app.kubernetes.io/name: tenant-policy-gateway
    app.kubernetes.io/part-of: aibrix-multitenant-llm-gateway
  annotations:
    # Works with AWS Load Balancer Controller-style NLB annotations when installed.
    service.beta.kubernetes.io/aws-load-balancer-type: external
    service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: ip
    service.beta.kubernetes.io/aws-load-balancer-scheme: ${AWS_FULL_GATEWAY_SCHEME}
    # Legacy in-tree cloud-provider fallback for internal LBs.
    service.beta.kubernetes.io/aws-load-balancer-internal: "${AWS_FULL_GATEWAY_INTERNAL_LEGACY}"
spec:
  type: LoadBalancer
  selector:
    app.kubernetes.io/name: tenant-policy-gateway
  ports:
    - name: http
      port: 80
      targetPort: http
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: tenant-policy-gateway-full-stack-egress
  namespace: tenant-gateway
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: tenant-policy-gateway
  policyTypes:
    - Egress
  egress:
    # DNS for Kubernetes service discovery.
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
    # AIBrix/Envoy upstream inside the cluster.
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: envoy-gateway-system
      ports:
        - protocol: TCP
          port: 80
        - protocol: TCP
          port: 8080
    # Private RFC1918 egress for ElastiCache Redis, VPC endpoints, and internal AWS service endpoints.
    # Standard Kubernetes NetworkPolicy cannot express FQDN egress for Cognito/JWKS; for strict
    # production use Cilium/Calico enterprise FQDN policy or route AWS API traffic through VPC endpoints/NAT.
    - to:
        - ipBlock:
            cidr: 10.0.0.0/8
        - ipBlock:
            cidr: 172.16.0.0/12
        - ipBlock:
            cidr: 192.168.0.0/16
      ports:
        - protocol: TCP
          port: 443
        - protocol: TCP
          port: 6379
        - protocol: TCP
          port: 80
    # Optional public HTTPS egress for Cognito/JWKS when the lab VPC uses NAT rather than FQDN-aware policy.
    # Remove this in a locked-down landing zone and replace it with Cilium/Calico FQDN or private endpoint routing.
    - to:
        - ipBlock:
            cidr: ${AWS_FULL_OPTIONAL_PUBLIC_HTTPS_EGRESS_CIDR}
      ports:
        - protocol: TCP
          port: 443
