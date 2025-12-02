# Production Guide

[← Back to Advanced Setup](../ADVANCED_SETUP.md)

This guide covers production considerations including high availability, resource sizing, data persistence, backups, and performance tuning.

## Table of Contents

- [High Availability](#high-availability)
- [Resource Sizing](#resource-sizing)
- [Data Persistence](#data-persistence)
- [Backup Strategy](#backup-strategy)
- [Performance Tuning](#performance-tuning)

---

## High Availability

### Collector HA

Deploy multiple collector instances behind a load balancer:

```
Load Balancer (4317/4318)
↓
├─ Collector 1
├─ Collector 2
└─ Collector 3
```

#### Implementation

**1. Deploy Multiple Instances**:

```bash
# On host 1
docker compose --profile full up -d

# On host 2
docker compose --profile full up -d

# On host 3
docker compose --profile full up -d
```

**2. Configure Load Balancer** (e.g., AWS ALB):

- Target Group: Collectors on port 4317/4318
- Health Check: `http://<collector>:13133/health/status`

**3. Configure Applications to Send to Load Balancer**:

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT=http://<load-balancer>:4318
```

### Prometheus HA

For Prometheus high availability, deploy multiple instances with identical configuration:

```bash
# Prometheus 1
docker compose --profile full up -d

# Prometheus 2 (on different host)
docker compose --profile full up -d
```

Both instances will:

- Scrape the same targets
- Remote write to VictoriaMetrics
- VictoriaMetrics will deduplicate identical samples

### VictoriaMetrics HA

For VictoriaMetrics clustering (horizontal scaling), see the [VictoriaMetrics cluster documentation](https://docs.victoriametrics.com/Cluster-VictoriaMetrics.html).

---

## Resource Sizing

### OpenTelemetry Collector

| Metric | Recommended Value | Notes                                 |
| ------ | ----------------- | ------------------------------------- |
| CPU    | 2-4 cores         | 1 core per 10k spans/sec              |
| Memory | 2-4 GB            | Depends on batch size and cardinality |
| Disk   | 10 GB             | For logs and temporary state          |

**Scaling Guidelines**:

- **10k spans/sec**: 2 cores, 2 GB RAM
- **50k spans/sec**: 4 cores, 4 GB RAM
- **100k+ spans/sec**: Consider horizontal scaling with load balancer

### Prometheus

| Metric              | Formula                             | Example (100k active series) |
| ------------------- | ----------------------------------- | ---------------------------- |
| Memory              | `active_series * 1-3 KB`            | 100k \* 2 KB = 200 MB        |
| Disk (2h retention) | `samples/sec * 2 bytes * 2h * 3600` | ~1 GB                        |

**Scaling Guidelines**:

- **100k series**: 2 cores, 4 GB RAM, 50 GB disk
- **1M series**: 4 cores, 8 GB RAM, 200 GB disk
- **10M+ series**: Consider federation or sharding

### VictoriaMetrics

| Metric | Recommended Value         | Notes                                  |
| ------ | ------------------------- | -------------------------------------- |
| CPU    | 2-8 cores                 | Scales with query concurrency          |
| Memory | 8-32 GB                   | More memory = better query performance |
| Disk   | See retention table below | ~50 GB per month per 1M series         |

**Disk Usage Estimates**:

| Retention Period | Disk Usage (1M active series) |
| ---------------- | ----------------------------- |
| 1 month          | ~50 GB                        |
| 6 months         | ~300 GB                       |
| 12 months        | ~600 GB                       |
| 24 months        | ~1.2 TB                       |

---

## Data Persistence

By default, Docker volumes are used for persistence:

```yaml
volumes:
  prometheus_data:
  victoriametrics_data:
```

### For Production: Mount to Host Directories

Edit `docker-compose.yaml`:

```yaml
volumes:
  prometheus_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /mnt/data/prometheus

  victoriametrics_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /mnt/data/victoriametrics
```

**Create the directories**:

```bash
sudo mkdir -p /mnt/data/prometheus
sudo mkdir -p /mnt/data/victoriametrics
sudo chown -R 65534:65534 /mnt/data/prometheus  # Prometheus runs as nobody
sudo chown -R 1000:1000 /mnt/data/victoriametrics
```

### Using EBS Volumes (AWS)

For AWS deployments, mount EBS volumes:

```bash
# Attach EBS volume to EC2 instance
aws ec2 attach-volume --volume-id vol-xxx --instance-id i-xxx --device /dev/sdf

# Format and mount
sudo mkfs.ext4 /dev/sdf
sudo mkdir -p /mnt/data
sudo mount /dev/sdf /mnt/data

# Add to /etc/fstab for persistence
echo '/dev/sdf /mnt/data ext4 defaults,nofail 0 2' | sudo tee -a /etc/fstab
```

---

## Backup Strategy

### VictoriaMetrics Snapshots

**1. Create Snapshot**:

```bash
curl http://localhost:8428/snapshot/create
# Response: {"status":"ok","snapshot":"20251201"}

# Snapshot stored in: /victoria-metrics-data/snapshots/20251201
```

**2. Copy to Backup Location**:

```bash
rsync -av /mnt/data/victoriametrics/snapshots/20251201 s3://my-backup-bucket/
```

**3. Automated Backups via Cron**:

```bash
#!/bin/bash
# /usr/local/bin/backup-victoriametrics.sh

SNAPSHOT=$(curl -s http://localhost:8428/snapshot/create | jq -r .snapshot)
rsync -av /mnt/data/victoriametrics/snapshots/$SNAPSHOT /backup/victoriametrics/
find /backup/victoriametrics/ -mtime +30 -delete  # Keep 30 days
```

Add to crontab:

```bash
# Daily backup at 2 AM
0 2 * * * /usr/local/bin/backup-victoriametrics.sh
```

### Prometheus Snapshots

**Enable Admin API** in `prometheus.yaml`:

```yaml
# Add to command in docker-compose.yaml
command:
  - "--config.file=/etc/prometheus/prometheus.yaml"
  - "--storage.tsdb.path=/prometheus"
  - "--web.enable-admin-api"
```

**Create Snapshot**:

```bash
curl -XPOST http://localhost:9090/api/v1/admin/tsdb/snapshot
# Response includes snapshot path
```

---

## Performance Tuning

### Collector Tuning

#### Batch Processor

Increase batch sizes for higher throughput:

```yaml
processors:
  batch:
    timeout: 500ms # Longer timeout = larger batches
    send_batch_size: 16384 # Increase batch size
    send_batch_max_size: 32768
```

**Metrics to Monitor**:

- `otelcol_processor_batch_batch_send_size` (histogram)
- `otelcol_processor_batch_timeout_trigger_send` (counter)

#### Memory Limiter

Prevent OOM crashes:

```yaml
processors:
  memory_limiter:
    check_interval: 1s
    limit_mib: 4096 # 4 GB limit
    spike_limit_mib: 512 # Allow 512 MB spikes

  batch: {}

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, batch] # memory_limiter FIRST
      exporters: [spanmetrics]
```

### Prometheus Tuning

#### Scrape Performance

For high cardinality targets:

```yaml
scrape_configs:
  - job_name: "otel-collector"
    scrape_interval: 15s # Increase if needed
    scrape_timeout: 10s # Must be < scrape_interval
    static_configs:
      - targets: ["otel-collector:8889"]
    metric_relabel_configs:
      # Drop high-cardinality metrics you don't need
      - source_labels: [__name__]
        regex: "go_gc_.*"
        action: drop
```

#### Query Performance with Recording Rules

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

Mount rules file:

```yaml
prometheus:
  image: prom/prometheus:latest
  volumes:
    - ./prometheus.yaml:/etc/prometheus/prometheus.yaml:ro
    - ./rules.yml:/etc/prometheus/rules.yml:ro # Add this
```

### VictoriaMetrics Tuning

#### Memory Usage

```yaml
command:
  - "-retentionPeriod=12"
  - "-httpListenAddr=:8428"
  - "-memory.allowedPercent=70" # Use 70% of system RAM
  - "-search.maxMemoryPerQuery=0" # No limit (default: 1GB)
```

#### Ingestion Performance

```yaml
command:
  - "-retentionPeriod=12"
  - "-httpListenAddr=:8428"
  - "-insert.maxQueueDuration=30s" # Queue samples for up to 30s during spikes
```

#### Query Performance

```yaml
command:
  - "-retentionPeriod=12"
  - "-httpListenAddr=:8428"
  - "-search.maxConcurrentRequests=32" # Increase for more concurrent queries
  - "-search.maxQueryDuration=120s" # Allow longer queries
  - "-search.maxPointsPerTimeseries=30000" # Increase for finer resolution
```

---

## Production Checklist

Before going to production, ensure:

- [ ] **High Availability**: Multiple instances of critical components
- [ ] **Resource Sizing**: Adequate CPU, memory, and disk for expected load
- [ ] **Data Persistence**: Host-mounted volumes or EBS volumes
- [ ] **Backups**: Automated backup strategy in place
- [ ] **Monitoring**: Observability stack metrics are being collected
- [ ] **Security**: TLS, authentication, and network restrictions (see [Security Guide](security.md))
- [ ] **Performance Tuning**: Batch sizes, memory limits, and query optimizations applied
- [ ] **Alerting**: Alerts configured for critical metrics
- [ ] **Documentation**: Runbooks for common operations and troubleshooting

---

## Next Steps

- **Secure your deployment**: [Security Guide](security.md)
- **Reference materials**: [Reference Guide](reference.md)
- **Return to main guide**: [Advanced Setup](../ADVANCED_SETUP.md)

[← Back to Advanced Setup](../ADVANCED_SETUP.md)
