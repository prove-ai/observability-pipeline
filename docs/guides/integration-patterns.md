# Advanced Integration Patterns

[← Back to Advanced Setup](../ADVANCED_SETUP.md)

This guide describes advanced deployment patterns for integrating the Observability Pipeline with complex infrastructure scenarios.

## Pattern 1: Hybrid Cloud (On-Prem + Cloud)

**Scenario**: On-premises applications send traces to cloud-hosted Observability Pipeline.

### Architecture

```
On-Premises:
  Apps → On-Prem Collector →
↓ (Secure tunnel: VPN / Direct Connect)
Cloud (AWS):
  Central Collector → Prometheus → VictoriaMetrics
```

### Implementation

#### 1. Deploy On-Prem Collector with Forward Exporter

Configure the on-prem collector to forward to cloud:

```yaml
exporters:
  otlp:
    endpoint: <cloud-collector>:4317
    tls:
      insecure: false
      cert_file: /etc/otel/certs/client.crt
      key_file: /etc/otel/certs/client.key

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [otlp] # Forward to cloud
```

#### 2. Deploy Cloud Collector with Full Stack

```bash
docker compose --profile full up -d
```

#### 3. Configure Network Connectivity

- Set up VPN or AWS Direct Connect between on-prem and cloud
- Ensure security groups allow OTLP traffic (4317)
- Consider TLS for data in transit

---

**⚠️ TODO:** The following integration patterns are untested and may be removed. Testing and validation required.

---

## Pattern 2: Edge-to-Core Aggregation

**Scenario**: Multiple edge locations send metrics to a central core for aggregation.

### Architecture

```
Edge Location 1:
  Apps → Collector → Local Prometheus →
Edge Location 2:
  Apps → Collector → Local Prometheus →
Edge Location N:
  Apps → Collector → Local Prometheus →
↓ remote_write
Core (Central):
  VictoriaMetrics (aggregates all edges)
```

### Implementation

#### 1. Deploy at Each Edge (use no-vm profile)

```bash
docker compose --profile no-vm up -d
```

#### 2. Configure Edge Prometheus to Remote Write to Core

```yaml
global:
  external_labels:
    edge_location: location-1 # Unique per edge
    environment: production

remote_write:
  - url: http://<core-vm>:8428/api/v1/write
    queue_config:
      capacity: 100000
      max_shards: 200
```

#### 3. Deploy Core VictoriaMetrics

```bash
docker compose --profile vm-only up -d
```

## Pattern 3: Multi-Region Deployment with Central Storage

**Scenario**: Deploy collectors in multiple AWS regions, scrape with regional Prometheus instances, aggregate in central VictoriaMetrics.

### Architecture

```
Region 1 (us-east-1):
  Collector → Prometheus → remote_write → Central VM

Region 2 (eu-west-1):
  Collector → Prometheus → remote_write → Central VM

Central Region (us-east-1):
  VictoriaMetrics (aggregates all regions)
```

### Implementation

#### 1. Deploy in Each Region (use no-vm profile)

```bash
# On each regional deployment
docker compose --profile no-vm up -d
```

#### 2. Configure Regional Prometheus to Point to Central VM

Edit `prometheus.yaml` in each region:

```yaml
global:
  external_labels:
    region: us-east-1 # Change per region
    environment: production

remote_write:
  - url: http://<central-vm-host>:8428/api/v1/write
    queue_config:
      capacity: 50000
      max_shards: 100
```

#### 3. Deploy Central VictoriaMetrics

```bash
docker compose --profile vm-only up -d
```

#### 4. Query Across Regions

```promql
# Query all regions
sum by (service_name) (llm_traces_span_metrics_calls_total)

# Query specific region
llm_traces_span_metrics_calls_total{region="us-east-1"}
```

## Pattern 4: Kubernetes Integration

**Scenario**: Deploy collectors in Kubernetes, use the Observability Pipeline for storage and querying.

### Architecture

```
Kubernetes Cluster:
  Pods → OTel Collector (DaemonSet) →
↓
External:
  Prometheus (scrapes via NodePort/LoadBalancer)
  VictoriaMetrics (long-term storage)
```

### Implementation

#### 1. Deploy OTel Collector in Kubernetes

Use the OpenTelemetry Operator or deploy as a DaemonSet:

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: otel-collector
  namespace: observability
spec:
  selector:
    matchLabels:
      app: otel-collector
  template:
    metadata:
      labels:
        app: otel-collector
    spec:
      containers:
        - name: otel-collector
          image: otel/opentelemetry-collector-contrib:0.138.0
          ports:
            - containerPort: 4317 # OTLP gRPC
            - containerPort: 8889 # Prometheus metrics
          volumeMounts:
            - name: config
              mountPath: /etc/otel
      volumes:
        - name: config
          configMap:
            name: otel-collector-config
```

#### 2. Expose Collector via Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: otel-collector
  namespace: observability
spec:
  type: NodePort
  selector:
    app: otel-collector
  ports:
    - name: otlp-grpc
      port: 4317
      targetPort: 4317
      nodePort: 30317
    - name: metrics
      port: 8889
      targetPort: 8889
      nodePort: 30889
```

#### 3. Configure External Prometheus to Scrape Kubernetes Collector

```yaml
scrape_configs:
  - job_name: "k8s-otel-collector"
    static_configs:
      - targets: ["<k8s-node-ip>:30889"]
```

#### 4. Deploy External Storage

```bash
# Deploy Prometheus + VictoriaMetrics externally
docker compose --profile no-collector up -d
```

---

#### 4. Query Across Edge Locations

```promql
# Query all edges
sum by (service_name) (llm_traces_span_metrics_calls_total)

# Query specific edge
llm_traces_span_metrics_calls_total{edge_location="location-1"}
```

---

## Pattern 5: Service Mesh Integration (Istio)

**Scenario**: Integrate with Istio service mesh for automatic trace collection.

### Architecture

```
Kubernetes with Istio:
  Pods → Envoy Sidecars (generate traces) →
↓
OTel Collector (receives Zipkin/Jaeger) →
↓
Observability Pipeline (Prometheus + VictoriaMetrics)
```

### Implementation

#### 1. Configure Istio to Send Traces to OTel Collector

```yaml
apiVersion: install.istio.io/v1alpha1
kind: IstioOperator
spec:
  meshConfig:
    defaultConfig:
      tracing:
        zipkin:
          address: otel-collector.observability:9411
    enableTracing: true
    sampling: 100.0 # Adjust sampling rate
```

#### 2. Configure OTel Collector with Zipkin Receiver

```yaml
receivers:
  zipkin:
    endpoint: 0.0.0.0:9411

service:
  pipelines:
    traces:
      receivers: [zipkin, otlp]
      processors: [batch]
      exporters: [spanmetrics, debug]
```

#### 3. Expose Zipkin Port in Docker Compose

```yaml
otel-collector:
  ports:
    - 9411:9411 # Zipkin
```

---

## Pattern 6: Multi-Tenant Isolation

**Scenario**: Separate metrics by tenant/customer for isolation and billing.

### Implementation

#### 1. Add Tenant ID to Spans

In your application:

```python
from opentelemetry import trace

tracer = trace.get_tracer(__name__)
with tracer.start_as_current_span("operation") as span:
    span.set_attribute("tenant_id", "customer-123")
```

#### 2. Configure Spanmetrics with Tenant Dimension

```yaml
connectors:
  spanmetrics:
    dimensions:
      - name: tenant_id
      - name: environment
      - name: service_name
    dimensions_cache_size: 10000
```

#### 3. Query Per-Tenant Metrics

```promql
# Query specific tenant
llm_traces_span_metrics_calls_total{tenant_id="customer-123"}

# Query all tenants
sum by (tenant_id) (rate(llm_traces_span_metrics_calls_total[5m]))
```

#### 4. Optional: Filter Tenants in Prometheus

```yaml
scrape_configs:
  - job_name: "otel-collector"
    static_configs:
      - targets: ["otel-collector:8889"]
    metric_relabel_configs:
      # Drop internal tenant metrics
      - source_labels: [tenant_id]
        regex: "internal.*"
        action: drop
```

---

## Next Steps

- **Prepare for production**: [Production Guide](production-guide.md)
- **Secure your deployment**: [Security Guide](security.md)
- **Reference materials**: [Reference Guide](reference.md)

[← Back to Advanced Setup](../ADVANCED_SETUP.md)
