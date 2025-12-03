# Deployment Profile Selection Guide

[← Back to Advanced Setup](../ADVANCED_SETUP.md)

The Observability Pipeline supports six deployment profiles to accommodate various infrastructure scenarios. You **MUST** specify a profile when starting the stack because all services are profile-scoped.

## Profile Decision Matrix

| Your Existing Infrastructure | Recommended Profile | Services Deployed                        |
| ---------------------------- | ------------------- | ---------------------------------------- |
| Nothing (greenfield)         | `full`              | Collector + Prometheus + VictoriaMetrics |
| Prometheus only              | `no-prometheus`     | Collector + VictoriaMetrics              |
| VictoriaMetrics only         | `no-vm`             | Collector + Prometheus                   |
| OpenTelemetry Collector only | `no-collector`      | Prometheus + VictoriaMetrics             |
| Prometheus + VictoriaMetrics | `vm-only`           | VictoriaMetrics only                     |
| Storage backend (external)   | `prom-only`         | Prometheus only                          |

---

## PROFILE 1: full (Complete Stack)

**Use When**: Starting from scratch or deploying a self-contained observability stack.

**Services**: OpenTelemetry Collector, Prometheus, VictoriaMetrics

**Command**:

```bash
cd docker-compose
docker compose --profile full up -d
```

**Configuration Required**: None (uses defaults)

**Data Flow**:

```
Apps → Collector (4317/4318) → Prometheus (9090) → VictoriaMetrics (8428)
```

**Verification**:

```bash
# Check all services are running
docker compose ps

# Verify collector health
curl http://localhost:13133/health/status

# Verify Prometheus targets
curl http://localhost:9090/api/v1/targets

# Verify VictoriaMetrics health
curl http://localhost:8428/health
```

**Use Cases**:

- New deployments
- Development/testing environments
- Self-contained observability for single-team projects
- ML inference workloads with no existing monitoring

---

## PROFILE 2: no-prometheus (Integrate with Existing Prometheus)

**Use When**: You have an existing Prometheus instance and want to add trace-to-metrics capability + long-term storage.

**Services**: OpenTelemetry Collector, VictoriaMetrics

**Command**:

```bash
cd docker-compose
docker compose --profile no-prometheus up -d
```

**Configuration Required**:

### 1. Add Collector Scrape Targets to Your Prometheus

Edit your existing `prometheus.yml`:

```yaml
scrape_configs:
  # Scrape spanmetrics (converted from traces)
  - job_name: "otel-collector"
    static_configs:
      - targets: ["<collector-host>:8889"]

  # Scrape collector internal metrics (optional but recommended)
  - job_name: "otel-collector-internal"
    static_configs:
      - targets: ["<collector-host>:8888"]
```

Replace `<collector-host>` with:

- `otel-collector` if your Prometheus is on the same Docker network
- `localhost` if your Prometheus runs on the same host
- The EC2 instance IP/DNS if Prometheus is external

### 2. Configure Remote Write to VictoriaMetrics

```yaml
remote_write:
  - url: http://<victoriametrics-host>:8428/api/v1/write
    # Optional: Configure queue settings for high-throughput scenarios
    queue_config:
      capacity: 10000
      max_shards: 50
      min_shards: 1
      max_samples_per_send: 5000
      batch_send_deadline: 5s
```

Replace `<victoriametrics-host>` with:

- `victoriametrics` if on the same Docker network
- The container/host IP if external

### 3. Network Connectivity

Test from your Prometheus host:

```bash
curl http://<collector-host>:8889/metrics
curl http://<victoriametrics-host>:8428/health
```

**Common Scenarios**:

- Central Prometheus scraping multiple clusters
- Kubernetes clusters with existing Prometheus Operator
- Organizations with standardized Prometheus deployments

---

## PROFILE 3: no-vm (Integrate with Existing VictoriaMetrics)

**Use When**: You have an existing VictoriaMetrics instance (or other long-term storage) and need Prometheus + Collector.

**Services**: OpenTelemetry Collector, Prometheus

**Command**:

```bash
cd docker-compose
docker compose --profile no-vm up -d
```

**Configuration Required**:

### 1. Point Prometheus to Your VictoriaMetrics

Edit `docker-compose/prometheus.yaml`:

```yaml
remote_write:
  - url: http://<your-victoriametrics-host>:8428/api/v1/write
    # Optional: Add authentication if your VM requires it
    # basic_auth:
    #   username: your-username
    #   password: your-password
```

### 2. Network Connectivity

Test from the Prometheus container:

```bash
docker exec prometheus curl http://<your-vm-host>:8428/health
```

**Alternative**: If you don't want long-term storage at all, comment out the `remote_write` block entirely.

**Common Scenarios**:

- Centralized VictoriaMetrics cluster
- Managed VictoriaMetrics service (e.g., VictoriaMetrics Cloud)
- Alternative storage backends (Thanos, Cortex, M3DB)

---

## PROFILE 4: no-collector (Integrate with Existing Collector)

**Use When**: You have an existing OpenTelemetry Collector (perhaps in a Kubernetes daemonset or sidecar) and need Prometheus + VictoriaMetrics for storage.

**Services**: Prometheus, VictoriaMetrics

**Command**:

```bash
cd docker-compose
docker compose --profile no-collector up -d
```

**Configuration Required**:

### 1. Update Your Existing Collector Config

Ensure your collector config includes:

```yaml
exporters:
  prometheus:
    endpoint: "0.0.0.0:8889"
    namespace: llm # Match the namespace used in this stack
    resource_to_telemetry_conversion:
      enabled: true
    enable_open_metrics: true

service:
  telemetry:
    metrics:
      readers:
        - pull:
            exporter:
              prometheus:
                host: 0.0.0.0
                port: 8888

  pipelines:
    metrics:
      receivers: [spanmetrics] # Or your metrics source
      exporters: [prometheus]
```

### 2. Configure Prometheus to Scrape Your Collector

Edit `docker-compose/prometheus.yaml`:

```yaml
scrape_configs:
  - job_name: "otel-collector"
    static_configs:
      - targets: ["<your-collector-host>:8889"]

  - job_name: "otel-collector-internal"
    static_configs:
      - targets: ["<your-collector-host>:8888"]
```

### 3. Ensure OTLP Receivers Are Configured

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318
```

**Common Scenarios**:

- Kubernetes with OpenTelemetry Operator
- Multi-cluster environments with centralized collectors
- Service mesh with sidecar collectors (Istio + OTel)

---

## PROFILE 5: vm-only (VictoriaMetrics Standalone)

**Use When**: You only need VictoriaMetrics for long-term storage and have your own Prometheus + Collector elsewhere.

**Services**: VictoriaMetrics

**Command**:

```bash
cd docker-compose
docker compose --profile vm-only up -d
```

**Configuration Required**:

### Configure Your Prometheus to Remote Write

```yaml
remote_write:
  - url: http://<victoriametrics-host>:8428/api/v1/write
```

**Verification**:

```bash
# Health check
curl http://localhost:8428/health

# Query metrics via Prometheus-compatible API
curl 'http://localhost:8428/api/v1/query?query=up'
```

**Common Scenarios**:

- Consolidating multiple Prometheus instances into one storage backend
- Replacing aging Prometheus storage with VictoriaMetrics
- Cost reduction by centralizing long-term storage

---

## PROFILE 6: prom-only (Prometheus Standalone)

**Use When**: You only need Prometheus for scraping and querying, with external storage or no long-term retention.

**Services**: Prometheus

**Command**:

```bash
cd docker-compose
docker compose --profile prom-only up -d
```

**Configuration Required**:

### 1. Edit Prometheus Config

Edit `docker-compose/prometheus.yaml`:

**a. If you have external storage:**

```yaml
remote_write:
  - url: http://<your-storage-backend>:8428/api/v1/write
```

**b. If you don't need long-term storage:**

```yaml
# Comment out or remove the remote_write block
# remote_write:
#   - url: ...
```

### 2. Configure Scrape Targets

Since the collector is not included, point Prometheus at your own exporters:

```yaml
scrape_configs:
  - job_name: "your-application"
    static_configs:
      - targets:
          - "your-app-host:9100"
          - "another-app:8080"

  # If you have an external OTel Collector
  - job_name: "otel-collector"
    static_configs:
      - targets: ["<external-collector>:8889"]
```

**Common Scenarios**:

- Testing Prometheus configurations
- Temporary monitoring setups
- Development environments with no persistence requirements

---

## Next Steps

- **Configure your chosen profile**: [Configuration Reference](configuration-reference.md)
- **Deploy the stack**: [Deployment Methods](deployment-methods.md)
- **Prepare for production**: [Production Guide](production-guide.md)

[← Back to Advanced Setup](../ADVANCED_SETUP.md)
