# Architecture & Getting Started Guide

[← Back to Advanced Setup](../ADVANCED_SETUP.md)

## What This Pipeline Does

This observability pipeline solves a common problem: **how to monitor distributed applications using OpenTelemetry traces**. Instead of instrumenting your application twice (once for traces, once for metrics), this pipeline automatically derives metrics from traces and stores them for long-term analysis.

**In Plain English:**

- Your application sends traces (using OpenTelemetry)
- The pipeline converts those traces into useful metrics (request rate, errors, latency)
- You can query and visualize these metrics in any Prometheus-compatible tool
- All metrics are stored for 12 months with efficient compression

## Quick Start (5 Minutes)

### Prerequisites

Before you begin, ensure you have:

- ✅ **Docker** installed (version 20.10+)
- ✅ **Docker Compose** installed (version 2.0+)
- ✅ Basic familiarity with terminal/command line
- ✅ _Optional_: `otel-cli` for sending test traces

**Check your setup:**

```bash
docker --version        # Should show Docker 20.10+
docker compose version  # Should show Docker Compose 2.0+
```

### Start the Full Stack (Greenfield Setup)

If you're starting from scratch with no existing monitoring infrastructure:

```bash
# Clone or navigate to the repository
cd /path/to/observability-pipeline

# Start everything with one command
cd docker-compose
docker compose --profile full up -d
```

**That's it!** You now have a complete observability stack running:

```
✓ OpenTelemetry Collector (receiving traces)
✓ Prometheus (scraping and querying metrics)
✓ VictoriaMetrics (storing metrics for 12 months)
```

### Verify It's Working

```bash
# 1. Check all services are healthy
docker compose ps

# 2. Verify OpenTelemetry Collector is ready
curl http://localhost:13133/health/status
# Expected: {"status":"Server available"}

# 3. Verify Prometheus can reach targets
curl http://localhost:9090/api/v1/targets | jq
# Expected: All targets showing "up"

# 4. Verify VictoriaMetrics is running
curl http://localhost:8428/health
# Expected: "OK"
```

### Send Your First Trace

Install `otel-cli` (optional but helpful for testing):

```bash
# macOS
brew install equinix-labs/otel-cli/otel-cli

# Linux
curl -L https://github.com/equinix-labs/otel-cli/releases/latest/download/otel-cli-linux-amd64 -o /usr/local/bin/otel-cli
chmod +x /usr/local/bin/otel-cli
```

Send a test trace:

```bash
otel-cli span \
  --service "my-app" \
  --name "test-request" \
  --endpoint http://localhost:4318/v1/traces \
  --protocol http/protobuf \
  --attrs "environment=dev,user_id=123"
```

**View the results** (wait 10-15 seconds for metrics to appear):

```bash
# Open Prometheus in your browser
open http://localhost:9090

# Run this query in the Prometheus UI
llm_traces_span_metrics_calls_total{service_name="my-app"}
```

You should see your test span converted into a metric! 🎉

---

## Architecture Deep Dive

### Data Flow

```
Your Application
│ (sends OpenTelemetry traces)
│
├─[gRPC: port 4317]
└─[HTTP: port 4318]
     ↓
┌────────────────────────────────┐
│  OpenTelemetry Collector       │
│  ┌──────────────────────────┐  │
│  │ 1. Receives OTLP traces  │  │
│  │ 2. Batches spans         │  │
│  │ 3. Converts to metrics   │  │
│  │    (spanmetrics)         │  │
│  └──────────────────────────┘  │
└────────────────────────────────┘
     ↓ (exports Prometheus format)
     ↓ [port 8889]
     ↓
┌────────────────────────────────┐
│  Prometheus                    │
│  ┌──────────────────────────┐  │
│  │ • Scrapes every 10s      │  │
│  │ • Stores locally (TSDB)  │  │
│  │ • Provides query API     │  │
│  │ • Forwards to VM         │  │
│  └──────────────────────────┘  │
└────────────────────────────────┘
     ↓ (remote_write)
     ↓
┌────────────────────────────────┐
│  VictoriaMetrics               │
│  ┌──────────────────────────┐  │
│  │ • Long-term storage      │  │
│  │ • 12 month retention     │  │
│  │ • Prometheus-compatible  │  │
│  │ • 10x compression        │  │
│  └──────────────────────────┘  │
└────────────────────────────────┘
```

### Component Responsibilities

#### OpenTelemetry Collector (otel-collector)

**What it does:** The entry point for all traces from your applications.

- **Image**: `otel/opentelemetry-collector-contrib:0.138.0`
- **Primary Role**: Receive traces, convert to metrics, export to Prometheus
- **Key Feature**: Spanmetrics connector transforms traces into RED metrics

**Ports:**

- `4317` - OTLP gRPC receiver (recommended for production)
- `4318` - OTLP HTTP receiver (easier for testing)
- `8889` - Prometheus metrics exporter (spanmetrics output)
- `8888` - Internal collector metrics (monitor the collector itself)
- `13133` - Health check endpoint
- `1888` - pprof profiling (debugging only)
- `55679` - zpages debugging (debugging only)

**Configuration file:** `docker-compose/otel-collector-config.yaml`

#### Prometheus

**What it does:** Scrapes metrics from the collector and provides a query interface.

- **Image**: `prom/prometheus:latest`
- **Primary Role**: Metrics scraping, querying, and forwarding
- **Port**: `9090` (Web UI and API)
- **Scrape Interval**: 10 seconds (configurable in `prometheus.yaml`)
- **Storage**: Local TSDB + remote write to VictoriaMetrics

**Configuration file:** `docker-compose/prometheus.yaml`

**Access the UI:** `http://localhost:9090`

#### VictoriaMetrics

**What it does:** Stores metrics long-term with efficient compression.

- **Image**: `victoriametrics/victoria-metrics:latest`
- **Primary Role**: Long-term metric storage
- **Port**: `8428`
- **Retention**: 12 months (configurable via `-retentionPeriod` flag)
- **API**: Prometheus-compatible query API

**Access the API:** `http://localhost:8428`

**Why use it?** VictoriaMetrics uses ~10x less disk space than Prometheus for the same data.

### Network Architecture

All services run on a Docker bridge network named `observability`:

```
External Applications
     ↓
     ↓ (send traces to localhost:4317 or :4318)
     ↓
┌─────────────────────────────────────────┐
│  observability Docker network           │
│                                         │
│  otel-collector ←→ prometheus ←→ VM    │
│  (4317,4318)       (9090)      (8428)  │
│                                         │
└─────────────────────────────────────────┘
```

**Important:** Applications outside Docker can send traces to `localhost:4317/4318`, but services inside Docker should use the service name `otel-collector:4317`.

---

## Integration Options

### Option 1: Full Stack (Recommended for New Setups)

**Use when:** You have no existing monitoring infrastructure.

**Command:** `docker compose --profile full up -d`

**What you get:** Collector + Prometheus + VictoriaMetrics

**Next steps:** [Skip to Testing & Verification](#testing--verification)

---

### Option 2: I Already Have Prometheus

**Use when:** You have an existing Prometheus instance.

**Command:** `docker compose --profile no-prometheus up -d`

**What you get:** Collector + VictoriaMetrics

**Required configuration:** Add these scrape targets to your existing Prometheus:

```yaml
# In your prometheus.yml
scrape_configs:
  - job_name: "otel-collector"
    static_configs:
      - targets: ["localhost:8889"] # spanmetrics

  - job_name: "otel-collector-internal"
    static_configs:
      - targets: ["localhost:8888"] # collector health metrics
```

**Next steps:** [Deployment Profiles Guide](deployment-profiles.md#profile-2-no-prometheus-bring-your-own-prometheus)

---

### Option 3: I Already Have VictoriaMetrics

**Use when:** You have an existing VictoriaMetrics or other long-term storage.

**Command:** `docker compose --profile no-vm up -d`

**What you get:** Collector + Prometheus

**Required configuration:** Point Prometheus to your VictoriaMetrics by editing `docker-compose/prometheus.yaml`:

```yaml
remote_write:
  - url: http://your-victoriametrics-host:8428/api/v1/write
```

**Next steps:** [Deployment Profiles Guide](deployment-profiles.md#profile-3-no-vm-bring-your-own-victoriametrics)

---

### Option 4: I Already Have an OpenTelemetry Collector

**Use when:** You have an existing OTel Collector (e.g., in Kubernetes).

**Command:** `docker compose --profile no-collector up -d`

**What you get:** Prometheus + VictoriaMetrics

**Required configuration:** Configure your existing collector to export Prometheus metrics on port 8889.

**Next steps:** [Deployment Profiles Guide](deployment-profiles.md#profile-4-no-collector-bring-your-own-collector)

---

### Option 5: Other Combinations

See the complete [Deployment Profiles Guide](deployment-profiles.md) for:

- `vm-only` - Only VictoriaMetrics
- `prom-only` - Only Prometheus

---

## Testing & Verification

### Step 1: Check Container Health

```bash
# Should show all containers as "Up" or "healthy"
docker compose ps

# Expected output:
# NAME              STATUS    PORTS
# otel-collector    Up        0.0.0.0:4317->4317/tcp, ...
# prometheus        Up        0.0.0.0:9090->9090/tcp
# victoriametrics   Up        0.0.0.0:8428->8428/tcp
```

### Step 2: Verify OpenTelemetry Collector

```bash
# Health check
curl http://localhost:13133/health/status

# Expected: {"status":"Server available","upSince":"..."}
```

### Step 3: Verify Prometheus Targets

```bash
# Check targets via API
curl http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'

# Or open in browser
open http://localhost:9090/targets
```

**Expected:** Both targets showing `health: "up"`:

- `otel-collector` (port 8889)
- `otel-collector-internal` (port 8888)

### Step 4: Send a Test Trace

```bash
otel-cli span \
  --service "test-service" \
  --name "test-operation" \
  --endpoint http://localhost:4318/v1/traces \
  --protocol http/protobuf \
  --attrs "env=dev"
```

### Step 5: Verify Metrics Appear

Wait 15 seconds, then query Prometheus:

```bash
# Via API
curl 'http://localhost:9090/api/v1/query?query=llm_traces_span_metrics_calls_total' | jq

# Or open Prometheus UI
open http://localhost:9090
# Then run: llm_traces_span_metrics_calls_total{service_name="test-service"}
```

### Step 6: Verify VictoriaMetrics

```bash
# Health check
curl http://localhost:8428/health
# Expected: OK

# Query metrics (same as Prometheus API)
curl 'http://localhost:8428/api/v1/query?query=up' | jq
```

---

## Key Design Decisions

### Why Spanmetrics?

The spanmetrics connector automatically generates **RED metrics** from traces:

- **Rate**: `llm_traces_span_metrics_calls_total` (requests per second)
- **Errors**: Filtered by `status_code="STATUS_CODE_ERROR"`
- **Duration**: `llm_traces_span_metrics_latency_bucket` (p50, p95, p99 latency)

**Benefit:** Instrument once with OpenTelemetry, get both traces and metrics.

### Why VictoriaMetrics?

| Feature             | Prometheus              | VictoriaMetrics     |
| ------------------- | ----------------------- | ------------------- |
| Storage efficiency  | 1x                      | 10x better          |
| Long-term retention | ❌ Not designed for it  | ✅ Optimized for it |
| Query API           | ✅ Standard             | ✅ Compatible       |
| Resource usage      | High for long retention | Low                 |

**Benefit:** Store 12 months of metrics using 10% of the disk space.

### Why Keep Prometheus?

- **Ecosystem**: Vast tooling and integrations
- **Service Discovery**: Built-in for Kubernetes, AWS, Consul, etc.
- **Recording Rules**: Pre-compute expensive queries
- **Buffering**: If VictoriaMetrics goes down, Prometheus retains recent data

**Benefit:** Best of both worlds - Prometheus for flexibility, VictoriaMetrics for storage.

---

## Troubleshooting

### Containers won't start

```bash
# Check logs for errors
docker compose logs otel-collector
docker compose logs prometheus
docker compose logs victoriametrics

# Common issue: Ports already in use
# Solution: Stop conflicting services or change ports in docker-compose.yaml
```

### Prometheus shows no metrics

1. **Check targets:** Visit `http://localhost:9090/targets` - both should be "UP"
2. **Check collector exports metrics:** `curl http://localhost:8889/metrics`
3. **Wait for scrape interval:** Default is 10 seconds
4. **Send a new trace:** Old traces before collector restart won't persist

### Metrics not appearing in VictoriaMetrics

```bash
# Check Prometheus can reach VictoriaMetrics
docker exec prometheus curl http://victoriametrics:8428/health

# Check Prometheus remote_write config
docker exec prometheus cat /etc/prometheus/prometheus.yaml | grep -A5 remote_write
```

### Reset everything

```bash
# Stop containers and delete all data
docker compose down -v

# Start fresh
docker compose --profile full up -d
```

---

## Next Steps

### For New Users

1. ✅ You've started the stack
2. ✅ You've verified it works
3. **Next:** Integrate your application → See [Integration Patterns](integration-patterns.md)
4. **Then:** Configure for your needs → See [Configuration Reference](configuration-reference.md)

### For Production Deployments

1. **Choose your deployment profile** → [Deployment Profiles Guide](deployment-profiles.md)
2. **Deploy to servers** → [Deployment Methods](deployment-methods.md) (Docker Compose or Ansible)
3. **Secure your deployment** → [Security Guide](security.md)
4. **Configure for production** → [Production Guide](production-guide.md)

### For Advanced Scenarios

- **Multi-region setup** → [Integration Patterns](integration-patterns.md#multi-region-deployments)
- **Kubernetes integration** → [Integration Patterns](integration-patterns.md#kubernetes-integration)
- **High availability** → [Production Guide](production-guide.md#high-availability)

---

## Quick Reference

### Useful Commands

```bash
# Start the stack
docker compose --profile full up -d

# Check status
docker compose ps

# View logs
docker compose logs -f
docker compose logs -f otel-collector  # Specific service

# Stop the stack
docker compose down

# Clean up (including data volumes)
docker compose down -v
```

### Important URLs

- **Prometheus UI**: http://localhost:9090
- **VictoriaMetrics API**: http://localhost:8428
- **Collector Health**: http://localhost:13133/health/status
- **Collector Internal Metrics**: http://localhost:8888/metrics
- **Collector Spanmetrics**: http://localhost:8889/metrics

### Send Traces from Your Application

**Python:**

```python
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

provider = TracerProvider()
processor = BatchSpanProcessor(OTLPSpanExporter(endpoint="http://localhost:4317"))
provider.add_span_processor(processor)
trace.set_tracer_provider(provider)

tracer = trace.get_tracer(__name__)
with tracer.start_as_current_span("my-operation"):
    # Your code here
    pass
```

**JavaScript/TypeScript:**

```javascript
const { NodeTracerProvider } = require("@opentelemetry/sdk-trace-node");
const {
  OTLPTraceExporter,
} = require("@opentelemetry/exporter-trace-otlp-http");
const { BatchSpanProcessor } = require("@opentelemetry/sdk-trace-base");

const provider = new NodeTracerProvider();
const exporter = new OTLPTraceExporter({
  url: "http://localhost:4318/v1/traces",
});
provider.addSpanProcessor(new BatchSpanProcessor(exporter));
provider.register();
```

**More examples:** [Integration Patterns](integration-patterns.md)

---

[← Back to Advanced Setup](../ADVANCED_SETUP.md)
