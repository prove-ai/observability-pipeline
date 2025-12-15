# Configuration Reference Guide

[← Back to Advanced Setup](../ADVANCED_SETUP.md)

This comprehensive reference provides all configuration options for tuning the Observability Pipeline components. Use this guide to customize the default setup for your specific requirements.

## Quick Navigation

| Component                                                         | Configuration File                          | Common Configurations                   |
| ----------------------------------------------------------------- | ------------------------------------------- | --------------------------------------- |
| [OpenTelemetry Collector](#opentelemetry-collector-configuration) | `docker-compose/otel-collector-config.yaml` | Receivers, processors, spanmetrics      |
| [Prometheus](#prometheus-configuration)                           | `docker-compose/prometheus.yaml`            | Scrape intervals, remote write, targets |
| [VictoriaMetrics](#victoriametrics-configuration)                 | `docker-compose/docker-compose.yaml`        | Retention, memory limits                |

## Configuration Strategy

Before making changes, understand the impact:

| Change Type            | Impact Level | When to Apply                           | Restart Required     |
| ---------------------- | ------------ | --------------------------------------- | -------------------- |
| Receiver ports         | Low          | During initial setup                    | Yes                  |
| Batch processor        | Medium       | Performance tuning                      | Yes                  |
| Spanmetrics dimensions | High         | Before production (affects cardinality) | Yes                  |
| Scrape intervals       | Medium       | After load testing                      | Prometheus only      |
| Retention periods      | Low          | Capacity planning                       | VictoriaMetrics only |

---

## OpenTelemetry Collector Configuration

**File Location:** `docker-compose/otel-collector-config.yaml`

**Collector Version:** `otel/opentelemetry-collector-contrib:0.138.0`

**When to Edit:** Initial setup, adding dimensions, performance tuning

### Configuration Overview

The collector has 5 main sections:

```
┌─────────────────────────────────────┐
│ 1. Receivers (How traces come in)   │
├─────────────────────────────────────┤
│ 2. Processors (How traces are       │
│    batched and filtered)            │
├─────────────────────────────────────┤
│ 3. Connectors (Spanmetrics:         │
│    traces → metrics)                │
├─────────────────────────────────────┤
│ 4. Exporters (Where data goes)      │
├─────────────────────────────────────┤
│ 5. Service Pipelines (Connect       │
│    everything together)             │
└─────────────────────────────────────┘
```

---

### 1. Receivers (Trace Ingestion)

**Purpose:** Define how applications send traces to the collector.

**Default Configuration:**

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318
```

#### Receiver Configuration Variables

| Parameter                | Type   | Default        | Description                   | When to Change                                        |
| ------------------------ | ------ | -------------- | ----------------------------- | ----------------------------------------------------- |
| `endpoint`               | string | `0.0.0.0:4317` | IP and port to bind           | Change IP to restrict access (e.g., `127.0.0.1:4317`) |
| `max_recv_msg_size_mib`  | int    | 4              | Max gRPC message size (MB)    | Increase if you have large traces (100+ spans)        |
| `max_concurrent_streams` | int    | 100            | Max parallel gRPC connections | Increase for high-concurrency applications            |

#### Common Receiver Configurations

**Scenario 1: Large Traces (ML/Batch Jobs)**

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
        max_recv_msg_size_mib: 16 # Allow larger messages
        max_concurrent_streams: 200
```

**Configuration Properties**

All three properties are officially supported in the OTLP receiver:

- **`endpoint`:** Configures the gRPC server listening address
- **`max_recv_msg_size_mib`:** Maximum message size in MiB (useful for large traces from ML/batch jobs)
- **`max_concurrent_streams`:** Maximum concurrent gRPC streams per connection

**Documentation References:**

- [OTLP Receiver Configuration](https://github.com/open-telemetry/opentelemetry-collector/blob/main/receiver/otlpreceiver/config.md)
- [Version 0.138.0 Release](https://github.com/open-telemetry/opentelemetry-collector-contrib/releases/tag/v0.138.0)

**Note:** The OpenTelemetry Collector Contrib distribution includes all core collector components, ensuring these configuration options are available.

**Scenario 2: Browser-Based Applications (CORS)**

```yaml
receivers:
  otlp:
    protocols:
      http:
        endpoint: 0.0.0.0:4318
        cors:
          allowed_origins:
            - "https://app.example.com"
            - "https://staging.example.com"
          allowed_headers:
            - "Content-Type"
```

**Configuration Properties**

All CORS properties are officially supported in the OTLP HTTP receiver:

- **`endpoint`:** HTTP server listening address (default: `localhost:4318`)
- **`cors.allowed_origins`:** Allowed values of the Origin header for browser requests; supports wildcards (e.g., `https://*.example.com`)
- **`allowed_headers`:** Additional headers allowed in CORS requests beyond the default safelist (`Accept`, `Accept-Language`, `Content-Type`, `Content-Language` are implicitly allowed)

**Documentation References:**

- [OTLP Receiver README](https://github.com/open-telemetry/opentelemetry-collector/blob/main/receiver/otlpreceiver/README.md)
- [OTLP Receiver Configuration](https://github.com/open-telemetry/opentelemetry-collector/blob/main/receiver/otlpreceiver/config.md)
- [Version 0.138.0 Release](https://github.com/open-telemetry/opentelemetry-collector-contrib/releases/tag/v0.138.0)

**Note:** The OpenTelemetry Collector Contrib distribution includes all core collector components, ensuring these CORS configuration options are available for browser-based telemetry.

**Scenario 3: Localhost-Only Access**

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 127.0.0.1:4317 # Only local connections
```

**Configuration Properties**

The `endpoint` property is officially supported in the OTLP receiver:

- **`endpoint`:** Configures the gRPC server listening address
  - Using `127.0.0.1:4317` restricts the receiver to accept connections only from the local machine
  - This is more secure than `0.0.0.0:4317` which accepts connections from any network interface
  - Ideal for scenarios where applications run on the same host as the collector (e.g., sidecar patterns, local development)

**Security Benefits:**

Binding to `127.0.0.1` prevents external network access to the collector's OTLP endpoint, reducing the attack surface when remote telemetry ingestion is not required.

**Documentation References:**

- [OTLP Receiver Configuration](https://github.com/open-telemetry/opentelemetry-collector/blob/main/receiver/otlpreceiver/config.md)
- [OTLP Receiver README](https://github.com/open-telemetry/opentelemetry-collector/blob/main/receiver/otlpreceiver/README.md)
- [Version 0.138.0 Release](https://github.com/open-telemetry/opentelemetry-collector-contrib/releases/tag/v0.138.0)

**Note:** The OpenTelemetry Collector Contrib distribution includes all core collector components, ensuring this endpoint configuration option is available.

---

### 2. Connectors: Spanmetrics (Traces → Metrics)

**Purpose:** The central component of the pipeline - converts OpenTelemetry spans into Prometheus metrics.

**What You Get:**

| Metric Type | Metric Name                               | What It Measures     | Use For                         |
| ----------- | ----------------------------------------- | -------------------- | ------------------------------- |
| Counter     | `llm_traces_span_metrics_calls_total`     | Total requests       | Rate (requests/sec), Error rate |
| Histogram   | `llm_traces_span_metrics_duration_bucket` | Latency distribution | p50, p95, p99 percentiles       |

**Default Configuration:**

```yaml
connectors:
  spanmetrics:
    histogram:
      explicit:
        buckets: [0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1, 5, 10]
    dimensions:
      - name: env
      - name: component
    dimensions_cache_size: 1000
```

---

#### Histogram Buckets Configuration

Buckets define latency ranges for your histograms. Choose based on your application's performance profile.

##### Bucket Selection Guide

| Use Case             | Recommended Buckets                               | Latency Range | Example Applications              |
| -------------------- | ------------------------------------------------- | ------------- | --------------------------------- |
| **Web APIs**         | `[0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1, 5, 10]`  | 1ms - 10s     | REST APIs, GraphQL, microservices |
| **ML Inference**     | `[0.01, 0.05, 0.1, 0.5, 1, 2.5, 5, 10, 30, 60]`   | 10ms - 60s    | Model serving, image processing   |
| **Batch Jobs**       | `[1, 5, 10, 30, 60, 300, 600, 1800, 3600]`        | 1s - 1hr      | Data processing, ETL pipelines    |
| **Database Queries** | `[0.0001, 0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1]` | 0.1ms - 1s    | Database calls, cache lookups     |
| **Mixed Workload**   | `[0.001, 0.01, 0.1, 0.5, 1, 5, 10, 30, 60]`       | 1ms - 60s     | General purpose                   |

##### How to Choose Buckets

**Step 1:** Measure your typical latency

```bash
# Option 1: From application logs
# Option 2: From existing traces
# Option 3: Load test and observe

# Goal: Find p50, p95, p99 latencies
```

**Step 2:** Select buckets that cover your range

```
Rule of thumb:
- Start bucket: 10x smaller than your p50
- End bucket: 2x larger than your p99
- 8-12 buckets total (more buckets = more storage)
```

**Example:**

If your API has:

- p50 = 50ms
- p95 = 200ms
- p99 = 500ms

Choose: `[0.005, 0.01, 0.05, 0.1, 0.2, 0.5, 1, 2, 5]`

**Configuration Examples:**

```yaml
# Example 1: Fast web API
connectors:
  spanmetrics:
    histogram:
      explicit:
        buckets: [0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1]

# Example 2: ML model inference (variable latency)
connectors:
  spanmetrics:
    histogram:
      explicit:
        buckets: [0.1, 0.5, 1, 2, 5, 10, 20, 30, 60]

# Example 3: Batch processing
connectors:
  spanmetrics:
    histogram:
      explicit:
        buckets: [10, 30, 60, 120, 300, 600, 1800, 3600]
```

---

#### Dimensions Configuration

Dimensions become Prometheus labels. They allow you to filter and group metrics.

##### Automatic Dimensions (Always Included)

These are automatically extracted from every span:

| Dimension      | Source             | Example Value                           | Use For                  |
| -------------- | ------------------ | --------------------------------------- | ------------------------ |
| `service_name` | Resource attribute | `checkout-service`                      | Filtering by service     |
| `span_name`    | Span name          | `HTTP POST /api/orders`                 | Filtering by operation   |
| `span_kind`    | Span kind          | `SPAN_KIND_SERVER`                      | Client vs server metrics |
| `status_code`  | Span status        | `STATUS_CODE_OK` or `STATUS_CODE_ERROR` | Error rate calculation   |

##### Custom Dimensions (You Configure)

Add dimensions that match your span attributes:

```yaml
dimensions:
  - name: env # Matches span attribute "env"
  - name: component # Matches span attribute "component"
  - name: http.status_code # Dotted names work too
  - name: model.name # Custom attributes from your app
  - name: region # Deployment region
```

##### Dimension Selection Strategy

**✅ Good Dimensions (Low Cardinality):**

| Dimension          | Typical Values         | Cardinality | Impact |
| ------------------ | ---------------------- | ----------- | ------ |
| `environment`      | dev, staging, prod     | 3           | ✅ Low |
| `region`           | us-east-1, eu-west-1   | 10-20       | ✅ Low |
| `http.status_code` | 200, 404, 500          | 10-20       | ✅ Low |
| `model.name`       | gpt-4, llama-3         | 5-10        | ✅ Low |
| `customer.tier`    | free, paid, enterprise | 3-5         | ✅ Low |

**❌ Bad Dimensions (High Cardinality):**

| Dimension     | Typical Values      | Cardinality        | Impact     |
| ------------- | ------------------- | ------------------ | ---------- |
| `user.id`     | 123456, 789012, ... | Millions           | ❌ Extreme |
| `trace.id`    | Unique per trace    | Billions           | ❌ Extreme |
| `request.id`  | Unique per request  | Billions           | ❌ Extreme |
| `customer.id` | One per customer    | Thousands-Millions | ⚠️ High    |
| `session.id`  | Unique per session  | Millions           | ❌ Extreme |

**⚠️ CARDINALITY WARNING:**

```
Total time series = (unique combinations of ALL dimensions)

Example:
- 10 services × 50 span_names × 3 environments × 5 regions = 7,500 series ✅
- 10 services × 50 span_names × 1,000 customer_ids = 500,000 series ❌
```

**High cardinality = More storage, slower queries, higher costs**

##### Complete Configuration Example

```yaml
connectors:
  spanmetrics:
    histogram:
      explicit:
        buckets: [0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1, 5, 10]

    dimensions:
      - name: env # Environment
      - name: component # Component/module name
      - name: http.status_code # HTTP status
      - name: model.name # ML model name
      - name: model.version # ML model version
      - name: deployment.name # K8s deployment

    # Increase cache if you have many unique dimension combinations
    dimensions_cache_size: 10000 # Default: 1000
```

##### Dimensions Cache Size

| Scenario          | Recommended Cache Size | Calculation              |
| ----------------- | ---------------------- | ------------------------ |
| Small deployment  | 1,000 (default)        | < 1k unique combinations |
| Medium deployment | 10,000                 | 1k - 10k combinations    |
| Large deployment  | 50,000                 | 10k - 50k combinations   |
| Very large        | 100,000                | 50k+ combinations        |

**How to estimate:**

```
Combinations ≈ (unique services) × (avg spans per service) × (dimension value combinations)

Example:
5 services × 20 span names × 3 envs × 2 components = 600 combinations
→ Use default 1,000 cache size
```

### Exporters

```yaml
exporters:
  prometheus:
    endpoint: "0.0.0.0:8889"
    namespace: llm # Metric prefix (llm_traces_span_metrics_*)
    resource_to_telemetry_conversion:
      enabled: true # Include resource attributes as labels
    enable_open_metrics: true

  debug:
    verbosity: detailed # Options: basic, normal, detailed
    # Change to "basic" in production to reduce logs
```

### Extensions

```yaml
extensions:
  health_check:
    endpoint: 0.0.0.0:13133
    path: /health/status

  # Optional: Enable profiling for debugging performance issues
  pprof:
    endpoint: 0.0.0.0:1888

  # Optional: Enable zpages for live debugging
  zpages:
    endpoint: 0.0.0.0:55679
```

**Additional Configuration Notes**:

- `health_check`: Required for monitoring and health probes
- `pprof`: Provides runtime profiling data (CPU, memory, goroutines). Access at `https://obs-dev.proveai.com:1888/debug/pprof/`
- `zpages`: Provides live debugging pages for pipelines, extensions, and feature gates. Access at `https://obs-dev.proveai.com:55679/debug/servicez`

**Advanced health_check options**:

```yaml
extensions:
  health_check:
    endpoint: 0.0.0.0:13133
    path: /health/status
    check_collector_pipeline:
      enabled: true
      interval: 5m
      exporter_failure_threshold: 5
```

### Service Pipelines

```yaml
service:
  extensions: [health_check, pprof, zpages]

  telemetry:
    metrics:
      level: detailed # Options: none, basic, normal, detailed
      readers:
        - pull:
            exporter:
              prometheus:
                host: 0.0.0.0
                port: 8888 # Internal collector metrics
    logs:
      level: debug # Options: debug, info, warn, error
      # Change to "info" in production

  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [spanmetrics, debug]
      # Add more processors as needed:
      # processors: [filter/drop-health-checks, batch, probabilistic_sampler]

    metrics:
      receivers: [otlp, spanmetrics]
      processors: [batch]
      exporters: [prometheus, debug]
```

**Note**: If using pprof and zpages extensions, ensure the ports are exposed in your Docker Compose configuration. For production deployments, consider restricting access to debugging ports (1888, 55679) or removing them entirely.

**Adding Additional Pipelines**:

```yaml
pipelines:
  traces:
    receivers: [otlp]
    processors: [batch]
    exporters: [spanmetrics, debug]

  # Separate pipeline for direct OTLP metrics (if needed)
  metrics/otlp:
    receivers: [otlp]
    processors: [batch]
    exporters: [prometheus]

  # Separate pipeline for spanmetrics
  metrics/spanmetrics:
    receivers: [spanmetrics]
    processors: [batch]
    exporters: [prometheus]
```

---

---

## Prometheus Configuration

**File Location:** `docker-compose/prometheus.yaml`

**When to Edit:** Adjusting scrape intervals, configuring remote storage, or modifying scrape targets based on your deployment profile

### Configuration Overview

The Prometheus configuration has 3 main sections that correspond to the scenarios outlined in the config file:

```
┌────────────────────────────────────┐
│ 1. Global (Scrape interval)        │
├────────────────────────────────────┤
│ 2. Remote Write (VictoriaMetrics)  │
├────────────────────────────────────┤
│ 3. Scrape Configs (What to scrape) │
└────────────────────────────────────┘
```

---

### 1. Global Configuration

**Current Default:**

```yaml
global:
  scrape_interval: 10s
```

The `scrape_interval` determines how often Prometheus scrapes metrics from targets. The default of `10s` is suitable for most production workloads. Adjust this value based on your needs:

- Lower values (e.g., `5s`) provide higher resolution but increase storage
- Higher values (e.g., `30s` or `60s`) reduce storage at the cost of resolution

---

### 2. Remote Write Configuration

**Purpose:** Send metrics to VictoriaMetrics for long-term storage.

**Current Default:**

```yaml
remote_write:
  - url: http://victoriametrics:8428/api/v1/write
```

#### When to Modify

**Scenario 1: Using profiles that include the `victoriametrics` service**

- Keep the configuration as-is
- The default URL `http://victoriametrics:8428/api/v1/write` points to the VictoriaMetrics container in the Docker Compose stack

**Scenario 2: Using an external VictoriaMetrics instance**

- Replace `victoriametrics` with your VictoriaMetrics host/DNS:

```yaml
remote_write:
  - url: http://your-vm-host:8428/api/v1/write
```

**Scenario 3: NOT using VictoriaMetrics**

- Comment out or remove the entire `remote_write` block
- Prometheus will use local storage only

```yaml
# remote_write:
#   - url: http://victoriametrics:8428/api/v1/write
```

---

### 3. Scrape Configurations

**Purpose:** Define which services Prometheus scrapes metrics from.

**Current Default:**

```yaml
scrape_configs:
  - job_name: "otel-collector"
    static_configs:
      - targets: ["otel-collector:8889"]

  - job_name: "otel-collector-internal"
    static_configs:
      - targets: ["otel-collector:8888"]
```

#### When to Modify

**Scenario 1: Using "full" profiles where `otel-collector` is part of the stack**

- Keep the `otel-collector` jobs as-is
- These jobs scrape:
  - Port `8889`: Spanmetrics (traces converted to metrics)
  - Port `8888`: Internal collector metrics (optional, for monitoring collector health)

**Scenario 2: NOT running the OTel Collector from this compose file**

- Remove the `otel-collector` jobs
- Add your own scrape targets for your collector or exporters:

```yaml
scrape_configs:
  - job_name: "your-services"
    static_configs:
      - targets:
          - "your-app:9100"
          - "another-exporter:9200"
```

---

### Additional Resources

For advanced Prometheus configuration options not covered in this setup (alerting rules, service discovery, TLS, authentication, etc.), see the [official Prometheus documentation](https://prometheus.io/docs/prometheus/latest/configuration/configuration/).

---

---

## VictoriaMetrics Configuration

**File Location:** `docker-compose/docker-compose.yaml` (command flags)

**When to Edit:** Adjusting data retention period or changing the listen address

### Configuration Overview

VictoriaMetrics is configured using command-line flags in the Docker Compose file.

**Current Default:**

```yaml
victoriametrics:
  image: victoriametrics/victoria-metrics:latest
  command:
    - "-retentionPeriod=12"
    - "-httpListenAddr=:8428"
  volumes:
    - victoriametrics_data:/victoria-metrics-data
  ports:
    - "8428:8428"
```

---

### 1. Retention Period

**Flag:** `-retentionPeriod=12`

**Purpose:** Controls how long metrics are stored before being automatically deleted.

**Current Default:** `12` (months)

The retention period determines how far back you can query metrics. The default of 12 months provides a full year of historical data. Adjust this value based on your requirements:

- Lower values (e.g., `1`, `3`, `6`) reduce disk storage requirements
- Higher values (e.g., `24`, `36`) extend historical data retention for compliance or long-term analysis

**Example: Change to 6 months**

```yaml
victoriametrics:
  command:
    - "-retentionPeriod=6"
    - "-httpListenAddr=:8428"
```

**Note:** Changing the retention period affects disk space usage. VictoriaMetrics uses approximately 1-2 bytes per sample on disk. Monitor your disk usage to ensure you have adequate storage for your chosen retention period.

---

### 2. HTTP Listen Address

**Flag:** `-httpListenAddr=:8428`

**Purpose:** Specifies the network address and port for the VictoriaMetrics HTTP API.

**Current Default:** `:8428` (listens on all interfaces, port 8428)

This flag controls where VictoriaMetrics accepts connections. The default configuration works for most deployments where VictoriaMetrics is accessed via Docker networking or localhost. You might change this if:

- You have a port conflict and need to use a different port
- You want to restrict access to specific network interfaces

**Example: Change port to 8429**

```yaml
victoriametrics:
  command:
    - "-retentionPeriod=12"
    - "-httpListenAddr=:8429"
  ports:
    - "8429:8429" # Update port mapping too
```

**Example: Listen only on localhost**

```yaml
victoriametrics:
  command:
    - "-retentionPeriod=12"
    - "-httpListenAddr=127.0.0.1:8428"
```

---

### Additional Resources

For advanced configuration options not included in this setup (memory limits, query performance tuning, deduplication, HA configurations, etc.), refer to the [official VictoriaMetrics documentation](https://docs.victoriametrics.com/).

---

---

## Configuration Summary Table

Quick reference for all three components:

| Component           | File                         | Key Settings                           | Restart Required |
| ------------------- | ---------------------------- | -------------------------------------- | ---------------- |
| **OTel Collector**  | `otel-collector-config.yaml` | Receivers, dimensions, buckets         | Yes              |
| **Prometheus**      | `prometheus.yaml`            | Scrape interval, targets, remote_write | Yes (or reload)  |
| **VictoriaMetrics** | `docker-compose.yaml`        | Retention, memory                      | Yes              |

---

## Next Steps

### You've Configured Your Stack

Now it's time to deploy and integrate:

1. **Deploy:** [Deployment Guide](deployment-guide.md)
2. **Integrate Applications:** [Hybrid Cloud Integration](hybrid-cloud-integration.md)
3. **Production Readiness:** [Production Guide](production-guide.md)
4. **Security:** [Security Guide](security.md)

### Need Help?

- **Metrics not appearing?** Check [Production Guide - Troubleshooting](production-guide.md#troubleshooting-production-issues)
- **Performance issues?** See [Production Guide - Performance Tuning](production-guide.md#performance-tuning)
- **High cardinality problems?** Review [Dimensions Configuration](#dimensions-configuration) above

---

[← Back to Advanced Setup](../ADVANCED_SETUP.md)
