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

**Collector Version:** `otel/opentelemetry-collector-contrib:0.138.0` (Core `v1.44.0`)

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

[OTLP Receiver Configuration Source (Go Struct)](https://pkg.go.dev/go.opentelemetry.io/collector/config/configgrpc#section-readme)

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

[OpenTelemetry Collector HTTP Server Config (CORS)](https://github.com/open-telemetry/opentelemetry-collector/blob/main/config/confighttp/README.md#server-configuration)

**Scenario 3: Localhost-Only Access**

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 127.0.0.1:4317 # Only local connections
```

[OpenTelemetry Collector Networking Best Practices](https://opentelemetry.io/docs/security/config-best-practices/#network-configuration)

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
- `pprof`: Provides runtime profiling data (CPU, memory, goroutines). Access at `http://localhost:1888/debug/pprof/`
- `zpages`: Provides live debugging pages for pipelines, extensions, and feature gates. Access at `http://localhost:55679/debug/servicez`

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

**When to Edit:** Adjusting scrape intervals, configuring remote storage, or modifying scrape targets

### Configuration Overview

The Prometheus configuration has 3 main sections:

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

**Purpose:** Set the default scrape interval for all jobs.

**Current Configuration:**

```yaml
global:
  scrape_interval: 10s
```

#### Scrape Interval Guide

| Parameter         | Current Value | Description                 | When to Change                |
| ----------------- | ------------- | --------------------------- | ----------------------------- |
| `scrape_interval` | `10s`         | How often to scrape targets | Adjust based on your use case |

#### Choosing a Scrape Interval

| Use Case         | Interval | Resolution | Storage Impact | Best For                         |
| ---------------- | -------- | ---------- | -------------- | -------------------------------- |
| **Development**  | `5s`     | High       | 2x default     | Debugging, testing               |
| **Production**   | `10s`    | Good       | Baseline       | Most production workloads        |
| **High Scale**   | `30s`    | Medium     | 0.33x default  | Large deployments, cost savings  |
| **Low Priority** | `60s`    | Low        | 0.16x default  | Non-critical metrics, batch jobs |

**Example: Change to 30s for cost savings**

```yaml
global:
  scrape_interval: 30s
```

---

### 2. Remote Write Configuration

**Purpose:** Send metrics to VictoriaMetrics for long-term storage.

**Current Configuration:**

```yaml
remote_write:
  - url: http://victoriametrics:8428/api/v1/write
```

#### When to Modify Remote Write

| Scenario                      | Action                | Example                                               |
| ----------------------------- | --------------------- | ----------------------------------------------------- |
| **Using profiles with VM**    | Keep as-is            | No changes needed                                     |
| **External VictoriaMetrics**  | Change URL            | `url: http://your-vm-host:8428/api/v1/write`          |
| **Not using VictoriaMetrics** | Comment out or remove | See [Prometheus-only profile](deployment-profiles.md) |
| **Using cloud storage**       | Replace URL           | Use your cloud provider's remote write endpoint       |

#### Example: External VictoriaMetrics

```yaml
remote_write:
  - url: http://your-vm-host:8428/api/v1/write
    # Optional: Add authentication
    # basic_auth:
    #   username: prometheus-writer
    #   password: your-secure-password
```

#### Example: Disable Remote Write (Prometheus-only)

```yaml
# Comment out the entire remote_write block if not using VictoriaMetrics
# remote_write:
#   - url: http://victoriametrics:8428/api/v1/write
```

---

### 3. Scrape Configurations

**Purpose:** Define which services to scrape metrics from.

**Current Configuration:**

```yaml
scrape_configs:
  - job_name: "otel-collector"
    static_configs:
      - targets: ["otel-collector:8889"]

  - job_name: "otel-collector-internal"
    static_configs:
      - targets: ["otel-collector:8888"]
```

#### Default Scrape Jobs

| Job Name                  | Target                | Metrics                      | When to Use                               |
| ------------------------- | --------------------- | ---------------------------- | ----------------------------------------- |
| `otel-collector`          | `otel-collector:8889` | Spanmetrics (traces→metrics) | When using the OTel Collector service     |
| `otel-collector-internal` | `otel-collector:8888` | Collector internal metrics   | Optional, for monitoring collector health |

#### Profile-Specific Guidance

**If using "full" profiles** (with `otel-collector` service):

- Keep the `otel-collector` job as-is
- The collector service name matches the Docker Compose service

**If NOT using the OTel Collector** (Prometheus-only profile):

- Remove or comment out the `otel-collector` jobs
- Add your own scrape targets (see examples below)

#### Adding Your Own Scrape Targets

**Example: Scrape your application exporters**

```yaml
scrape_configs:
  # Your custom services
  - job_name: "your-services"
    static_configs:
      - targets:
          - "your-app:9100"
          - "another-exporter:9200"
```

**Example: Multiple targets with labels**

```yaml
scrape_configs:
  - job_name: "my-apps"
    static_configs:
      - targets: ["app1:8080"]
        labels:
          env: "production"
          tier: "frontend"
      - targets: ["app2:8080"]
        labels:
          env: "production"
          tier: "backend"
```

---

### Complete Configuration Examples

#### Example 1: Default (Full Profile with OTel Collector)

```yaml
global:
  scrape_interval: 10s

remote_write:
  - url: http://victoriametrics:8428/api/v1/write

scrape_configs:
  - job_name: "otel-collector"
    static_configs:
      - targets: ["otel-collector:8889"]

  - job_name: "otel-collector-internal"
    static_configs:
      - targets: ["otel-collector:8888"]
```

#### Example 2: External VictoriaMetrics

```yaml
global:
  scrape_interval: 10s

remote_write:
  - url: http://external-vm.example.com:8428/api/v1/write
    basic_auth:
      username: prometheus
      password: secure-password

scrape_configs:
  - job_name: "otel-collector"
    static_configs:
      - targets: ["otel-collector:8889"]
```

#### Example 3: Prometheus-Only (No VictoriaMetrics, Custom Targets)

```yaml
global:
  scrape_interval: 15s

# No remote_write - using Prometheus local storage only

scrape_configs:
  - job_name: "my-application"
    static_configs:
      - targets:
          - "app-server-1:9090"
          - "app-server-2:9090"

  - job_name: "node-exporters"
    static_configs:
      - targets:
          - "node1:9100"
          - "node2:9100"
```

---

### Common Configuration Tasks

#### Task 1: Reduce Storage Costs

Increase scrape interval to collect fewer data points:

```yaml
global:
  scrape_interval: 30s # Was 10s
```

#### Task 2: Add External VictoriaMetrics

Update remote write URL:

```yaml
remote_write:
  - url: http://your-external-vm:8428/api/v1/write
```

#### Task 3: Scrape Additional Services

Add new jobs to `scrape_configs`:

```yaml
scrape_configs:
  - job_name: "otel-collector"
    static_configs:
      - targets: ["otel-collector:8889"]

  # Add your services here
  - job_name: "my-app"
    static_configs:
      - targets: ["my-app:8080"]
```

---

---

## VictoriaMetrics Configuration

**File Location:** `docker-compose/docker-compose.yaml` (command flags)

**When to Edit:** Changing retention, memory limits, or deduplication settings

### Configuration Overview

VictoriaMetrics is configured using command-line flags (not a config file).

**Default Configuration:**

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

### Core Configuration Flags

| Flag                     | Type   | Default                  | Description               | When to Change                    |
| ------------------------ | ------ | ------------------------ | ------------------------- | --------------------------------- |
| `-retentionPeriod`       | int    | `1` (month)              | How long to keep data     | Increase for longer history       |
| `-httpListenAddr`        | string | `:8428`                  | HTTP API listen address   | Change port if conflict           |
| `-storageDataPath`       | string | `/victoria-metrics-data` | Data directory            | Using custom volume               |
| `-memory.allowedPercent` | int    | `80`                     | % of system memory to use | Tune based on server size         |
| `-memory.allowedBytes`   | bytes  | (auto)                   | Absolute memory limit     | Prefer over percent in containers |

---

### 1. Retention Configuration

Control how long metrics are stored.

#### Retention Period Guide

| Retention               | Flag Value            | Disk Usage (1M series) | Use Case              |
| ----------------------- | --------------------- | ---------------------- | --------------------- |
| **1 month**             | `-retentionPeriod=1`  | ~50 GB                 | Development/testing   |
| **3 months**            | `-retentionPeriod=3`  | ~150 GB                | Short-term production |
| **6 months**            | `-retentionPeriod=6`  | ~300 GB                | Standard production   |
| **12 months** (default) | `-retentionPeriod=12` | ~600 GB                | Long-term analysis    |
| **24 months**           | `-retentionPeriod=24` | ~1.2 TB                | Compliance/audit      |
| **36 months**           | `-retentionPeriod=36` | ~1.8 TB                | Extended compliance   |

**Storage Calculation:**

```
Disk space = active_series × retention_months × 0.5 GB

Example:
2 million series × 12 months × 0.5 GB = 1.2 TB
```

**Configuration Examples:**

```yaml
# Example 1: 6 month retention
victoriametrics:
  command:
    - "-retentionPeriod=6"
    - "-httpListenAddr=:8428"

# Example 2: 24 month retention (compliance)
victoriametrics:
  command:
    - "-retentionPeriod=24"
    - "-httpListenAddr=:8428"
```

---

### 2. Memory Configuration

VictoriaMetrics uses memory for caching to improve query performance.

#### Memory Allocation Guide

| Server RAM | Recommended Setting | Flag                        | VictoriaMetrics RAM | Reasoning         |
| ---------- | ------------------- | --------------------------- | ------------------- | ----------------- |
| 4 GB       | 60%                 | `-memory.allowedPercent=60` | ~2.4 GB             | Leave room for OS |
| 8 GB       | 70%                 | `-memory.allowedPercent=70` | ~5.6 GB             | Balanced          |
| 16 GB      | 75%                 | `-memory.allowedPercent=75` | ~12 GB              | Good caching      |
| 32 GB+     | 80% (default)       | `-memory.allowedPercent=80` | ~25 GB+             | Optimal caching   |

#### Configuration Methods

**Method 1: Percentage (Recommended for bare metal)**

```yaml
victoriametrics:
  command:
    - "-retentionPeriod=12"
    - "-httpListenAddr=:8428"
    - "-memory.allowedPercent=75"
```

**Method 2: Absolute Bytes (Recommended for containers)**

```yaml
victoriametrics:
  command:
    - "-retentionPeriod=12"
    - "-httpListenAddr=:8428"
    - "-memory.allowedBytes=8GB" # Explicit limit
```

**Method 3: Combined with Docker limits**

```yaml
victoriametrics:
  command:
    - "-retentionPeriod=12"
    - "-httpListenAddr=:8428"
    - "-memory.allowedPercent=80"
  deploy:
    resources:
      limits:
        memory: 10G # Docker enforces this
```

---

### 3. Query Performance Configuration

Tune query timeouts and concurrency:

| Flag                            | Default | Description              | Increase When           |
| ------------------------------- | ------- | ------------------------ | ----------------------- |
| `-search.maxQueryDuration`      | `30s`   | Max query execution time | Complex queries timeout |
| `-search.maxConcurrentRequests` | `16`    | Max simultaneous queries | Many dashboard users    |
| `-search.maxQueueDuration`      | `10s`   | Max time in queue        | Queries queue up        |

**Example: High-Concurrency Configuration**

```yaml
victoriametrics:
  command:
    - "-retentionPeriod=12"
    - "-httpListenAddr=:8428"
    - "-search.maxQueryDuration=60s" # Allow longer queries
    - "-search.maxConcurrentRequests=32" # More concurrent queries
    - "-search.maxQueueDuration=30s" # Longer queue wait
```

---

### 4. Deduplication Configuration

**Use When:** Multiple Prometheus instances scrape the same targets (HA setup).

| Flag                       | Default          | Description                       |
| -------------------------- | ---------------- | --------------------------------- |
| `-dedup.minScrapeInterval` | `0ms` (disabled) | Dedupe samples within this window |

**Example: HA Prometheus Setup**

```yaml
# Two Prometheus instances scrape the same targets every 10s
# VictoriaMetrics deduplicates redundant samples

victoriametrics:
  command:
    - "-retentionPeriod=12"
    - "-httpListenAddr=:8428"
    - "-dedup.minScrapeInterval=10s" # Match Prometheus scrape_interval
```

**How it works:**

```
Prometheus-1 scrapes at: 0s, 10s, 20s, 30s
Prometheus-2 scrapes at: 1s, 11s, 21s, 31s
VictoriaMetrics keeps: One sample per 10s window
```

---

### Complete Configuration Examples

#### Example 1: Small Development Setup

```yaml
victoriametrics:
  image: victoriametrics/victoria-metrics:latest
  command:
    - "-retentionPeriod=1" # 1 month
    - "-httpListenAddr=:8428"
    - "-memory.allowedBytes=2GB" # Small memory footprint
  volumes:
    - victoriametrics_data:/victoria-metrics-data
  ports:
    - "8428:8428"
```

#### Example 2: Production Setup (Default)

```yaml
victoriametrics:
  image: victoriametrics/victoria-metrics:latest
  command:
    - "-retentionPeriod=12" # 12 months
    - "-httpListenAddr=:8428"
    - "-memory.allowedBytes=8GB"
    - "-search.maxQueryDuration=30s"
    - "-search.maxConcurrentRequests=16"
  volumes:
    - victoriametrics_data:/victoria-metrics-data
  ports:
    - "8428:8428"
  deploy:
    resources:
      limits:
        memory: 10G
        cpus: "4"
```

#### Example 3: High-Availability Production

```yaml
victoriametrics:
  image: victoriametrics/victoria-metrics:latest
  command:
    - "-retentionPeriod=24" # 24 months (compliance)
    - "-httpListenAddr=:8428"
    - "-memory.allowedBytes=16GB" # Large cache
    - "-dedup.minScrapeInterval=10s" # HA Prometheus dedup
    - "-search.maxQueryDuration=60s" # Complex queries
    - "-search.maxConcurrentRequests=32" # Many users
    - "-search.maxQueueDuration=30s"
  volumes:
    - victoriametrics_data:/victoria-metrics-data
  ports:
    - "8428:8428"
  deploy:
    resources:
      limits:
        memory: 20G
        cpus: "8"
```

---

### Advanced Flags

| Flag                  | Description                    | Use Case                    |
| --------------------- | ------------------------------ | --------------------------- |
| `-promscrape.config`  | Use VictoriaMetrics as scraper | Replace Prometheus entirely |
| `-influxListenAddr`   | Accept InfluxDB writes         | Multi-protocol ingestion    |
| `-graphiteListenAddr` | Accept Graphite writes         | Legacy metric migration     |
| `-opentsdbListenAddr` | Accept OpenTSDB writes         | IoT/sensor data             |

---

### Additional VictoriaMetrics Resources

For more advanced configuration options and detailed information, refer to the [official VictoriaMetrics documentation](https://docs.victoriametrics.com/).

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
2. **Integrate Applications:** [Integration Patterns](integration-patterns.md)
3. **Production Readiness:** [Production Guide](production-guide.md)
4. **Security:** [Security Guide](security.md)

### Need Help?

- **Metrics not appearing?** Check [Production Guide - Troubleshooting](production-guide.md#troubleshooting-production-issues)
- **Performance issues?** See [Production Guide - Performance Tuning](production-guide.md#performance-tuning)
- **High cardinality problems?** Review [Dimensions Configuration](#dimensions-configuration) above

---

[← Back to Advanced Setup](../ADVANCED_SETUP.md)
