# Architecture

[← Back to Advanced Setup](../ADVANCED_SETUP.md)

This document describes the architecture of the observability pipeline, which transforms OpenTelemetry traces into metrics for long-term storage and analysis. The system consists of four main components: **Envoy Proxy** (authentication gateway), **OpenTelemetry Collector** (converts traces to RED metrics via spanmetrics), **Prometheus** (scrapes and queries metrics), and **VictoriaMetrics** (long-term storage with 10x compression). The pipeline supports multiple deployment profiles for integration with existing infrastructure, and includes comprehensive testing procedures and design rationale.

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
- `9901` - Envoy user interface (localhost only)

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

**Access the UI:** `https://obs-dev.proveai.com:9090` (requires authentication via Envoy)

#### VictoriaMetrics

**What it does:** Stores metrics long-term with efficient compression.

- **Image**: `victoriametrics/victoria-metrics:latest`
- **Primary Role**: Long-term metric storage
- **Port**: `8428` (accessed via Envoy)
- **Retention**: 12 months (configurable via `-retentionPeriod` flag)
- **API**: Prometheus-compatible query API

**Access the API:** `https://obs-dev.proveai.com:8428` (requires authentication via Envoy)

**Why use it?** VictoriaMetrics uses ~10x less disk space than Prometheus for the same data.

### Network Architecture

All services run on a Docker bridge network named `observability`:

```
External Applications
     ↓
     ↓ (send traces to obs-dev.proveai.com:4317 or :4318)
     ↓
┌─────────────────────────────────────────┐
│  observability Docker network           │
│                                         │
│  Envoy Proxy (ports: 4317, 4318, 9090, 8428)
│     │                                   │
│     ├─→ otel-collector (internal)       │
│     │                                   │
│     ├─→ prometheus (internal)           │
│     │    │                              │
│     │    ├─→ otel-collector:8889 (scrape)
│     │    │                              │
│     │    └─→ victoriametrics:8428 (remote_write)
│     │                                   │
│     └─→ victoriametrics (internal)      │
│                                         │
└─────────────────────────────────────────┘
```

**Important:**

- External applications send traces to `obs-dev.proveai.com:4317/4318`, which routes through Envoy for authentication before reaching the collector.
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
curl https://obs-dev.proveai.com:13133/health/status

# Expected: {"status":"Server available","upSince":"..."}
```

### Step 3: Verify Prometheus Targets

```bash
# Check targets via API (requires authentication via Envoy)
curl -H "X-API-Key: placeholder_api_key" https://obs-dev.proveai.com:9090/api/v1/targets | jq '.data.activeTargets[] | {job: .labels.job, health: .health}'

# Or open in browser (authentication required)
open https://obs-dev.proveai.com:9090/targets
```

**Note:** For Basic Auth examples, see [Prometheus Commands](reference.md#prometheus-commands).

**Expected:** Both targets showing `health: "up"`:

- `otel-collector` (port 8889)
- `otel-collector-internal` (port 8888)

### Step 4: Send a Test Trace

```bash
# Note: Requires authentication via Envoy
# For API Key auth (default):
otel-cli span \
  --service "otel-test" \
  --name "demo-span" \
  --endpoint https://obs-dev.proveai.com:4318/v1/traces \
  --protocol http/protobuf \
  --attrs "env=dev,component=demo" \
  --start "$(date -Iseconds)" \
  --end "$(date -Iseconds)" \
  --otlp-headers "X-API-Key=placeholder_api_key"

# For Basic Auth:
  otel-cli span \
  --service "otel-test" \
  --name "demo-span" \
  --endpoint https://obs-dev.proveai.com:4318/v1/traces \
  --protocol http/protobuf \
  --attrs "env=dev,component=demo" \
  --start "$(date -Iseconds)" \
  --end "$(date -Iseconds)" \
  --otlp-headers "Authorization=Basic $(echo -n 'user:secretpassword' | base64)"
```

### Step 5: Verify Metrics Appear

Wait 15 seconds, then query Prometheus:

```bash
# Via API (requires authentication via Envoy)
# For API Key auth (default):
curl -H "X-API-Key: placeholder_api_key" 'https://obs-dev.proveai.com:9090/api/v1/query?query=llm_traces_span_metrics_calls_total' | jq

# For Basic Auth:
curl -u user:secretpassword 'https://obs-dev.proveai.com:9090/api/v1/query?query=llm_traces_span_metrics_calls_total' | jq

# Or open Prometheus UI (authentication required)
open https://obs-dev.proveai.com:9090
# Then run: llm_traces_span_metrics_calls_total{service_name="my-app"}
```

### Step 6: Verify VictoriaMetrics

```bash
# Health check (requires authentication via Envoy)
# For API Key auth (default):
curl -H "X-API-Key: placeholder_api_key" https://obs-dev.proveai.com:8428/health
# Expected: OK

# For Basic Auth:
curl -u user:secretpassword https://obs-dev.proveai.com:8428/health

```

```bash
# Query metrics (same as Prometheus API, requires authentication)
# For API Key auth (default):
curl -H "X-API-Key: placeholder_api_key" 'https://obs-dev.proveai.com:8428/api/v1/query?query=up' | jq

# For Basic Auth:
curl -u user:secretpassword 'https://obs-dev.proveai.com:8428/api/v1/query?query=up' | jq
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

- **Prometheus UI**: https://obs-dev.proveai.com:9090 (requires authentication via Envoy)
- **VictoriaMetrics API**: https://obs-dev.proveai.com:8428 (requires authentication via Envoy)
- **Collector Health**: https://obs-dev.proveai.com:13133/health/status (no authentication required)
- **Collector Internal Metrics**: https://obs-dev.proveai.com:8888/metrics (no authentication required)
- **Collector Spanmetrics**: https://obs-dev.proveai.com:8889/metrics (internal only, no authentication required)

---

[← Back to Advanced Setup](../ADVANCED_SETUP.md)
