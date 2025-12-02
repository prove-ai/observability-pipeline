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

**When to Edit:** Initial setup, adding dimensions, performance tuning

### Configuration Overview

The collector has 5 main sections:

```
┌─────────────────────────────────────┐
│ 1. Receivers (How traces come in)  │
├─────────────────────────────────────┤
│ 2. Processors (How traces are      │
│    batched and filtered)            │
├─────────────────────────────────────┤
│ 3. Connectors (Spanmetrics:        │
│    traces → metrics)                │
├─────────────────────────────────────┤
│ 4. Exporters (Where data goes)     │
├─────────────────────────────────────┤
│ 5. Service Pipelines (Connect      │
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

**Scenario 3: Localhost-Only Access**

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 127.0.0.1:4317 # Only local connections
```

---

### 2. Processors (Batching & Filtering)

**Purpose:** Control how traces are batched for efficiency and optionally filter unwanted spans.

#### Batch Processor (Required)

The batch processor groups spans together before exporting, reducing network overhead.

**Default Configuration:**

```yaml
processors:
  batch:
    timeout: 200ms
    send_batch_size: 8192
    send_batch_max_size: 16384
```

#### Batch Processor Variables

| Parameter             | Type     | Default | Description                   | Impact of Increasing               |
| --------------------- | -------- | ------- | ----------------------------- | ---------------------------------- |
| `timeout`             | duration | `200ms` | Max time before sending batch | Lower latency, more network calls  |
| `send_batch_size`     | int      | `8192`  | Preferred batch size (spans)  | Better compression, higher latency |
| `send_batch_max_size` | int      | `16384` | Maximum batch size (spans)    | Memory usage increases             |

#### Batch Processor Tuning Guide

Choose based on your latency vs. throughput requirements:

| Use Case               | timeout | send_batch_size | send_batch_max_size | Best For                             |
| ---------------------- | ------- | --------------- | ------------------- | ------------------------------------ |
| **Low Latency**        | `100ms` | `1024`          | `2048`              | Real-time dashboards, debugging      |
| **Balanced** (default) | `200ms` | `8192`          | `16384`             | Most production workloads            |
| **High Throughput**    | `500ms` | `16384`         | `32768`             | Batch jobs, high-volume ML inference |
| **Very High Volume**   | `1s`    | `32768`         | `65536`             | 100k+ spans/sec                      |

**Example: High Throughput Configuration**

```yaml
processors:
  batch:
    timeout: 500ms
    send_batch_size: 16384
    send_batch_max_size: 32768
```

---

#### Optional Processors

Add these to filter spans or enrich data:

##### Filter Processor: Drop Health Check Spans

**Use When:** Health checks create noise in metrics.

```yaml
processors:
  batch: {}

  filter/drop-health-checks:
    spans:
      exclude:
        match_type: regexp
        attributes:
          - key: http.target
            value: "/health.*"
          - key: http.url
            value: ".*/(health|ping|readiness|liveness).*"
```

**Add to pipeline:**

```yaml
pipelines:
  traces:
    receivers: [otlp]
    processors: [filter/drop-health-checks, batch] # Filter before batch
    exporters: [spanmetrics]
```

##### Resource Processor: Add Metadata

**Use When:** You want to add cluster/environment labels to all spans.

```yaml
processors:
  resource:
    attributes:
      - key: environment
        value: "production"
        action: upsert
      - key: cluster
        value: "us-east-1a"
        action: upsert
      - key: deployment.id
        from_attribute: k8s.deployment.name
        action: insert
```

##### Probabilistic Sampler: Reduce Volume

**Use When:** Trace volume is too high (>10k spans/sec).

```yaml
processors:
  probabilistic_sampler:
    sampling_percentage: 10.0 # Keep 10% of traces
```

**Sampling Guidelines:**

| Incoming Spans/Sec | Recommended Sampling % | Result                     |
| ------------------ | ---------------------- | -------------------------- |
| < 1,000            | 100% (no sampling)     | Keep everything            |
| 1,000 - 10,000     | 50%                    | Half the volume            |
| 10,000 - 50,000    | 10-20%                 | Manageable volume          |
| > 50,000           | 1-5%                   | High-level visibility only |

**Complete Example with All Processors:**

```yaml
processors:
  # Always first: filter unwanted spans
  filter/drop-health-checks:
    spans:
      exclude:
        match_type: regexp
        attributes:
          - key: http.target
            value: "/health.*"

  # Then: add metadata
  resource:
    attributes:
      - key: environment
        value: "production"
        action: upsert

  # Then: sample if needed
  probabilistic_sampler:
    sampling_percentage: 20.0

  # Finally: batch for efficiency
  batch:
    timeout: 200ms
    send_batch_size: 8192

# Use in pipeline (order matters!)
service:
  pipelines:
    traces:
      receivers: [otlp]
      processors:
        [filter/drop-health-checks, resource, probabilistic_sampler, batch]
      exporters: [spanmetrics]
```

---

### 3. Connectors: Spanmetrics (Traces → Metrics)

**Purpose:** The heart of the pipeline - converts OpenTelemetry spans into Prometheus metrics.

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

**Namespace Customization**:

The `namespace` parameter prefixes all metric names:

```yaml
namespace: llm
# Results in: llm_traces_span_metrics_calls_total

namespace: inference
# Results in: inference_traces_span_metrics_calls_total
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

**When to Edit:** Scrape interval tuning, adding targets, configuring remote write

### Configuration Overview

Prometheus has 3 main sections:

```
┌────────────────────────────────────┐
│ 1. Global (Defaults for all jobs) │
├────────────────────────────────────┤
│ 2. Scrape Configs (What to scrape)│
├────────────────────────────────────┤
│ 3. Remote Write (Long-term storage)│
└────────────────────────────────────┘
```

---

### 1. Global Configuration

**Purpose:** Set defaults that apply to all scrape jobs.

**Default Configuration:**

```yaml
global:
  scrape_interval: 10s
  scrape_timeout: 10s
  evaluation_interval: 15s
```

#### Global Configuration Variables

| Parameter             | Type     | Default | Description                 | Impact of Decreasing         |
| --------------------- | -------- | ------- | --------------------------- | ---------------------------- |
| `scrape_interval`     | duration | `10s`   | How often to scrape targets | Higher resolution, more load |
| `scrape_timeout`      | duration | `10s`   | Max time for scrape request | More failures if too low     |
| `evaluation_interval` | duration | `15s`   | How often to evaluate rules | Faster alerting, more CPU    |

#### Scrape Interval Selection Guide

Choose based on your monitoring requirements and scale:

| Use Case                 | Interval | Resolution | Storage Impact | Best For                          |
| ------------------------ | -------- | ---------- | -------------- | --------------------------------- |
| **Development/Debug**    | `5s`     | High       | 2x default     | Debugging, real-time dashboards   |
| **Production** (default) | `10s`    | Good       | Baseline       | Most production workloads         |
| **High Scale**           | `30s`    | Medium     | 0.33x default  | Large deployments (100+ services) |
| **Low Priority**         | `60s`    | Low        | 0.16x default  | Batch jobs, non-critical metrics  |

**Storage Formula:**

```
Data points per day = (86400 / scrape_interval) × number_of_time_series

Example with 10,000 series:
- 5s interval:  172,800,000 points/day (~16 GB)
- 10s interval:  86,400,000 points/day (~8 GB)
- 30s interval:  28,800,000 points/day (~2.7 GB)
```

#### Adding External Labels

External labels are added to ALL metrics scraped by this Prometheus instance:

```yaml
global:
  scrape_interval: 10s
  external_labels:
    cluster: "production-us-east-1"
    environment: "production"
    datacenter: "dc-1"
```

**Use external labels for:**

- Multi-cluster setups (identify which cluster)
- Federated Prometheus (aggregate from multiple instances)
- Remote write to shared storage (distinguish sources)

**Example: Multi-Region Setup**

```yaml
# prometheus-us-east-1.yaml
global:
  scrape_interval: 10s
  external_labels:
    cluster: 'prod-use1'
    region: 'us-east-1'

# prometheus-eu-west-1.yaml
global:
  scrape_interval: 10s
  external_labels:
    cluster: 'prod-euw1'
    region: 'eu-west-1'
```

---

### 2. Remote Write Configuration

**Purpose:** Send metrics to long-term storage (VictoriaMetrics).

**Default Configuration:**

```yaml
remote_write:
  - url: http://victoriametrics:8428/api/v1/write
```

#### Remote Write Variables

| Parameter                           | Type     | Default    | Description                | When to Change                              |
| ----------------------------------- | -------- | ---------- | -------------------------- | ------------------------------------------- |
| `url`                               | string   | (required) | VictoriaMetrics endpoint   | Change for external VM or different storage |
| `queue_config.capacity`             | int      | `10000`    | Queue size before dropping | Increase for bursty workloads               |
| `queue_config.max_shards`           | int      | `50`       | Max parallel connections   | Increase for high throughput                |
| `queue_config.max_samples_per_send` | int      | `5000`     | Batch size                 | Increase for efficiency                     |
| `queue_config.batch_send_deadline`  | duration | `5s`       | Max wait before sending    | Decrease for lower latency                  |

#### Remote Write Tuning Guide

Choose configuration based on your metrics volume:

| Workload Scale       | Samples/Sec | capacity | max_shards | max_samples_per_send | Best For           |
| -------------------- | ----------- | -------- | ---------- | -------------------- | ------------------ |
| **Small**            | < 10k       | 10,000   | 50         | 5,000                | Small deployments  |
| **Medium** (default) | 10k - 50k   | 20,000   | 100        | 5,000                | Most production    |
| **Large**            | 50k - 100k  | 50,000   | 200        | 10,000               | High-scale systems |
| **Very Large**       | > 100k      | 100,000  | 500        | 20,000               | Massive scale      |

**How to measure your samples/sec:**

```promql
# Run this query in Prometheus
rate(prometheus_tsdb_head_samples_appended_total[5m])
```

#### Complete Remote Write Examples

**Example 1: Default (Balanced)**

```yaml
remote_write:
  - url: http://victoriametrics:8428/api/v1/write
    queue_config:
      capacity: 10000
      max_shards: 50
      min_shards: 1
      max_samples_per_send: 5000
      batch_send_deadline: 5s
      min_backoff: 30ms
      max_backoff: 5s
```

**Example 2: High Throughput (>100k samples/sec)**

```yaml
remote_write:
  - url: http://victoriametrics:8428/api/v1/write
    queue_config:
      capacity: 100000
      max_shards: 500
      min_shards: 10
      max_samples_per_send: 20000
      batch_send_deadline: 10s
      min_backoff: 100ms
      max_backoff: 30s
```

**Example 3: Low Latency (Real-time)**

```yaml
remote_write:
  - url: http://victoriametrics:8428/api/v1/write
    queue_config:
      capacity: 5000
      max_shards: 20
      min_shards: 5
      max_samples_per_send: 1000
      batch_send_deadline: 1s # Send quickly
```

#### Filtering Metrics (Write Relabeling)

Reduce storage costs by filtering out unwanted metrics:

**Example: Drop Go Runtime Metrics**

```yaml
remote_write:
  - url: http://victoriametrics:8428/api/v1/write
    write_relabel_configs:
      # Drop Go internal metrics
      - source_labels: [__name__]
        regex: "go_.*"
        action: drop

      # Drop process metrics
      - source_labels: [__name__]
        regex: "process_.*"
        action: drop
```

**Example: Only Send Specific Metrics**

```yaml
remote_write:
  - url: http://victoriametrics:8428/api/v1/write
    write_relabel_configs:
      # Only keep metrics starting with "llm_traces"
      - source_labels: [__name__]
        regex: "llm_traces_.*"
        action: keep
```

**Example: Drop High-Cardinality Labels**

```yaml
remote_write:
  - url: http://victoriametrics:8428/api/v1/write
    write_relabel_configs:
      # Remove user_id label (high cardinality)
      - regex: "user_id"
        action: labeldrop
```

#### Authentication for Remote Storage

**Basic Auth:**

```yaml
remote_write:
  - url: http://victoriametrics:8428/api/v1/write
    basic_auth:
      username: prometheus-writer
      password: your-secure-password
```

**Bearer Token:**

```yaml
remote_write:
  - url: http://victoriametrics:8428/api/v1/write
    bearer_token: your-api-token
```

**Bearer Token from File (More Secure):**

```yaml
remote_write:
  - url: http://victoriametrics:8428/api/v1/write
    bearer_token_file: /etc/prometheus/token
```

#### Multiple Remote Write Endpoints

Send to multiple storage backends:

```yaml
remote_write:
  # Primary storage: VictoriaMetrics
  - url: http://victoriametrics:8428/api/v1/write
    queue_config:
      capacity: 10000

  # Secondary storage: Cloud provider
  - url: https://prometheus-remote-write.example.com/api/v1/write
    basic_auth:
      username: prometheus
      password: secret
    queue_config:
      capacity: 5000
```

### Scrape Configurations

```yaml
scrape_configs:
  # Scrape spanmetrics from OTel Collector
  - job_name: "otel-collector"
    static_configs:
      - targets: ["otel-collector:8889"]
    # Optional: Add labels to all metrics from this job
    # relabel_configs:
    #   - target_label: environment
    #     replacement: production

  # Scrape collector internal metrics
  - job_name: "otel-collector-internal"
    static_configs:
      - targets: ["otel-collector:8888"]

  # Scrape Prometheus itself (useful for monitoring)
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  # Scrape VictoriaMetrics metrics
  - job_name: "victoriametrics"
    static_configs:
      - targets: ["victoriametrics:8428"]
```

### Service Discovery

Prometheus supports multiple service discovery mechanisms:

```yaml
scrape_configs:
  # File-based discovery
  - job_name: "file-sd"
    file_sd_configs:
      - files:
          - "/etc/prometheus/targets/*.json"
        refresh_interval: 30s

  # Consul discovery
  - job_name: "consul-sd"
    consul_sd_configs:
      - server: "consul.service.consul:8500"
        services: ["otel-collector", "my-app"]

  # EC2 discovery
  - job_name: "ec2-sd"
    ec2_sd_configs:
      - region: us-east-1
        access_key: YOUR_ACCESS_KEY
        secret_key: YOUR_SECRET_KEY
        port: 8889
```

### Recording Rules

Use recording rules for expensive queries:

```yaml
# prometheus.yaml
rule_files:
  - "/etc/prometheus/rules.yml"
```

Create `rules.yml`:

```yaml
groups:
  - name: spanmetrics
    interval: 30s
    rules:
      # Pre-aggregate request rate
      - record: job:llm_traces_span_metrics_calls:rate5m
        expr: sum by (service_name, span_name) (rate(llm_traces_span_metrics_calls_total[5m]))

      # Pre-aggregate p95 latency
      - record: job:llm_traces_span_metrics_duration:p95
        expr: histogram_quantile(0.95, sum by (service_name, span_name, le) (rate(llm_traces_span_metrics_duration_bucket[5m])))
```

Mount rules file in Docker Compose:

```yaml
prometheus:
  image: prom/prometheus:latest
  volumes:
    - ./prometheus.yaml:/etc/prometheus/prometheus.yaml:ro
    - ./rules.yml:/etc/prometheus/rules.yml:ro # Add this
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

1. **Deploy:** [Deployment Methods Guide](deployment-methods.md)
2. **Integrate Applications:** [Integration Patterns](integration-patterns.md)
3. **Production Readiness:** [Production Guide](production-guide.md)
4. **Security:** [Security Guide](security.md)

### Need Help?

- **Metrics not appearing?** Check [Architecture Guide - Troubleshooting](architecture.md#troubleshooting)
- **Performance issues?** See [Production Guide - Performance Tuning](production-guide.md)
- **High cardinality problems?** Review [Dimensions Configuration](#dimensions-configuration) above

---

[← Back to Advanced Setup](../ADVANCED_SETUP.md)
