# Reference Guide

[← Back to Advanced Setup](../ADVANCED_SETUP.md)

This guide provides reference information including metric definitions, port mappings, example queries, useful commands, and common configurations.

## Table of Contents

- [Metric Reference](#metric-reference)
- [Example Queries](#example-queries)
- [Port Reference](#port-reference)
- [Useful Commands](#useful-commands)
- [Common Configurations](#common-configurations)
- [Additional Resources](#additional-resources)

---

## Metric Reference

### Spanmetrics Output

The spanmetrics connector generates the following metrics:

| Metric Name                               | Type      | Description                          |
| ----------------------------------------- | --------- | ------------------------------------ |
| `llm_traces_span_metrics_calls_total`     | Counter   | Total number of spans                |
| `llm_traces_span_metrics_duration_bucket` | Histogram | Span duration histogram              |
| `llm_traces_span_metrics_duration_sum`    | Counter   | Total duration of all spans          |
| `llm_traces_span_metrics_duration_count`  | Counter   | Count of spans (same as calls_total) |

### Labels

All spanmetrics include these labels:

**Automatic Labels** (always present):

- `service_name`: Name of the service
- `span_name`: Name of the span/operation
- `span_kind`: Type of span
- `status_code`: Span status

**Custom Labels** (configured via dimensions):

- `env`: Environment (if configured)
- `component`: Component name (if configured)
- Any additional dimensions you configure

### Label Values

**span_kind**:

- `SPAN_KIND_CLIENT`: Client span (outbound request)
- `SPAN_KIND_SERVER`: Server span (inbound request)
- `SPAN_KIND_INTERNAL`: Internal span
- `SPAN_KIND_PRODUCER`: Message producer
- `SPAN_KIND_CONSUMER`: Message consumer

**status_code**:

- `STATUS_CODE_UNSET`: No error information
- `STATUS_CODE_OK`: Success
- `STATUS_CODE_ERROR`: Error occurred

---

## Example Queries

### Request Rate (requests per second)

```promql
rate(llm_traces_span_metrics_calls_total[5m])
```

### Error Rate

```promql
rate(llm_traces_span_metrics_calls_total{status_code="STATUS_CODE_ERROR"}[5m])
```

### Error Percentage

```promql
sum(rate(llm_traces_span_metrics_calls_total{status_code="STATUS_CODE_ERROR"}[5m]))
/
sum(rate(llm_traces_span_metrics_calls_total[5m]))
* 100
```

### P50 Latency

```promql
histogram_quantile(0.50,
  sum by (service_name, le) (
    rate(llm_traces_span_metrics_duration_bucket[5m])
  )
)
```

### P95 Latency

```promql
histogram_quantile(0.95,
  sum by (service_name, le) (
    rate(llm_traces_span_metrics_duration_bucket[5m])
  )
)
```

### P99 Latency

```promql
histogram_quantile(0.99,
  sum by (service_name, le) (
    rate(llm_traces_span_metrics_duration_bucket[5m])
  )
)
```

### Average Latency

```promql
rate(llm_traces_span_metrics_duration_sum[5m])
/
rate(llm_traces_span_metrics_duration_count[5m])
```

### Top 5 Services by Request Rate

```promql
topk(5, sum by (service_name) (rate(llm_traces_span_metrics_calls_total[5m])))
```

### Top 5 Services by Error Rate

```promql
topk(5,
  sum by (service_name) (
    rate(llm_traces_span_metrics_calls_total{status_code="STATUS_CODE_ERROR"}[5m])
  )
)
```

### Requests by Environment

```promql
sum by (env) (rate(llm_traces_span_metrics_calls_total[5m]))
```

### SLI: Availability (% of successful requests)

```promql
sum(rate(llm_traces_span_metrics_calls_total{status_code!="STATUS_CODE_ERROR"}[5m]))
/
sum(rate(llm_traces_span_metrics_calls_total[5m]))
* 100
```

### SLI: Latency (% of requests under threshold)

```promql
# Requests under 100ms
sum(rate(llm_traces_span_metrics_duration_bucket{le="0.1"}[5m]))
/
sum(rate(llm_traces_span_metrics_duration_count[5m]))
* 100
```

---

## Port Reference

| Port  | Service             | Component       | Purpose                   | Required |
| ----- | ------------------- | --------------- | ------------------------- | -------- |
| 4317  | OTLP gRPC           | Collector       | Receive traces (gRPC)     | Yes      |
| 4318  | OTLP HTTP           | Collector       | Receive traces (HTTP)     | Yes      |
| 8889  | Prometheus Exporter | Collector       | Expose spanmetrics        | Yes      |
| 8888  | Internal Metrics    | Collector       | Collector self-monitoring | Yes      |
| 13133 | Health Check        | Collector       | Health/readiness checks   | Yes      |
| 1888  | pprof               | Collector       | Profiling (debugging)     | Optional |
| 55679 | zpages              | Collector       | Debugging UI              | Optional |
| 9090  | HTTP                | Prometheus      | Query API / UI            | Yes      |
| 8428  | HTTP                | VictoriaMetrics | Query API / Remote write  | Yes      |

**Note**: Ports 1888 (pprof) and 55679 (zpages) are only accessible if you enable these extensions in your collector configuration. They are optional and primarily used for debugging and performance analysis.

---

## Useful Commands

### Docker Commands

```bash
# View all logs
docker compose logs -f

# View logs from specific time
docker compose logs --since 30m otel-collector

# Follow logs with grep
docker compose logs -f otel-collector | grep ERROR

# Check resource usage
docker stats

# Execute command in container
docker exec -it otel-collector sh

# Restart single service
docker compose restart otel-collector

# Stop all services
docker compose down

# Stop and remove volumes
docker compose down -v
```

### Prometheus Commands

```bash
# Check configuration
curl http://localhost:9090/api/v1/status/config

# Check targets
curl http://localhost:9090/api/v1/targets

# Query API
curl 'http://localhost:9090/api/v1/query?query=up'

# Check TSDB status
curl http://localhost:9090/api/v1/status/tsdb

# Health check
curl http://localhost:9090/-/healthy

# Readiness check
curl http://localhost:9090/-/ready
```

### VictoriaMetrics Commands

```bash
# Health check
curl http://localhost:8428/health

# Metrics
curl http://localhost:8428/metrics

# Query (Prometheus-compatible)
curl 'http://localhost:8428/api/v1/query?query=up'

# Create snapshot
curl http://localhost:8428/snapshot/create

# List snapshots
ls /victoria-metrics-data/snapshots/

# Delete old data (use with caution)
curl -X POST 'http://localhost:8428/api/v1/admin/tsdb/delete_series?match[]={__name__="old_metric"}'
```

### OpenTelemetry Collector Commands

```bash
# Check collector health
curl http://localhost:13133/health/status

# View zpages service status (if enabled)
curl http://localhost:55679/debug/servicez

# View pipeline information (if zpages enabled)
curl http://localhost:55679/debug/pipelinez

# Capture CPU profile (if pprof enabled)
curl http://localhost:1888/debug/pprof/profile?seconds=30 -o cpu.prof

# Capture memory heap profile (if pprof enabled)
curl http://localhost:1888/debug/pprof/heap -o heap.prof

# Check collector metrics
curl http://localhost:8888/metrics

# Check spanmetrics output
curl http://localhost:8889/metrics | grep llm_traces
```

### System Commands

```bash
# Check listening ports
netstat -tulpn | grep -E '(4317|4318|8889|9090|8428)'

# Check disk usage
df -h

# Check memory usage
free -h

# Check process CPU/memory
top -p $(docker inspect -f '{{.State.Pid}}' otel-collector)
```

---

## Common Configurations

### Configuration 1: ML Inference Workloads

Optimized for ML inference latency (seconds to minutes):

```yaml
# otel-collector-config.yaml
connectors:
  spanmetrics:
    histogram:
      explicit:
        buckets: [0.01, 0.05, 0.1, 0.5, 1, 2.5, 5, 10, 30, 60] # Optimized for inference latency
    dimensions:
      - name: model_name
      - name: model_version
      - name: environment
      - name: gpu_type
    dimensions_cache_size: 5000

exporters:
  prometheus:
    endpoint: "0.0.0.0:8889"
    namespace: inference
```

### Configuration 2: High-Throughput APIs

Optimized for high request rates:

```yaml
# otel-collector-config.yaml
processors:
  batch:
    timeout: 500ms
    send_batch_size: 16384
    send_batch_max_size: 32768

  memory_limiter:
    check_interval: 1s
    limit_mib: 8192
    spike_limit_mib: 2048

connectors:
  spanmetrics:
    histogram:
      explicit:
        buckets: [0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1, 5]
    dimensions_cache_size: 10000
```

### Configuration 3: Multi-Tenant

Separate metrics by tenant/customer:

```yaml
# otel-collector-config.yaml
connectors:
  spanmetrics:
    dimensions:
      - name: tenant_id
      - name: environment
      - name: service_name
    dimensions_cache_size: 10000

# prometheus.yaml
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

### Configuration 4: Development/Testing

Lower retention, higher verbosity:

```yaml
# victoriametrics
command:
  - "-retentionPeriod=1" # 1 month only

# prometheus.yaml
global:
  scrape_interval: 5s # Higher frequency

# otel-collector-config.yaml
exporters:
  debug:
    verbosity: detailed # More detailed logs

service:
  telemetry:
    logs:
      level: debug
```

### Configuration 5: Production (High Availability)

```yaml
# prometheus.yaml
global:
  scrape_interval: 10s
  external_labels:
    cluster: production
    region: us-east-1

remote_write:
  - url: http://victoriametrics:8428/api/v1/write
    queue_config:
      capacity: 50000
      max_shards: 200
      min_shards: 10

# otel-collector-config.yaml
processors:
  memory_limiter:
    check_interval: 1s
    limit_mib: 4096
    spike_limit_mib: 512

  batch:
    timeout: 200ms
    send_batch_size: 8192

service:
  telemetry:
    logs:
      level: info # Less verbose
```

---

## Additional Resources

### Documentation

- **OpenTelemetry Collector**: https://opentelemetry.io/docs/collector/
- **OpenTelemetry SDK**: https://opentelemetry.io/docs/instrumentation/
- **Prometheus**: https://prometheus.io/docs/
- **PromQL**: https://prometheus.io/docs/prometheus/latest/querying/basics/
- **VictoriaMetrics**: https://docs.victoriametrics.com/
- **Docker Compose**: https://docs.docker.com/compose/

### Tools

- **otel-cli**: https://github.com/equinix-labs/otel-cli  
  CLI tool for sending test spans
- **PromLens**: https://promlens.com/  
  Query builder for PromQL

- **Promtool**: Built into Prometheus
  ```bash
  docker exec prometheus promtool check config /etc/prometheus/prometheus.yaml
  ```

### OpenTelemetry SDKs

- **Python**: https://opentelemetry.io/docs/instrumentation/python/
- **JavaScript**: https://opentelemetry.io/docs/instrumentation/js/
- **Go**: https://opentelemetry.io/docs/instrumentation/go/
- **Java**: https://opentelemetry.io/docs/instrumentation/java/
- **.NET**: https://opentelemetry.io/docs/instrumentation/net/

### Community

- **OpenTelemetry Slack**: https://cloud-native.slack.com/ (#otel channels)
- **Prometheus Community**: https://prometheus.io/community/
- **VictoriaMetrics Slack**: https://slack.victoriametrics.com/

### Learning Resources

- **OpenTelemetry Bootcamp**: https://opentelemetry.io/docs/demo/
- **Prometheus Examples**: https://github.com/prometheus/prometheus/tree/main/documentation/examples
- **PromQL for Humans**: https://timber.io/blog/promql-for-humans/

---

## Quick Reference Card

### Common Tasks

| Task                | Command                                            |
| ------------------- | -------------------------------------------------- |
| Start full stack    | `docker compose --profile full up -d`              |
| View logs           | `docker compose logs -f`                           |
| Check health        | `curl http://localhost:13133/health/status`        |
| Query metrics       | `curl http://localhost:9090/api/v1/query?query=up` |
| Stop stack          | `docker compose down`                              |
| Restart collector   | `docker compose restart otel-collector`            |
| View resource usage | `docker stats`                                     |

### Common Queries

| Metric       | Query                                                                                       |
| ------------ | ------------------------------------------------------------------------------------------- |
| Request rate | `rate(llm_traces_span_metrics_calls_total[5m])`                                             |
| Error rate   | `rate(llm_traces_span_metrics_calls_total{status_code="STATUS_CODE_ERROR"}[5m])`            |
| P95 latency  | `histogram_quantile(0.95, sum by (le) (rate(llm_traces_span_metrics_duration_bucket[5m])))` |

### Troubleshooting

| Issue                         | Solution                                  |
| ----------------------------- | ----------------------------------------- |
| Collector not receiving spans | Check firewall, verify endpoint in app    |
| Metrics not appearing         | Check spanmetrics config in pipelines     |
| High memory usage             | Add memory_limiter processor              |
| Slow queries                  | Use recording rules or reduce cardinality |

---

## Next Steps

- **Return to main guide**: [Advanced Setup](../ADVANCED_SETUP.md)
- **Deploy your stack**: [Deployment Guide](deployment-guide.md)

[← Back to Advanced Setup](../ADVANCED_SETUP.md)
