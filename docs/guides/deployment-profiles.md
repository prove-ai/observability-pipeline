# Deployment Profile Selection Guide

[← Back to Observability Pipeline Guide](../index.md)

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

**Command**: [Start the profile](#cmd-start-profile) with `--profile full`

**Configuration Required**: None (uses defaults)

**Data Flow**: See [Architecture Guide - Data Flow](architecture.md#data-flow)

**Verification**: [Check service status](#cmd-check-status), then verify with [Health Checks](#ref-health-checks) and [Metrics Validation](#ref-metrics-validation).

**Use Cases**:

- New deployments
- Development/testing environments
- Self-contained observability for single-team projects
- ML inference workloads with no existing monitoring

---

## PROFILE 2: no-prometheus (Integrate with Existing Prometheus)

**Use When**: You have an existing Prometheus instance and want to add trace-to-metrics capability + long-term storage.

**Services**: OpenTelemetry Collector, VictoriaMetrics

**Command**: [Start the profile](#cmd-start-profile) with `--profile no-prometheus`

**Configuration Required**:

1. **Add Collector Scrape Targets**: Apply [Collector Scrape Configuration](#ref-collector-scrape) to your existing `prometheus.yaml`
2. **Configure Remote Write**: Apply [VictoriaMetrics Remote Write Configuration](#ref-vm-remote-write) to your existing `prometheus.yaml`
3. **Verify Connectivity**: Test from your Prometheus host using the Collector and VictoriaMetrics [Health Checks](#ref-health-checks)

**Common Scenarios**:

- Central Prometheus scraping multiple clusters
- Organizations with standardized Prometheus deployments

---

## PROFILE 3: no-vm (Integrate with Existing VictoriaMetrics)

**Use When**: You have an existing VictoriaMetrics instance (or other long-term storage) and need Prometheus + Collector.

**Services**: OpenTelemetry Collector, Prometheus

**Command**: [Start the profile](#cmd-start-profile) with `--profile no-vm`

**Configuration Required**:

1. **Configure Remote Write**: Edit `docker-compose/prometheus.yaml` and apply [VictoriaMetrics Remote Write Configuration](#ref-vm-remote-write) (add basic auth if needed)
2. **Verify Connectivity**: Test from Prometheus container using [Verify from container](#cmd-verify-from-container) command

**Alternative**: If you don't want long-term storage at all, comment out the `remote_write` block entirely.

**Common Scenarios**:

- Centralized VictoriaMetrics cluster
- Managed VictoriaMetrics service (e.g., VictoriaMetrics Cloud)
- Alternative storage backends (Thanos, Cortex, M3DB)
- Hybrid cloud setups (on-prem collectors forwarding to cloud storage) - see [Hybrid Cloud Integration](hybrid-cloud-integration.md)

---

## PROFILE 4: no-collector (Integrate with Existing Collector)

**Use When**: You have an existing OpenTelemetry Collector and need Prometheus + VictoriaMetrics for storage.

**Services**: Prometheus, VictoriaMetrics

**Command**: [Start the profile](#cmd-start-profile) with `--profile no-collector`

**Configuration Required**:

1. **Update Your Collector**: Ensure your existing collector config includes [Collector Configuration](#ref-collector-config) (includes OTLP receivers, Prometheus exporter, and internal metrics)
2. **Configure Prometheus Scraping**: Edit `docker-compose/prometheus.yaml` and apply [Collector Scrape Configuration](#ref-collector-scrape)

**Common Scenarios**:

- Multi-cluster environments with centralized collectors
- Distributed systems with multiple collector instances

---

## PROFILE 5: vm-only (VictoriaMetrics Standalone)

**Use When**: You only need VictoriaMetrics for long-term storage and have your own Prometheus + Collector elsewhere.

**Services**: VictoriaMetrics

**Command**: [Start the profile](#cmd-start-profile) with `--profile vm-only`

**Configuration Required**:

Apply [VictoriaMetrics Remote Write Configuration](#ref-vm-remote-write) to your external Prometheus instance.

**Verification**: Use VictoriaMetrics [Health Checks](#ref-health-checks) and [Metrics Validation](#ref-metrics-validation)

**Common Scenarios**:

- Consolidating multiple Prometheus instances into one storage backend
- Replacing aging Prometheus storage with VictoriaMetrics
- Cost reduction by centralizing long-term storage

---

## PROFILE 6: prom-only (Prometheus Standalone)

**Use When**: You only need Prometheus for scraping and querying, with external storage or no long-term retention.

**Services**: Prometheus

**Command**: [Start the profile](#cmd-start-profile) with `--profile prom-only`

**Configuration Required**:

Edit `docker-compose/prometheus.yaml`:

1. **For external storage**: Apply [VictoriaMetrics Remote Write Configuration](#ref-vm-remote-write) (or configure for your storage backend)
2. **For no long-term storage**: Comment out the `remote_write` block
3. **Configure scrape targets**: Since the collector is not included, point Prometheus at your own exporters:

```yaml
scrape_configs:
  - job_name: "your-application"
    static_configs:
      - targets:
          - "your-app-host:9100"
          - "another-app:8080"
```

If you have an external OTel Collector, apply [Collector Scrape Configuration](#ref-collector-scrape)

**Common Scenarios**:

- Testing Prometheus configurations
- Temporary monitoring setups
- Development environments with no persistence requirements

---

## Command Reference

The commands below are referenced throughout the profile configurations.

### <a id="cmd-start-profile"></a>Start a Profile

```bash
cd docker-compose
docker compose --profile <profile-name> up -d
```

Replace `<profile-name>` with: `full`, `no-prometheus`, `no-vm`, `no-collector`, `vm-only`, or `prom-only`

### <a id="cmd-stop-profile"></a>Stop a Profile

```bash
cd docker-compose
docker compose --profile <profile-name> down
```

### <a id="cmd-check-status"></a>Check Service Status

```bash
docker compose ps
```

### <a id="cmd-view-logs"></a>View Service Logs

```bash
# View all logs
docker compose --profile <profile-name> logs -f

# View specific service logs
docker compose logs -f <service-name>
```

Replace `<service-name>` with: `otel-collector`, `prometheus`, or `victoriametrics`

### <a id="cmd-verify-from-container"></a>Verify from Container

```bash
# Test connectivity from Prometheus container
docker exec prometheus curl http://<your-vm-host>:8428/health

# Test connectivity from any container
docker exec <container-name> curl <target-url>
```

---

## Configuration Reference Blocks

The configuration templates below are referenced throughout the profile configurations. Use these when integrating with your existing infrastructure.

### <a id="ref-collector-scrape"></a>Collector Scrape Configuration

Add this to your Prometheus `scrape_configs`:

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

**Host Resolution for `<collector-host>`:**

- `otel-collector` if on the same Docker network
- `localhost` if running on the same host
- EC2 instance IP/DNS if external

### <a id="ref-vm-remote-write"></a>VictoriaMetrics Remote Write Configuration

Add this to your Prometheus configuration:

```yaml
remote_write:
  - url: http://<victoriametrics-host>:8428/api/v1/write
    # Optional: Add authentication if your VM requires it
    # basic_auth:
    #   username: your-username
    #   password: your-password

    # Optional: Configure queue settings for high-throughput scenarios
    # queue_config:
    #   capacity: 10000
    #   max_shards: 50
    #   min_shards: 1
    #   max_samples_per_send: 5000
    #   batch_send_deadline: 5s
```

**Host Resolution for `<victoriametrics-host>`:**

- `victoriametrics` if on the same Docker network
- Container/host IP if external

**Common Options:**

- Use `basic_auth` when connecting to external/managed VictoriaMetrics instances
- Use `queue_config` to tune performance for high-throughput scenarios

### <a id="ref-collector-config"></a>Collector Configuration

Ensure your collector config includes:

```yaml
exporters:
  prometheus:
    endpoint: "0.0.0.0:8889"
    namespace: llm # Match the namespace used in this stack
    resource_to_telemetry_conversion:
      enabled: true
    enable_open_metrics: true

receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318

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

### <a id="ref-health-checks"></a>Health Checks

Verify that each service is running and responsive:

**Collector:**

```bash
curl http://<host>:13133/health/status
# Expected: {"status":"Server available","upSince":"..."}
```

**Prometheus:**

```bash
# Note: Requires authentication via Envoy
curl -H "X-API-Key: placeholder_api_key" http://<host>:9090/-/healthy
# Expected: HTTP 200 OK with "Prometheus Server is Healthy."
```

For Basic Auth examples, see [Prometheus Commands](reference.md#prometheus-commands).

**VictoriaMetrics:**

```bash
# Note: Requires authentication via Envoy
curl -H "X-API-Key: placeholder_api_key" http://<host>:8428/health
# Expected: OK
```

For Basic Auth examples, see [VictoriaMetrics Commands](reference.md#victoriametrics-commands).

### <a id="ref-metrics-validation"></a>Metrics Validation

Verify that metrics are being collected and flowing through the pipeline:

**Collector Spanmetrics:**

```bash
curl http://<host>:8889/metrics
# Should return Prometheus-formatted metrics including llm_traces_span_metrics_*
```

**Prometheus Scrape Targets:**

```bash
# Note: Requires authentication via Envoy
curl -H "X-API-Key: placeholder_api_key" http://<host>:9090/api/v1/targets
# Check that otel-collector targets show "health":"up"
```

For Basic Auth examples, see [Prometheus Commands](reference.md#prometheus-commands).

**VictoriaMetrics Data:**

```bash
# Note: Requires authentication via Envoy
curl -H "X-API-Key: placeholder_api_key" 'http://<host>:8428/api/v1/query?query=up'
# Verify metrics are stored and queryable
```

For Basic Auth examples, see [VictoriaMetrics Commands](reference.md#victoriametrics-commands).

---

## Next Steps

- **Configure your chosen profile**: [Configuration Reference](configuration-reference.md)
- **Deploy the stack**: [Deployment Guide](deployment-guide.md)
- **Hybrid cloud setup**: [Hybrid Cloud Integration](hybrid-cloud-integration.md)
- **Prepare for production**: [Production Guide](production-guide.md)

[← Back to Observability Pipeline Guide](../index.md)
