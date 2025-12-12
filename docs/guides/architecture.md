# Architecture & Getting Started Guide

[← Back to Advanced Setup](../ADVANCED_SETUP.md)

## What This Pipeline Does

This observability pipeline, when deployed with the [full deployment profile](deployment-profiles.md#profile-1-full-complete-stack), solves a common problem: **how to monitor distributed applications using OpenTelemetry traces**. Instead of instrumenting your application twice (once for traces, once for metrics), this pipeline automatically derives metrics from traces and stores them for long-term analysis.

**At a Glance:**

- Your application sends traces (using OpenTelemetry)
- The pipeline converts those traces into useful metrics (request rate, errors, latency)
- You can query and visualize these metrics using the ProveAI client
- All metrics are stored for 12 months with efficient compression

## Quick Start

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
# Note: Prometheus endpoints require authentication via Envoy
# For API Key auth (default):
curl -H "X-API-Key: placeholder_api_key" http://localhost:9090/api/v1/targets | jq
# For Basic Auth:
# curl -u admin:secretpassword http://localhost:9090/api/v1/targets | jq
# Expected: All targets showing "up"

# 4. Verify VictoriaMetrics is running
# Note: VictoriaMetrics endpoints require authentication via Envoy
# For API Key auth (default):
curl -H "X-API-Key: placeholder_api_key" http://localhost:8428/health
# For Basic Auth:
# curl -u admin:secretpassword http://localhost:8428/health
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

<a id="send-test-trace-command"></a>

```bash
# Note: Requires authentication via Envoy
# For API Key auth (default):
otel-cli span \
  --service "otel-test" \
  --name "demo-span" \
  --endpoint http://localhost:4318/v1/traces \
  --protocol http/protobuf \
  --attrs "env=dev,component=demo" \
  --start "$(date -Iseconds)" \
  --end "$(date -Iseconds)" \
  --otlp-headers "X-API-Key=placeholder_api_key"

# For Basic Auth:
# otel-cli span \
# --service "otel-test" \
# --name "demo-span" \
# --endpoint http://localhost:4318/v1/traces \
# --protocol http/protobuf \
# --attrs "env=dev,component=demo" \
# --start "$(date -Iseconds)" \
# --end "$(date -Iseconds)" \
# --otlp-headers "Authorization=Basic $(echo -n 'admin:secretpassword' | base64)"
```

**View the results** (wait 10-15 seconds for metrics to appear):

```bash
# Open Prometheus in your browser
open http://localhost:9090

# Run this query in the Prometheus UI
llm_traces_span_metrics_calls_total{service_name="otel-test"}
```

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
│  Envoy Proxy                   │
│  ┌──────────────────────────┐  │
│  │ • API Key Authentication │  │
│  │ • Centralized auth       │  │
│  └──────────────────────────┘  │
└────────────────────────────────┘
     ↓ (forwards authenticated requests)
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

#### Envoy Proxy

**What it does:** Centralized authentication gateway for all external requests.

- **Image**: `observability-pipeline-envoy:latest` (custom build)
- **Primary Role**: Authenticate requests before forwarding to backend services
- **Key Feature**: Supports API Key and Basic Auth methods

**Ports:**

- `4317` - OTLP gRPC receiver (proxied to collector)
- `4318` - OTLP HTTP receiver (proxied to collector)
- `9090` - Prometheus UI and API (proxied)
- `8428` - VictoriaMetrics API (proxied)
- `9901` - Envoy admin interface (localhost only)

**Configuration:** Environment variables in `.env` file (see [Security Guide](security.md))

#### OpenTelemetry Collector (otel-collector)

**What it does:** Receives authenticated traces from Envoy and converts them to metrics.

- **Image**: `otel/opentelemetry-collector-contrib:0.138.0`
- **Primary Role**: Receive traces, convert to metrics, export to Prometheus
- **Key Feature**: Spanmetrics connector transforms traces into [RED metrics](#red-metrics)

**Ports:**

- `4317` - OTLP gRPC receiver (internal, accessed via Envoy)
- `4318` - OTLP HTTP receiver (internal, accessed via Envoy)
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
- **Port**: `9090` (Web UI and API, accessed via Envoy)
- **Scrape Interval**: 10 seconds (configurable in `prometheus.yaml`)
- **Storage**: Local TSDB + remote write to VictoriaMetrics

**Configuration file:** `docker-compose/prometheus.yaml`

**Access the UI:** `http://localhost:9090` (requires authentication via Envoy)

#### VictoriaMetrics

**What it does:** Stores metrics long-term with efficient compression.

- **Image**: `victoriametrics/victoria-metrics:latest`
- **Primary Role**: Long-term metric storage
- **Port**: `8428` (accessed via Envoy)
- **Retention**: 12 months (configurable via `-retentionPeriod` flag)
- **API**: Prometheus-compatible query API

**Access the API:** `http://localhost:8428` (requires authentication via Envoy)

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
│  Envoy Proxy (ports: 4317, 4318, 9090, 8428)
│     │                                    │
│     ├─→ otel-collector (internal)       │
│     │                                    │
│     ├─→ prometheus (internal)           │
│     │    │                               │
│     │    ├─→ otel-collector:8889 (scrape)
│     │    │                               │
│     │    └─→ victoriametrics:8428 (remote_write)
│     │                                    │
│     └─→ victoriametrics (internal)      │
│                                         │
└─────────────────────────────────────────┘
```

**Important:**

- External applications send traces to `localhost:4317/4318`, which routes through Envoy for authentication before reaching the collector.
- Services inside Docker communicate directly using service names (e.g., `otel-collector:4317`) without authentication.

---

## Integration Options

### Option 1: Full Stack (Recommended for New Setups)

Deploy a complete, self-contained observability stack with no external dependencies. Best for greenfield projects or when starting from scratch.

**→ [View full stack setup guide](deployment-profiles.md#profile-1-full-complete-stack)**

**Next steps:** [Skip to Testing & Verification](#testing--verification)

---

### Option 2: I Already Have Prometheus

Add trace-to-metrics capability and long-term storage to your existing Prometheus deployment. Requires configuring your Prometheus to scrape the collector and write to VictoriaMetrics.

**→ [View integration with existing Prometheus](deployment-profiles.md#profile-2-no-prometheus-integrate-with-existing-prometheus)**

---

### Option 3: I Already Have VictoriaMetrics

Deploy the collector and Prometheus while integrating with your existing VictoriaMetrics instance for long-term storage.

**→ [View integration with existing VictoriaMetrics](deployment-profiles.md#profile-3-no-vm-integrate-with-existing-victoriametrics)**

---

### Option 4: I Already Have an OpenTelemetry Collector

Deploy Prometheus and VictoriaMetrics to complement your existing collector deployment.

**→ [View integration with existing OpenTelemetry Collector](deployment-profiles.md#profile-4-no-collector-integrate-with-existing-collector)**

---

### Option 5: VictoriaMetrics Only

Deploy only VictoriaMetrics as a centralized long-term storage backend for multiple Prometheus instances.

**→ [View VictoriaMetrics standalone setup](deployment-profiles.md#profile-5-vm-only-victoriametrics-standalone)**

---

### Option 6: Prometheus Only

Deploy Prometheus standalone for scraping and querying, optionally with external storage backends like Thanos, Cortex, or M3DB.

**→ [View Prometheus standalone setup](deployment-profiles.md#profile-6-prom-only-prometheus-standalone)**

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
# Check targets via API (requires authentication via Envoy)
curl -H "X-API-Key: placeholder_api_key" http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'

# Or open in browser (authentication required)
open http://localhost:9090/targets
```

**Expected:** Both targets showing `health: "up"`:

- `otel-collector` (port 8889)
- `otel-collector-internal` (port 8888)

### Step 4: Send a Test Trace

See the example in [Send Your First Trace](#send-test-trace-command) above.

### Step 5: Verify Metrics Appear

Wait 15 seconds, then query Prometheus:

```bash
# Via API (requires authentication via Envoy)
# For API Key auth (default):
curl -H "X-API-Key: placeholder_api_key" 'http://localhost:9090/api/v1/query?query=llm_traces_span_metrics_calls_total' | jq
# For Basic Auth:
# curl -u admin:secretpassword 'http://localhost:9090/api/v1/query?query=llm_traces_span_metrics_calls_total' | jq

# Or open Prometheus UI (authentication required)
open http://localhost:9090
# Then run: llm_traces_span_metrics_calls_total{service_name="my-app"}
```

### Step 6: Verify VictoriaMetrics

```bash
# Health check (requires authentication via Envoy)
# For API Key auth (default):
curl -H "X-API-Key: placeholder_api_key" http://localhost:8428/health
# For Basic Auth:
# curl -u admin:secretpassword http://localhost:8428/health
# Expected: OK

# Query metrics (same as Prometheus API, requires authentication)
curl -H "X-API-Key: placeholder_api_key" 'http://localhost:8428/api/v1/query?query=up' | jq
```

---

## Key Design Decisions

### Why Spanmetrics?

<a id="red-metrics"></a>

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
- **Service Discovery**: Built-in for AWS, Consul, DNS, and more
- **Recording Rules**: Pre-compute expensive queries
- **Buffering**: If VictoriaMetrics goes down, Prometheus retains recent data

**Benefit:** Best of both worlds - Prometheus for flexibility, VictoriaMetrics for storage.

---

## Next Steps

### For New Users

1. ✅ You've started the stack
2. ✅ You've verified it works
3. **Next:** Integrate your application → See [Hybrid Cloud Integration](hybrid-cloud-integration.md)
4. **Then:** Configure for your needs → See [Configuration Reference](configuration-reference.md)

### For Production Deployments

1. **Choose your deployment profile** → [Deployment Profiles Guide](deployment-profiles.md)
2. **Deploy to servers** → [Deployment Guide](deployment-guide.md) (Docker Compose)
3. **Secure your deployment** → [Security Guide](security.md)
4. **Configure for production** → [Production Guide](production-guide.md)

### For Advanced Scenarios

- **Hybrid cloud integration** → [Hybrid Cloud Integration](hybrid-cloud-integration.md) - Connect on-premises infrastructure to cloud observability

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

- **Prometheus UI**: http://localhost:9090 (requires authentication via Envoy)
- **VictoriaMetrics API**: http://localhost:8428 (requires authentication via Envoy)
- **Collector Health**: http://localhost:13133/health/status (no authentication required)
- **Collector Internal Metrics**: http://localhost:8888/metrics (no authentication required)
- **Collector Spanmetrics**: http://localhost:8889/metrics (internal only, no authentication required)

### Send Traces from Your Application

**Python:**

```python
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor

provider = TracerProvider()
# Endpoint goes through Envoy proxy (requires authentication)
# For API Key auth (default):
processor = BatchSpanProcessor(OTLPSpanExporter(
    endpoint="http://localhost:4317",
    headers={"X-API-Key": "your-api-key"}  # Required for Envoy auth
))
# For Basic Auth:
# import base64
# auth_header = base64.b64encode(b'admin:secretpassword').decode('utf-8')
# processor = BatchSpanProcessor(OTLPSpanExporter(
#     endpoint="http://localhost:4317",
#     headers={"Authorization": f"Basic {auth_header}"}  # Required for Envoy auth
# ))
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
// Endpoint goes through Envoy proxy (requires authentication)
// For API Key auth (default):
const exporter = new OTLPTraceExporter({
  url: "http://localhost:4318/v1/traces",
  headers: {
    "X-API-Key": "your-api-key", // Required for Envoy auth
  },
});
// For Basic Auth:
// const auth = Buffer.from('admin:secretpassword').toString('base64');
// const exporter = new OTLPTraceExporter({
//   url: "http://localhost:4318/v1/traces",
//   headers: {
//     "Authorization": `Basic ${auth}`, // Required for Envoy auth
//   },
// });
provider.addSpanProcessor(new BatchSpanProcessor(exporter));
provider.register();
```

**Hybrid cloud setup:** [Hybrid Cloud Integration](hybrid-cloud-integration.md)

---

[← Back to Advanced Setup](../ADVANCED_SETUP.md)
