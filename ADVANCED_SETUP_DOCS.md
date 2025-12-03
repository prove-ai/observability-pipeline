# Advanced Customer Setup Guide - Observability Pipeline

Version: 1.0
Last Updated: December 2025
Target Audience: DevOps Engineers, Infrastructure Engineers, ML Engineers deploying inference workloads

═══════════════════════════════════════════════════════════════════════════════

TABLE OF CONTENTS

1. Introduction
2. Architecture Overview
3. Deployment Profile Selection Guide
4. Configuration Reference
5. Deployment Methods
6. Advanced Integration Patterns
7. Production Considerations
8. Performance Tuning
9. Security & Compliance
10. Monitoring the Observability Stack
11. Advanced Troubleshooting
12. Migration Scenarios
13. Appendix

═══════════════════════════════════════════════════════════════════════════════

1. INTRODUCTION

This guide provides comprehensive instructions for deploying and configuring the Observability Pipeline in production environments. The pipeline converts OpenTelemetry (OTLP) traces into Prometheus metrics, stores them in VictoriaMetrics for long-term retention, and provides flexible deployment options to integrate with your existing infrastructure.

WHAT THIS PIPELINE DOES

• Receives OTLP traces via gRPC (port 4317) and HTTP (port 4318)
• Converts spans to metrics using the spanmetrics connector
• Exports metrics to Prometheus format (port 8889)
• Scrapes metrics into Prometheus (10-second interval)
• Stores metrics long-term in VictoriaMetrics (12-month retention)
• Exposes Prometheus-compatible query API via VictoriaMetrics

PREREQUISITES

• Familiarity with: Docker, Prometheus, basic observability concepts
• Infrastructure: Docker and Docker Compose installed (or Ansible for remote deployment)
• Network Access: Appropriate firewall rules and security group configurations
• SSH Access: For Ansible-based deployments to EC2 instances

═══════════════════════════════════════════════════════════════════════════════

2. ARCHITECTURE OVERVIEW

DATA FLOW

Application (OTLP traces)
↓
↓ gRPC (4317) / HTTP (4318)
↓
OpenTelemetry Collector
├── Receives OTLP traces
├── Processes with batch processor
├── Converts spans → metrics (spanmetrics connector)
└── Exports to Prometheus format (8889)
↓
↓ Prometheus scrape (every 10s)
↓
Prometheus (9090)
├── Short-term storage
└── remote_write →
↓
VictoriaMetrics (8428)
└── Long-term storage (12 months)

COMPONENT RESPONSIBILITIES

OpenTelemetry Collector (otel-collector)
• Image: otel/opentelemetry-collector-contrib:0.138.0
• Primary Role: Ingest OTLP traces and convert to metrics
• Ports:

- 4317: OTLP gRPC receiver
- 4318: OTLP HTTP receiver
- 8889: Prometheus metrics exporter (spanmetrics output)
- 8888: Internal collector metrics (for monitoring the collector itself)
- 13133: Health check endpoint
- 1888: pprof profiling (optional, for performance debugging)
- 55679: zpages debugging (optional, for live pipeline inspection)

Note: pprof and zpages extensions are optional and primarily used for debugging. Enable them in the extensions section of your collector configuration.

Prometheus
• Image: prom/prometheus:latest
• Primary Role: Scrape metrics and provide query interface
• Port: 9090
• Scrape Interval: 10 seconds (configurable)
• Storage: Short-term local TSDB + remote_write to VictoriaMetrics

VictoriaMetrics
• Image: victoriametrics/victoria-metrics:latest
• Primary Role: Long-term metric storage
• Port: 8428
• Retention: 12 months (configurable)
• API: Prometheus-compatible query API

NETWORK ARCHITECTURE

All services communicate over a Docker bridge network named "observability". External applications send traces to the collector's exposed ports, and Prometheus scrapes metrics from the collector's exporter.

═══════════════════════════════════════════════════════════════════════════════

3. DEPLOYMENT PROFILE SELECTION GUIDE

The Observability Pipeline supports six deployment profiles to accommodate various infrastructure scenarios. You MUST specify a profile when starting the stack because all services are profile-scoped.

PROFILE DECISION MATRIX

Your Existing Infrastructure → Recommended Profile → Services Deployed
─────────────────────────────────────────────────────────────────────────────
Nothing (greenfield) → full → Collector + Prometheus + VictoriaMetrics
Prometheus only → no-prometheus → Collector + VictoriaMetrics
VictoriaMetrics only → no-vm → Collector + Prometheus
OpenTelemetry Collector only → no-collector → Prometheus + VictoriaMetrics
Prometheus + VictoriaMetrics → vm-only → VictoriaMetrics only
Storage backend (external) → prom-only → Prometheus only

───────────────────────────────────────────────────────────────────────────────
PROFILE 1: full (Complete Stack)
───────────────────────────────────────────────────────────────────────────────

Use When: Starting from scratch or deploying a self-contained observability stack.

Services: OpenTelemetry Collector, Prometheus, VictoriaMetrics

Command:
cd docker-compose
docker compose --profile full up -d

Configuration Required: None (uses defaults)

Data Flow:
Apps → Collector (4317/4318) → Prometheus (9090) → VictoriaMetrics (8428)

Verification:

# Check all services are running

docker compose ps

# Verify collector health

curl http://localhost:13133/health/status

# Verify Prometheus targets

curl http://localhost:9090/api/v1/targets

# Verify VictoriaMetrics health

curl http://localhost:8428/health

Use Cases:
• New deployments
• Development/testing environments
• Self-contained observability for single-team projects
• ML inference workloads with no existing monitoring

───────────────────────────────────────────────────────────────────────────────
PROFILE 2: no-prometheus (Integrate with Existing Prometheus)
───────────────────────────────────────────────────────────────────────────────

Use When: You have an existing Prometheus instance and want to add trace-to-metrics capability + long-term storage.

Services: OpenTelemetry Collector, VictoriaMetrics

Command:
cd docker-compose
docker compose --profile no-prometheus up -d

Configuration Required:

1. Add Collector Scrape Targets to Your Prometheus (prometheus.yml):

scrape_configs: # Scrape spanmetrics (converted from traces) - job_name: "otel-collector"
static_configs: - targets: ["<collector-host>:8889"]

    # Scrape collector internal metrics (optional but recommended)
    - job_name: "otel-collector-internal"
      static_configs:
        - targets: ["<collector-host>:8888"]

Replace <collector-host> with:
• otel-collector if your Prometheus is on the same Docker network
• localhost if your Prometheus runs on the same host
• The EC2 instance IP/DNS if Prometheus is external

2. Configure Remote Write to VictoriaMetrics:

remote_write: - url: http://<victoriametrics-host>:8428/api/v1/write # Optional: Configure queue settings for high-throughput scenarios
queue_config:
capacity: 10000
max_shards: 50
min_shards: 1
max_samples_per_send: 5000
batch_send_deadline: 5s

Replace <victoriametrics-host> with:
• victoriametrics if on the same Docker network
• The container/host IP if external

3. Network Connectivity:

# Test from your Prometheus host

curl http://<collector-host>:8889/metrics
curl http://<victoriametrics-host>:8428/health

Common Scenarios:
• Central Prometheus scraping multiple clusters
• Kubernetes clusters with existing Prometheus Operator
• Organizations with standardized Prometheus deployments

───────────────────────────────────────────────────────────────────────────────
PROFILE 3: no-vm (Integrate with Existing VictoriaMetrics)
───────────────────────────────────────────────────────────────────────────────

Use When: You have an existing VictoriaMetrics instance (or other long-term storage) and need Prometheus + Collector.

Services: OpenTelemetry Collector, Prometheus

Command:
cd docker-compose
docker compose --profile no-vm up -d

Configuration Required:

1. Edit docker-compose/prometheus.yaml to point to your VictoriaMetrics:

remote_write: - url: http://<your-victoriametrics-host>:8428/api/v1/write # Optional: Add authentication if your VM requires it # basic_auth: # username: your-username # password: your-password

2. Network Connectivity:

# Test from the Prometheus container

docker exec prometheus curl http://<your-vm-host>:8428/health

Alternative: If you don't want long-term storage at all, comment out the remote_write block entirely.

Common Scenarios:
• Centralized VictoriaMetrics cluster
• Managed VictoriaMetrics service (e.g., VictoriaMetrics Cloud)
• Alternative storage backends (Thanos, Cortex, M3DB)

───────────────────────────────────────────────────────────────────────────────
PROFILE 4: no-collector (Integrate with Existing Collector)
───────────────────────────────────────────────────────────────────────────────

Use When: You have an existing OpenTelemetry Collector (perhaps in a Kubernetes daemonset or sidecar) and need Prometheus + VictoriaMetrics for storage.

Services: Prometheus, VictoriaMetrics

Command:
cd docker-compose
docker compose --profile no-collector up -d

Configuration Required:

1. Update Your Existing Collector to expose Prometheus metrics:

Ensure your collector config includes:

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
readers: - pull:
exporter:
prometheus:
host: 0.0.0.0
port: 8888

    pipelines:
      metrics:
        receivers: [spanmetrics]  # Or your metrics source
        exporters: [prometheus]

2. Edit docker-compose/prometheus.yaml to scrape your collector:

scrape_configs: - job_name: "otel-collector"
static_configs: - targets: ["<your-collector-host>:8889"]

    - job_name: "otel-collector-internal"
      static_configs:
        - targets: ["<your-collector-host>:8888"]

3. Ensure OTLP Receivers are configured in your collector:

receivers:
otlp:
protocols:
grpc:
endpoint: 0.0.0.0:4317
http:
endpoint: 0.0.0.0:4318

Common Scenarios:
• Kubernetes with OpenTelemetry Operator
• Multi-cluster environments with centralized collectors
• Service mesh with sidecar collectors (Istio + OTel)

───────────────────────────────────────────────────────────────────────────────
PROFILE 5: vm-only (VictoriaMetrics Standalone)
───────────────────────────────────────────────────────────────────────────────

Use When: You only need VictoriaMetrics for long-term storage and have your own Prometheus + Collector elsewhere.

Services: VictoriaMetrics

Command:
cd docker-compose
docker compose --profile vm-only up -d

Configuration Required:

1. Configure Your Prometheus to remote_write to this VictoriaMetrics instance:

remote_write: - url: http://<victoriametrics-host>:8428/api/v1/write

Verification:
curl http://localhost:8428/health

# Query metrics via Prometheus-compatible API

curl 'http://localhost:8428/api/v1/query?query=up'

Common Scenarios:
• Consolidating multiple Prometheus instances into one storage backend
• Replacing aging Prometheus storage with VictoriaMetrics
• Cost reduction by centralizing long-term storage

───────────────────────────────────────────────────────────────────────────────
PROFILE 6: prom-only (Prometheus Standalone)
───────────────────────────────────────────────────────────────────────────────

Use When: You only need Prometheus for scraping and querying, with external storage or no long-term retention.

Services: Prometheus

Command:
cd docker-compose
docker compose --profile prom-only up -d

Configuration Required:

1. Edit docker-compose/prometheus.yaml:

   a. If you have external storage:

   remote_write:

   - url: http://<your-storage-backend>:8428/api/v1/write

   b. If you don't need long-term storage:

   # Comment out or remove the remote_write block

   # remote_write:

   # - url: ...

2. Configure Scrape Targets:

Since the collector is not included, point Prometheus at your own exporters:

scrape_configs: - job_name: "your-application"
static_configs: - targets: - "your-app-host:9100" - "another-app:8080"

    # If you have an external OTel Collector
    - job_name: "otel-collector"
      static_configs:
        - targets: ["<external-collector>:8889"]

Common Scenarios:
• Testing Prometheus configurations
• Temporary monitoring setups
• Development environments with no persistence requirements

═══════════════════════════════════════════════════════════════════════════════

4. CONFIGURATION REFERENCE

OPENTELEMETRY COLLECTOR CONFIGURATION

File: docker-compose/otel-collector-config.yaml

RECEIVERS

receivers:
otlp:
protocols:
grpc:
endpoint: 0.0.0.0:4317 # Optional: Configure maximum message size # max_recv_msg_size_mib: 4 # max_concurrent_streams: 100
http:
endpoint: 0.0.0.0:4318 # Optional: Configure CORS for browser-based apps # cors: # allowed_origins: # - "https://your-app.com"

Customization Options:

Parameter | Default | Description | When to Change
─────────────────────────────────────────────────────────────────────────────────────
endpoint | 0.0.0.0:4317 | Bind address for gRPC | Restrict to specific interface
max_recv_msg_size_mib | 4 MB | Max gRPC message size | Large traces/spans
max_concurrent_streams | 100 | Max concurrent gRPC streams | High concurrency

PROCESSORS

processors:
batch: # Default: 8192 spans per batch, 200ms timeout
timeout: 200ms
send_batch_size: 8192
send_batch_max_size: 16384

Recommended Tuning:

Scenario | timeout | send_batch_size | send_batch_max_size
────────────────────────────────────────────────────────────────────
Low latency | 100ms | 1024 | 2048
Balanced (default) | 200ms | 8192 | 16384
High throughput | 500ms | 16384 | 32768

Additional Processors (add to processors: section):

processors:
batch: {}

    # Filter out noisy spans
    filter/drop-health-checks:
      spans:
        exclude:
          match_type: regexp
          attributes:
            - key: http.target
              value: "/health.*"

    # Add resource attributes
    resource:
      attributes:
        - key: environment
          value: "production"
          action: upsert
        - key: deployment.id
          from_attribute: k8s.deployment.name
          action: insert

    # Sample high-volume traces
    probabilistic_sampler:
      sampling_percentage: 10.0  # Keep 10% of traces

CONNECTORS (Spanmetrics)

The spanmetrics connector is the core component that converts traces into metrics.

connectors:
spanmetrics:
histogram:
explicit:
buckets: [0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1, 5, 10] # Customize for your latency profile # Example for ML inference (seconds): # buckets: [0.01, 0.05, 0.1, 0.5, 1, 2.5, 5, 10, 30, 60]

      dimensions:
        - name: env
        - name: component
        # Add more dimensions as needed:
        # - name: model_name
        # - name: model_version
        # - name: customer_id

      dimensions_cache_size: 1000
      # Increase if you have many unique dimension combinations
      # dimensions_cache_size: 10000

Histogram Bucket Selection:

Use Case | Recommended Buckets | Explanation
──────────────────────────────────────────────────────────────────────────────────
Web APIs | [0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1, 5, 10] | Millisecond to second range
ML Inference | [0.01, 0.05, 0.1, 0.5, 1, 2.5, 5, 10, 30, 60] | Second to minute range
Batch Jobs | [1, 5, 10, 30, 60, 300, 600, 1800, 3600] | Minute to hour range
Database Queries | [0.0001, 0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1] | Sub-millisecond to second

Dimensions:

Dimensions become Prometheus labels. Each unique combination creates a new time series.

dimensions: - name: env # Matches span attribute "env" - name: component # Matches span attribute "component" - name: http.status_code # Can use dotted attribute names - name: model.name # Custom attributes from your app

CARDINALITY WARNING: Each unique combination of dimension values creates a separate time series. Be cautious with high-cardinality dimensions (user IDs, request IDs, etc.).

Automatic Dimensions (always included):
• service_name
• span_name
• span_kind
• status_code

EXPORTERS

exporters:
prometheus:
endpoint: "0.0.0.0:8889"
namespace: llm # Metric prefix (llm*traces_span_metrics*\*)
resource_to_telemetry_conversion:
enabled: true # Include resource attributes as labels
enable_open_metrics: true

    debug:
      verbosity: detailed  # Options: basic, normal, detailed
      # Change to "basic" in production to reduce logs

Namespace Customization:

The namespace parameter prefixes all metric names:

namespace: llm

# Results in: llm_traces_span_metrics_calls_total

namespace: inference

# Results in: inference_traces_span_metrics_calls_total

EXTENSIONS

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

Additional Configuration Notes:

• health_check: Required for monitoring and health probes
• pprof: Provides runtime profiling data (CPU, memory, goroutines). Access at http://localhost:1888/debug/pprof/
• zpages: Provides live debugging pages for pipelines, extensions, and feature gates. Access at http://localhost:55679/debug/servicez

Advanced health_check options:

extensions:
health_check:
endpoint: 0.0.0.0:13133
path: /health/status
check_collector_pipeline:
enabled: true
interval: 5m
exporter_failure_threshold: 5

SERVICE PIPELINES

service:
extensions: [health_check, pprof, zpages]

Note: If using pprof and zpages extensions, ensure the ports are exposed in your Docker Compose configuration:

otel-collector:
ports:

- 4317:4317
- 4318:4318
- 8888:8888
- 8889:8889
- 13133:13133
- 1888:1888 # pprof (optional, for debugging)
- 55679:55679 # zpages (optional, for debugging)

For production deployments, consider restricting access to debugging ports (1888, 55679) or removing them entirely.

telemetry:
metrics:
level: detailed # Options: none, basic, normal, detailed
readers: - pull:
exporter:
prometheus:
host: 0.0.0.0
port: 8888 # Internal collector metrics
logs:
level: debug # Options: debug, info, warn, error # Change to "info" in production

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

Adding Additional Pipelines:

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

───────────────────────────────────────────────────────────────────────────────
PROMETHEUS CONFIGURATION
───────────────────────────────────────────────────────────────────────────────

File: docker-compose/prometheus.yaml

global:
scrape_interval: 10s # Optional global settings: # scrape_timeout: 10s # evaluation_interval: 15s # For recording rules # external_labels: # cluster: 'production-us-east-1' # environment: 'production'

SCRAPE INTERVAL TUNING

Use Case | Recommended Interval | Trade-off
───────────────────────────────────────────────────────────────
Development | 5s | High granularity, high load
Production (default) | 10s | Balanced
High-scale | 30s or 60s | Lower load, less granularity

REMOTE WRITE CONFIGURATION

remote_write: - url: http://victoriametrics:8428/api/v1/write

      # Optional: Performance tuning
      queue_config:
        capacity: 10000              # Queue size before dropping samples
        max_shards: 50               # Max parallel write shards
        min_shards: 1                # Min parallel write shards
        max_samples_per_send: 5000   # Batch size
        batch_send_deadline: 5s      # Max time before sending partial batch
        min_backoff: 30ms            # Min retry backoff
        max_backoff: 5s              # Max retry backoff

      # Optional: Write relabeling (filter what gets sent)
      # write_relabel_configs:
      #   - source_labels: [__name__]
      #     regex: 'go_.*'  # Don't remote_write Go internal metrics
      #     action: drop

      # Optional: Authentication
      # basic_auth:
      #   username: your-username
      #   password: your-password
      # OR
      # bearer_token: your-token
      # OR
      # bearer_token_file: /path/to/token

High-Throughput Remote Write Tuning:

For high metric volumes (>100k samples/sec):

remote_write: - url: http://victoriametrics:8428/api/v1/write
queue_config:
capacity: 50000
max_shards: 200
min_shards: 10
max_samples_per_send: 10000
batch_send_deadline: 10s

SCRAPE CONFIGURATIONS

scrape_configs: # Scrape spanmetrics from OTel Collector - job_name: "otel-collector"
static_configs: - targets: ["otel-collector:8889"] # Optional: Add labels to all metrics from this job # relabel_configs: # - target_label: environment # replacement: production

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

SERVICE DISCOVERY

Prometheus supports multiple service discovery mechanisms:

scrape_configs:

# File-based discovery

- job_name: "file-sd"
  file_sd_configs:
  - files:
    - "/etc/prometheus/targets/\*.json"
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

───────────────────────────────────────────────────────────────────────────────
VICTORIAMETRICS CONFIGURATION
───────────────────────────────────────────────────────────────────────────────

VictoriaMetrics is configured via command-line flags in the Docker Compose file.

Current Configuration:

victoriametrics:
image: victoriametrics/victoria-metrics:latest
command: - '-retentionPeriod=12' # 12 months - '-httpListenAddr=:8428' # Listen port
volumes: - victoriametrics_data:/victoria-metrics-data
ports: - "8428:8428"

Additional Configuration Options:

command: - '-retentionPeriod=12' # Retention in months - '-httpListenAddr=:8428' - '-storageDataPath=/victoria-metrics-data' # Data directory - '-memory.allowedPercent=80' # % of system memory to use - '-search.maxQueryDuration=30s' # Max query duration - '-search.maxConcurrentRequests=16' # Max concurrent queries - '-dedup.minScrapeInterval=10s' # Dedupe identical samples within interval # Enable cluster mode (for horizontal scaling) # - '-promscrape.config=/etc/prometheus/prometheus.yml'

Retention Tuning:

Retention Period | Flag Value | Disk Usage Estimate (1M active series)
─────────────────────────────────────────────────────────────────────────────────
1 month | -retentionPeriod=1 | ~50 GB
6 months | -retentionPeriod=6 | ~300 GB
12 months (default) | -retentionPeriod=12 | ~600 GB
24 months | -retentionPeriod=24 | ~1.2 TB

Memory Tuning:

VictoriaMetrics is memory-efficient but benefits from more RAM for caching:

command: - '-retentionPeriod=12' - '-httpListenAddr=:8428' - '-memory.allowedPercent=60' # Conservative (default: 80%) # OR specify absolute memory limit: # - '-memory.allowedBytes=8GB'

Deduplication:

If you scrape the same metrics from multiple Prometheus instances:

command: - '-retentionPeriod=12' - '-httpListenAddr=:8428' - '-dedup.minScrapeInterval=10s' # Must match or be larger than scrape interval

═══════════════════════════════════════════════════════════════════════════════

5. DEPLOYMENT METHODS

LOCAL DOCKER COMPOSE DEPLOYMENT

Using Docker Compose Directly

# Navigate to docker-compose directory

cd docker-compose

# Start with a specific profile

docker compose --profile full up -d

# View logs

docker compose logs -f

# View specific service logs

docker compose logs -f otel-collector

# Stop services

docker compose down

# Stop and remove volumes (clears all data)

docker compose down -v

Using the Makefile

The repository includes a Makefile for convenience:

# From repository root

# Start the full stack

make up

# View logs

make logs
make logs-otel
make logs-prometheus
make logs-vm

# Check status

make status

# Restart services

make restart

# Stop services

make down

# Clean up everything (including volumes)

make clean

# Show all available commands

make help

───────────────────────────────────────────────────────────────────────────────
AWS EC2 DEPLOYMENT VIA ANSIBLE
───────────────────────────────────────────────────────────────────────────────

The repository includes Ansible playbooks for automated deployment to AWS EC2 instances.

PREREQUISITES

1. Ansible Installed Locally:

# macOS

brew install ansible

# Ubuntu/Debian

sudo apt-get install ansible

# Via pip

pip install ansible

2. EC2 Instance Running:
   • Ubuntu 20.04+ or Amazon Linux 2+
   • SSH access configured
   • Security group allows required ports

3. Security Group Configuration:

Port | Protocol | Service | Required For
──────────────────────────────────────────────────────────────────
22 | TCP | SSH | Ansible deployment
4317 | TCP | OTLP gRPC | Trace ingestion
4318 | TCP | OTLP HTTP | Trace ingestion
8888 | TCP | Collector internal metrics | Monitoring
8889 | TCP | Collector exporter metrics | Prometheus scraping
9090 | TCP | Prometheus | Query interface
8428 | TCP | VictoriaMetrics | Query API / Remote write
13133 | TCP | Health check | Monitoring

Optional Debugging Ports (not recommended for production):

Port | Protocol | Service | Required For
──────────────────────────────────────────────────────────────────
1888 | TCP | pprof | Performance profiling (debugging only)
55679 | TCP | zpages | Live pipeline debugging (debugging only)

Security Note: Do NOT expose ports 1888 and 55679 to the public internet. These debugging ports expose sensitive system information and should only be accessible from trusted networks or via VPN. Consider using Security Group rules to restrict access to specific IP addresses.

CONFIGURATION

1. Edit Inventory File (playbooks/inventory.ini):

[ec2_instances]

# Single instance

observability-pipeline ansible_host=3.144.2.209 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/my-key.pem

# Multiple instances (will deploy to all)

# observability-pipeline-1 ansible_host=1.2.3.4 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/my-key.pem

# observability-pipeline-2 ansible_host=5.6.7.8 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/my-key.pem

[ec2_instances:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no'

DEPLOYMENT

1. Test Connectivity:

cd playbooks
ansible all -m ping

2. Dry Run (check what will change):

ansible-playbook deploy.yml --check --diff

3. Deploy:

ansible-playbook deploy.yml

4. Or use Makefile:

# From repository root

make ansible-ping # Test connectivity
make ansible-check # Validate syntax
make ansible-deploy-dry-run # Dry run
make deploy # Deploy

POST-DEPLOYMENT

1. Verify Services:

# SSH to instance

ssh -i ~/.ssh/my-key.pem ubuntu@<ec2-ip>

# Check Docker containers

cd /opt/observability-pipeline/docker-compose
docker compose ps

# View logs

docker compose logs -f

2. Test Endpoints:

# From your local machine

curl http://<ec2-ip>:13133/health/status
curl http://<ec2-ip>:9090/-/healthy
curl http://<ec2-ip>:8428/health

3. Send Test Trace:

otel-cli span \
 --service "test-app" \
 --name "test-span" \
 --endpoint http://<ec2-ip>:4318/v1/traces \
 --protocol http/protobuf

CUSTOMIZING THE ANSIBLE PLAYBOOK

Change Deployment Path:

vars:
deploy_path: "/home/ubuntu/observability" # Instead of /opt/observability-pipeline

Change Docker Compose Profile:

The playbook now supports a compose_profile variable for easy profile selection:

vars:
deploy_user: "{{ ansible_user | default('ubuntu') }}"
deploy_path: "/opt/observability-pipeline"
compose_profile: "full" # Change to: no-vm, no-prometheus, no-collector, vm-only, or prom-only

This variable is used in all Docker Compose commands throughout the playbook:
• docker compose --profile {{ compose_profile }} up -d
• docker compose --profile {{ compose_profile }} down
• docker compose --profile {{ compose_profile }} ps

To use a different profile, simply change the compose_profile value in the vars section.

Add Environment Variables:

- name: Start Docker Compose services
  shell: sg docker -c "cd {{ deploy_path }}/docker-compose && docker compose --profile {{ compose_profile }} up -d"
  environment:
  PATH: "/usr/local/bin:/usr/bin:/bin"
  OTEL_EXPORTER_OTLP_ENDPOINT: "http://localhost:4318"

═══════════════════════════════════════════════════════════════════════════════

6. ADVANCED INTEGRATION PATTERNS

PATTERN 1: Multi-Region Deployment with Central Storage

Scenario: Deploy collectors in multiple AWS regions, scrape with regional Prometheus instances, aggregate in central VictoriaMetrics.

Architecture:

Region 1 (us-east-1):
Collector → Prometheus → remote_write → Central VM

Region 2 (eu-west-1):
Collector → Prometheus → remote_write → Central VM

Central Region (us-east-1):
VictoriaMetrics (aggregates all regions)

Implementation:

1. Deploy in Each Region (use no-vm profile):

# On each regional deployment

docker compose --profile no-vm up -d

2. Configure Regional Prometheus to point to central VM:

# prometheus.yaml in each region

global:
external_labels:
region: us-east-1 # Change per region
environment: production

remote_write: - url: http://<central-vm-host>:8428/api/v1/write
queue_config:
capacity: 50000
max_shards: 100

3. Deploy Central VictoriaMetrics:

docker compose --profile vm-only up -d

4. Query Across Regions:

# Query all regions

sum by (service_name) (llm_traces_span_metrics_calls_total)

# Query specific region

llm_traces_span_metrics_calls_total{region="us-east-1"}

PATTERN 2: Kubernetes Integration

Scenario: Deploy collectors in Kubernetes, use the Observability Pipeline for storage and querying.

Architecture:

Kubernetes Cluster:
Pods → OTel Collector (DaemonSet) →
↓
External:
Prometheus (scrapes via NodePort/LoadBalancer)
VictoriaMetrics (long-term storage)

PATTERN 3: Hybrid Cloud (On-Prem + Cloud)

Scenario: On-premises applications send traces to cloud-hosted Observability Pipeline.

Architecture:

On-Premises:
Apps → On-Prem Collector →
↓ (Secure tunnel: VPN / Direct Connect)
Cloud (AWS):
Central Collector → Prometheus → VictoriaMetrics

═══════════════════════════════════════════════════════════════════════════════

7. PRODUCTION CONSIDERATIONS

HIGH AVAILABILITY

Collector HA

Deploy multiple collector instances behind a load balancer:

Load Balancer (4317/4318)
↓
├─ Collector 1
├─ Collector 2
└─ Collector 3

Implementation:

1. Deploy Multiple Instances:

# On host 1

docker compose --profile full up -d

# On host 2

docker compose --profile full up -d

# On host 3

docker compose --profile full up -d

2. Configure Load Balancer (e.g., AWS ALB):
   • Target Group: Collectors on port 4317/4318
   • Health Check: http://<collector>:13133/health/status

3. Configure Applications to send to load balancer:

export OTEL_EXPORTER_OTLP_ENDPOINT=http://<load-balancer>:4318

RESOURCE SIZING

OpenTelemetry Collector

Metric | Recommended Value | Notes
─────────────────────────────────────────────────────────────────
CPU | 2-4 cores | 1 core per 10k spans/sec
Memory | 2-4 GB | Depends on batch size and cardinality
Disk | 10 GB | For logs and temporary state

Prometheus

Metric | Formula | Example (100k active series)
─────────────────────────────────────────────────────────────────────────────────────
Memory | active*series * 1-3 KB | 100k _ 2 KB = 200 MB
Disk (2h retention) | samples/sec _ 2 bytes \_ 2h \* 3600 | ~1 GB

VictoriaMetrics

Metric | Recommended Value | Notes
──────────────────────────────────────────────────────────────────────
CPU | 2-8 cores | Scales with query concurrency
Memory | 8-32 GB | More memory = better query performance
Disk | See retention table above | ~50 GB per month per 1M series

DATA PERSISTENCE

By default, Docker volumes are used for persistence:

volumes:
prometheus_data:
victoriametrics_data:

For Production, mount to host directories:

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

BACKUP STRATEGY

1. VictoriaMetrics Snapshots:

# Create snapshot

curl http://localhost:8428/snapshot/create

# Response: {"status":"ok","snapshot":"20251201"}

# Snapshot stored in: /victoria-metrics-data/snapshots/20251201

# Copy to backup location

rsync -av /mnt/data/victoriametrics/snapshots/20251201 s3://my-backup-bucket/

2. Prometheus Snapshots:

# Enable admin API in prometheus.yaml

# --web.enable-admin-api

curl -XPOST http://localhost:9090/api/v1/admin/tsdb/snapshot

3. Automated Backups (via cron):

#!/bin/bash
SNAPSHOT=$(curl -s http://localhost:8428/snapshot/create | jq -r .snapshot)
  rsync -av /mnt/data/victoriametrics/snapshots/$SNAPSHOT /backup/victoriametrics/
find /backup/victoriametrics/ -mtime +30 -delete # Keep 30 days

═══════════════════════════════════════════════════════════════════════════════

8. PERFORMANCE TUNING

COLLECTOR TUNING

Batch Processor

Increase batch sizes for higher throughput:

processors:
batch:
timeout: 500ms # Longer timeout = larger batches
send_batch_size: 16384 # Increase batch size
send_batch_max_size: 32768

Metrics to Monitor:
• otelcol_processor_batch_batch_send_size (histogram)
• otelcol_processor_batch_timeout_trigger_send (counter)

Memory Limiter

Prevent OOM crashes:

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

PROMETHEUS TUNING

Scrape Performance

For high cardinality targets:

scrape*configs: - job_name: "otel-collector"
scrape_interval: 15s # Increase if needed
scrape_timeout: 10s # Must be < scrape_interval
static_configs: - targets: ["otel-collector:8889"]
metric_relabel_configs: # Drop high-cardinality metrics you don't need - source_labels: [__name__]
regex: 'go_gc*.\*'
action: drop

Query Performance

Use recording rules for expensive queries:

# prometheus.yaml

rule_files:

- "/etc/prometheus/rules.yml"

# rules.yml

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

Mount rules file:

prometheus:
image: prom/prometheus:latest
volumes: - ./prometheus.yaml:/etc/prometheus/prometheus.yaml:ro - ./rules.yml:/etc/prometheus/rules.yml:ro # Add this

VICTORIAMETRICS TUNING

Memory Usage

command: - '-retentionPeriod=12' - '-httpListenAddr=:8428' - '-memory.allowedPercent=70' # Use 70% of system RAM - '-search.maxMemoryPerQuery=0' # No limit (default: 1GB)

Ingestion Performance

command: - '-retentionPeriod=12' - '-httpListenAddr=:8428' - '-insert.maxQueueDuration=30s' # Queue samples for up to 30s during spikes

Query Performance

command: - '-retentionPeriod=12' - '-httpListenAddr=:8428' - '-search.maxConcurrentRequests=32' # Increase for more concurrent queries - '-search.maxQueryDuration=120s' # Allow longer queries - '-search.maxPointsPerTimeseries=30000' # Increase for finer resolution

═══════════════════════════════════════════════════════════════════════════════

9. SECURITY & COMPLIANCE

SECURING DEBUGGING ENDPOINTS

The OpenTelemetry Collector debugging extensions (pprof and zpages) expose sensitive information about your system and should be secured in production.

Recommendations:

1. Disable in Production:

For production environments, disable debugging extensions entirely:

service:
extensions: [health_check] # Remove pprof and zpages

2. Restrict Access via Firewall:

If you need debugging capabilities in production, restrict access to specific IPs:

# iptables example

iptables -A INPUT -p tcp --dport 1888 -s 10.0.0.100 -j ACCEPT
iptables -A INPUT -p tcp --dport 1888 -j DROP
iptables -A INPUT -p tcp --dport 55679 -s 10.0.0.100 -j ACCEPT
iptables -A INPUT -p tcp --dport 55679 -j DROP

3. Use Reverse Proxy with Authentication:

Place a reverse proxy (nginx, Envoy) in front of debugging endpoints with authentication:

# nginx example

location /debug/ {
auth_basic "Restricted";
auth_basic_user_file /etc/nginx/.htpasswd;
proxy_pass http://localhost:55679/debug/;
}

4. Bind to Localhost Only:

For local debugging only, bind to localhost:

extensions:
pprof:
endpoint: 127.0.0.1:1888 # Only accessible from localhost
zpages:
endpoint: 127.0.0.1:55679 # Only accessible from localhost

TLS/SSL CONFIGURATION

Collector TLS

Enable TLS for OTLP receivers:

receivers:
otlp:
protocols:
grpc:
endpoint: 0.0.0.0:4317
tls:
cert_file: /etc/otel/certs/server.crt
key_file: /etc/otel/certs/server.key
client_ca_file: /etc/otel/certs/ca.crt # Optional: mTLS
http:
endpoint: 0.0.0.0:4318
tls:
cert_file: /etc/otel/certs/server.crt
key_file: /etc/otel/certs/server.key

AUTHENTICATION & AUTHORIZATION

Basic Auth (Prometheus)

Protect Prometheus endpoints:

# prometheus.yaml

global:
scrape_interval: 10s

# Add to Docker Compose

prometheus:
image: prom/prometheus:latest
command: - '--config.file=/etc/prometheus/prometheus.yaml' - '--web.config.file=/etc/prometheus/web-config.yml' # Add this
volumes: - ./prometheus.yaml:/etc/prometheus/prometheus.yaml:ro - ./web-config.yml:/etc/prometheus/web-config.yml:ro

Create web-config.yml:

basic_auth_users:
admin: $2y$10$... # bcrypt hash of password # Generate with: htpasswd -nBC 10 "" | tr -d ':\n'

Bearer Token Auth (VictoriaMetrics)

Use a reverse proxy (nginx) for token-based auth:

# nginx.conf

server {
listen 8429 ssl;

ssl_certificate /etc/nginx/certs/server.crt;
ssl_certificate_key /etc/nginx/certs/server.key;

location / {
if ($http_authorization != "Bearer YOUR_SECRET_TOKEN") {
return 401;
}
proxy_pass http://victoriametrics:8428;
}
}

NETWORK SECURITY

Firewall Rules (iptables)

# Allow OTLP from specific CIDR

iptables -A INPUT -p tcp --dport 4317 -s 10.0.0.0/8 -j ACCEPT
iptables -A INPUT -p tcp --dport 4318 -s 10.0.0.0/8 -j ACCEPT

# Allow Prometheus from specific IPs

iptables -A INPUT -p tcp --dport 9090 -s 192.168.1.100 -j ACCEPT

# Drop all other traffic to observability ports

iptables -A INPUT -p tcp --dport 4317 -j DROP
iptables -A INPUT -p tcp --dport 4318 -j DROP
iptables -A INPUT -p tcp --dport 9090 -j DROP

AWS Security Group

# Create security group

aws ec2 create-security-group \
 --group-name observability-sg \
 --description "Observability Pipeline Security Group"

# Allow OTLP from VPC

aws ec2 authorize-security-group-ingress \
 --group-id sg-xxx \
 --protocol tcp \
 --port 4317-4318 \
 --cidr 10.0.0.0/16

# Allow Prometheus from specific IP

aws ec2 authorize-security-group-ingress \
 --group-id sg-xxx \
 --protocol tcp \
 --port 9090 \
 --cidr 1.2.3.4/32

DATA PRIVACY

PII Scrubbing

Add processors to remove sensitive data:

processors:
attributes/scrub-pii:
actions: - key: user.email
action: delete - key: user.id
action: hash - key: credit_card
action: delete

    batch: {}

service:
pipelines:
traces:
receivers: [otlp]
processors: [attributes/scrub-pii, batch]
exporters: [spanmetrics]

═══════════════════════════════════════════════════════════════════════════════

10. MONITORING THE OBSERVABILITY STACK

MONITORING THE COLLECTOR

Key Metrics (access at http://localhost:8888/metrics):

Metric | Type | Description
────────────────────────────────────────────────────────────────────────────────
otelcol_receiver_accepted_spans | Counter | Total spans received
otelcol_receiver_refused_spans | Counter | Spans rejected (backpressure)
otelcol_processor_batch_batch_send_size | Histogram | Batch sizes
otelcol_exporter_sent_spans | Counter | Spans exported successfully
otelcol_exporter_send_failed_spans | Counter | Failed exports

MONITORING PROMETHEUS

Key Metrics:

Metric | Description
──────────────────────────────────────────────────────────────────────────
prometheus_tsdb_head_series | Active time series
prometheus_tsdb_head_samples_appended_total | Samples ingested
prometheus_remote_storage_samples_failed_total | Remote write failures
prometheus_rule_evaluation_failures_total | Rule evaluation errors

MONITORING VICTORIAMETRICS

Key Metrics (access at http://localhost:8428/metrics):

Metric | Description
─────────────────────────────────────────────────────
vm_rows | Total data points stored
vm_free_disk_space_bytes | Free disk space
vm_cache_entries | Cache entries
vm_slow_queries_total | Slow queries

═══════════════════════════════════════════════════════════════════════════════

11. ADVANCED TROUBLESHOOTING

DEBUGGING TOOLS

The collector provides built-in debugging extensions that can help diagnose issues:

1. Zpages (Port 55679):

Zpages provides live debugging information about the collector's internal state.

Enable zpages in your collector config:

extensions:
zpages:
endpoint: 0.0.0.0:55679

service:
extensions: [health_check, zpages]

Access zpages:

# View service status

http://localhost:55679/debug/servicez

# View pipeline information

http://localhost:55679/debug/pipelinez

# View extensions

http://localhost:55679/debug/extensionz

# View feature gates

http://localhost:55679/debug/featurez

Use Cases:
• Check if pipelines are running
• See receiver/processor/exporter health
• Debug configuration issues
• View real-time pipeline statistics

2. Pprof (Port 1888):

Pprof provides Go runtime profiling data for performance analysis.

Enable pprof in your collector config:

extensions:
pprof:
endpoint: 0.0.0.0:1888

service:
extensions: [health_check, pprof]

Access pprof:

# View available profiles

http://localhost:1888/debug/pprof/

# CPU profile (30 seconds)

curl http://localhost:1888/debug/pprof/profile?seconds=30 -o cpu.prof

# Memory heap profile

curl http://localhost:1888/debug/pprof/heap -o heap.prof

# Goroutine profile

curl http://localhost:1888/debug/pprof/goroutine -o goroutine.prof

Analyze profiles with go tool:

go tool pprof cpu.prof
go tool pprof heap.prof

Use Cases:
• Diagnose high CPU usage
• Find memory leaks
• Identify goroutine leaks
• Performance optimization

3. Debug Exporter:

The debug exporter logs all telemetry to stdout (already enabled in example configs).

Set verbosity level:

exporters:
debug:
verbosity: detailed # Options: basic, normal, detailed

Use Cases:
• Verify spans are being received
• Check span attributes and structure
• Debug spanmetrics dimension issues

ISSUE: Spans Not Converting to Metrics

Symptoms:
• Collector receives spans (visible in logs)
• No metrics appear at :8889/metrics

Diagnosis:

1. Check spanmetrics connector config:

docker exec otel-collector cat /etc/otel/config.yaml

Ensure spanmetrics is in the traces pipeline exporters:

pipelines:
traces:
exporters: [spanmetrics, debug] # spanmetrics must be here

2. Check metrics pipeline:

pipelines:
metrics:
receivers: [spanmetrics] # spanmetrics must be a receiver
exporters: [prometheus]

3. Verify dimensions exist in spans:

# Check debug logs for span attributes

docker compose logs otel-collector | grep -A 20 "Span #0"

If env and component dimensions are configured but not present in spans, metrics won't have those labels.

Solution:
• Ensure your application sends the expected span attributes
• Or remove non-existent dimensions from the config

ISSUE: High Memory Usage (Collector)

Symptoms:
• Collector container OOM killed
• High memory usage (>4GB)

Causes:

1. High span rate without batching
2. Large dimensions_cache_size with high cardinality
3. Memory leak (rare, but possible in contrib components)

Solutions:

1. Add memory_limiter:

processors:
memory_limiter:
check_interval: 1s
limit_mib: 4096
spike_limit_mib: 512
batch: {}

service:
pipelines:
traces:
processors: [memory_limiter, batch]

2. Reduce dimensions_cache_size:

connectors:
spanmetrics:
dimensions_cache_size: 1000 # Reduce from 10000

ISSUE: High Cardinality Explosion

Symptoms:
• Prometheus memory usage growing rapidly
• VictoriaMetrics disk usage growing rapidly
• Slow queries

Diagnosis:

# Check series count

count({**name**=~".+"})

# Find high-cardinality metrics

topk(10, count by (**name**) ({**name**=~".+"}))

Causes:
• High-cardinality dimensions (user_id, request_id, timestamp)
• Misconfigured spanmetrics dimensions

Solutions:

1. Remove high-cardinality dimensions:

connectors:
spanmetrics:
dimensions: - name: env - name: component # Remove: user_id, request_id, etc.

2. Drop high-cardinality metrics:

scrape_configs: - job_name: "otel-collector"
metric_relabel_configs: - source_labels: [__name__, user_id]
action: drop

═══════════════════════════════════════════════════════════════════════════════

12. MIGRATION SCENARIOS

SCENARIO 1: Migrating from Prometheus-only to Full Stack

Current State: Prometheus scraping application exporters
Target State: OTLP traces → Collector → Prometheus → VictoriaMetrics

Steps:

1. Deploy Collector + VictoriaMetrics:

docker compose --profile no-prometheus up -d

2. Update Existing Prometheus Config:

# Add collector scrape target

scrape_configs: - job_name: "otel-collector"
static_configs: - targets: ["otel-collector:8889"]

    # Keep existing exporters
    - job_name: "my-app"
      static_configs:
        - targets: ["my-app:9100"]

# Add remote_write

remote_write: - url: http://victoriametrics:8428/api/v1/write

3. Instrument Applications to send OTLP traces

4. Verify metrics appear in Prometheus

5. Gradually migrate applications from exporters to OTLP

SCENARIO 2: Migrating from Jaeger to OpenTelemetry Collector

Current State: Applications sending traces to Jaeger
Target State: Applications → OTel Collector (with Jaeger receiver) → spanmetrics

Steps:

1. Add Jaeger Receiver to collector config:

receivers:
otlp:
protocols:
grpc:
http:

jaeger:
protocols:
grpc:
endpoint: 0.0.0.0:14250
thrift_http:
endpoint: 0.0.0.0:14268

service:
pipelines:
traces:
receivers: [otlp, jaeger] # Add jaeger
processors: [batch]
exporters: [spanmetrics, debug]

2. Expose Jaeger Ports in Docker Compose:

otel-collector:
ports: - 14250:14250 # Jaeger gRPC - 14268:14268 # Jaeger HTTP

3. Point Applications at collector:

# Instead of Jaeger endpoint

export JAEGER_AGENT_HOST=jaeger-collector

# Use OTel Collector

export JAEGER_AGENT_HOST=otel-collector

4. No Application Code Changes needed (Jaeger SDK still works)

5. Gradually Migrate to OpenTelemetry SDK for better functionality

SCENARIO 3: Consolidating Multiple Prometheus Instances

Current State: Multiple Prometheus instances in different environments
Target State: Central VictoriaMetrics aggregating all metrics

Steps:

1. Deploy Central VictoriaMetrics:

docker compose --profile vm-only up -d

2. Configure Each Prometheus to remote_write to central VM:

# Prometheus in Environment 1

global:
external_labels:
environment: production
region: us-east-1

remote_write: - url: http://<central-vm>:8428/api/v1/write

3. Query Across Environments:

# All environments

sum by (service_name) (llm_traces_span_metrics_calls_total)

# Specific environment

llm_traces_span_metrics_calls_total{environment="production"}

4. Optional: Federate Prometheus if you need a central query interface:

# Central Prometheus (queries VM instead of scraping)

scrape_configs:

- job*name: "federate"
  honor_labels: true
  metrics_path: /federate
  params:
  match[]: - '{**name**=~"llm*.\*"}'
  static_configs:
  - targets: ["<vm-host>:8428"]

═══════════════════════════════════════════════════════════════════════════════

13. APPENDIX

METRIC REFERENCE

Spanmetrics Output

The spanmetrics connector generates the following metrics:

Metric Name | Type | Description
─────────────────────────────────────────────────────────────────────────────
llm_traces_span_metrics_calls_total | Counter | Total number of spans
llm_traces_span_metrics_duration_bucket | Histogram | Span duration histogram
llm_traces_span_metrics_duration_sum | Counter | Total duration of all spans
llm_traces_span_metrics_duration_count | Counter | Count of spans (same as calls_total)

Labels: service_name, span_name, span_kind, status_code, [custom dimensions]

Label Values:
• span_kind: SPAN_KIND_CLIENT, SPAN_KIND_SERVER, SPAN_KIND_INTERNAL, SPAN_KIND_PRODUCER, SPAN_KIND_CONSUMER
• status_code: STATUS_CODE_UNSET, STATUS_CODE_OK, STATUS_CODE_ERROR

EXAMPLE QUERIES

Request rate (requests per second):
rate(llm_traces_span_metrics_calls_total[5m])

Error rate:
rate(llm_traces_span_metrics_calls_total{status_code="STATUS_CODE_ERROR"}[5m])

Error percentage:
sum(rate(llm_traces_span_metrics_calls_total{status_code="STATUS_CODE_ERROR"}[5m]))
/
sum(rate(llm_traces_span_metrics_calls_total[5m]))

- 100

P50 latency:
histogram_quantile(0.50,
sum by (service_name, le) (
rate(llm_traces_span_metrics_duration_bucket[5m])
)
)

P95 latency:
histogram_quantile(0.95,
sum by (service_name, le) (
rate(llm_traces_span_metrics_duration_bucket[5m])
)
)

P99 latency:
histogram_quantile(0.99,
sum by (service_name, le) (
rate(llm_traces_span_metrics_duration_bucket[5m])
)
)

Average latency:
rate(llm_traces_span_metrics_duration_sum[5m])
/
rate(llm_traces_span_metrics_duration_count[5m])

PORT REFERENCE

Port | Service | Component | Purpose | Required
────────────────────────────────────────────────────────────────────────────────
4317 | OTLP gRPC | Collector | Receive traces (gRPC) | Yes
4318 | OTLP HTTP | Collector | Receive traces (HTTP) | Yes
8889 | Prometheus Exporter | Collector | Expose spanmetrics | Yes
8888 | Internal Metrics | Collector | Collector self-monitoring | Yes
13133 | Health Check | Collector | Health/readiness checks | Yes
1888 | pprof | Collector | Profiling (debugging) | Optional
55679 | zpages | Collector | Debugging UI | Optional
9090 | HTTP | Prometheus | Query API / UI | Yes
8428 | HTTP | VictoriaMetrics | Query API / Remote write | Yes

Note: Ports 1888 (pprof) and 55679 (zpages) are only accessible if you enable these extensions in your collector configuration. They are optional and primarily used for debugging and performance analysis.

USEFUL COMMANDS

Docker Commands:

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

Prometheus Commands:

# Check configuration

curl http://localhost:9090/api/v1/status/config

# Check targets

curl http://localhost:9090/api/v1/targets

# Query API

curl 'http://localhost:9090/api/v1/query?query=up'

# Check TSDB status

curl http://localhost:9090/api/v1/status/tsdb

VictoriaMetrics Commands:

# Health check

curl http://localhost:8428/health

# Metrics

curl http://localhost:8428/metrics

# Query (Prometheus-compatible)

curl 'http://localhost:8428/api/v1/query?query=up'

# Create snapshot

curl http://localhost:8428/snapshot/create

OpenTelemetry Collector Debugging Commands:

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

COMMON CONFIGURATIONS

Configuration: ML Inference Workloads

# otel-collector-config.yaml

connectors:
spanmetrics:
histogram:
explicit:
buckets: [0.01, 0.05, 0.1, 0.5, 1, 2.5, 5, 10, 30, 60] # Optimized for inference latency
dimensions: - name: model_name - name: model_version - name: environment - name: gpu_type
dimensions_cache_size: 5000

exporters:
prometheus:
endpoint: "0.0.0.0:8889"
namespace: inference

Configuration: High-Throughput APIs

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

Configuration: Multi-Tenant

# otel-collector-config.yaml

connectors:
spanmetrics:
dimensions: - name: tenant_id - name: environment - name: service_name
dimensions_cache_size: 10000

# prometheus.yaml

scrape_configs:

- job_name: "otel-collector"
  static_configs:
  - targets: ["otel-collector:8889"]
    metric_relabel_configs:
  # Drop internal tenant metrics
  - source_labels: [tenant_id]
    regex: "internal.\*"
    action: drop

ADDITIONAL RESOURCES

Documentation:
• OpenTelemetry Collector: https://opentelemetry.io/docs/collector/
• Prometheus: https://prometheus.io/docs/
• VictoriaMetrics: https://docs.victoriametrics.com/
• Docker Compose: https://docs.docker.com/compose/

Tools:
• otel-cli: https://github.com/equinix-labs/otel-cli (CLI tool for sending test spans)
• PromLens: https://promlens.com/ (Query builder for PromQL)
• Grafana: https://grafana.com/ (Visualization - compatible with this stack)

═══════════════════════════════════════════════════════════════════════════════

CONCLUSION

This guide covered advanced deployment scenarios, configuration options, and best practices for the Observability Pipeline. Key takeaways:

1. Choose the Right Profile: Match your deployment profile to your existing infrastructure
2. Configure for Your Use Case: Tune histogram buckets, dimensions, and resource limits
3. Monitor the Monitors: Set up alerts for the observability stack itself
4. Plan for Scale: Use HA deployments and tune for high throughput
5. Secure by Default: Enable TLS, authentication, and network restrictions

For additional support or questions, refer to the project README or contact your infrastructure team.

═══════════════════════════════════════════════════════════════════════════════

Document Version: 1.0
Last Updated: December 2025
Maintainer: Infrastructure Team
