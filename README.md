# Getting Started

## Prerequisites

-   Docker and Docker Compose installed
-   (Optional) otel-cli for testing

## Architecture

```
Client → Envoy Proxy (API Key Auth) → OTel Collector (OTLP receiver)
                                           ↓
                                       spanmetrics connector (converts spans to metrics)
                                           ↓
                                       Prometheus exporter (:8889)
                                           ↓
                                       Prometheus (scrapes every 5s)
                                           ↓
                                       VictoriaMetrics (long-term storage, 12 months retention)
```

**Note:** All external traffic flows through Envoy proxy, which provides centralized API key authentication before forwarding requests to backend services.

## Starting the Application

This application runs primarily off of the docker compose. To start run:

```bash
cd docker-compose
docker compose --profile full up -d
```

This will start:

-   **Envoy Proxy** on ports 4317 (gRPC), 4318 (HTTP), 9090 (Prometheus), 8428 (VictoriaMetrics) - provides API key authentication
-   **OTel Collector** on ports 8888 (internal metrics), 8889 (Prometheus exporter) - accessible via Envoy only
-   **Prometheus** - accessible via Envoy only (port 9090)
-   **VictoriaMetrics** - accessible via Envoy only (port 8428, long-term storage with 12 months retention)

### Docker Compose Profiles

If you already have portions of the observability stack set up (Prometheus, OpenTelemetry Collector, or VictoriaMetrics), you can use Docker Compose profiles to run only the services you need.

**Important:** All services in `docker-compose.yaml` are assigned to profiles, so you **must** specify a profile when starting the stack.

Available profiles:

-   `full` - Runs the complete stack (Collector, Prometheus, VictoriaMetrics)
-   `no-prometheus` - Use when you already have Prometheus (includes Collector and VictoriaMetrics)
-   `no-collector` - Use when you already have an OpenTelemetry Collector (includes Prometheus and VictoriaMetrics)
-   `no-vm` - Use when you already have VictoriaMetrics (includes Collector and Prometheus)
-   `vm-only` - Use when you only want VictoriaMetrics (no Collector or Prometheus)
-   `prom-only` - Use when you only want Prometheus (no Collector or VictoriaMetrics)

For detailed information on each profile and required customer configuration, see [PROFILES.md](docker-compose/PROFILES.md).

**Example usage:**

```bash
# Run only collector and VictoriaMetrics (you have Prometheus already)
docker compose --profile no-prometheus up -d

# Run only prometheus and VictoriaMetrics (you have Collector already)
docker compose --profile no-collector up -d

# Run only collector and prometheus (you have VictoriaMetrics already)
docker compose --profile no-vm up -d

# Run only VictoriaMetrics (you have your own Prometheus and Collector)
docker compose --profile vm-only up -d

# Run only Prometheus (you have your own Collector and storage)
docker compose --profile prom-only up -d
```

## Using the Makefile

This project includes a Makefile with convenient commands for managing the observability stack. Instead of manually navigating to the docker-compose directory and running docker compose commands, you can use these shortcuts:

### Basic Commands

```bash
make up          # Start the observability stack
make down        # Stop the observability stack
make restart     # Restart the stack
make status      # Check status of containers
make clean       # Clean up containers and volumes
```

### Log Commands

```bash
make logs              # View logs from all services
make logs-otel         # View logs from OTel Collector
make logs-prometheus   # View logs from Prometheus
make logs-vm           # View logs from VictoriaMetrics
```

### Additional Commands

```bash
make build      # Build custom images (if needed)
make help       # Show all available commands
```

## Testing Locally without LLM via Otel CLI

### Mac OS Installation

```bash
brew install equinix-labs/otel-cli/otel-cli
```

### Linux Installation

```bash
curl -L https://github.com/equinix-labs/otel-cli/releases/latest/download/otel-cli-linux-amd64 -o /usr/local/bin/otel-cli
chmod +x /usr/local/bin/otel-cli
```

### Windows Installation

Download from the [Github Releases Page](https://github.com/equinix-labs/otel-cli/releases)

## API Key Authentication

All external requests to the observability services must include a valid API key in the `X-API-Key` header. The Envoy proxy validates API keys before forwarding requests to backend services.

### Configuring API Keys

API keys are configured via the `ENVOY_API_KEYS` environment variable, which is read from the `.env` file in the project root. The Envoy configuration is generated dynamically from a template at container startup.

**Default behavior:**
- If `ENVOY_API_KEYS` is not set, a placeholder key (`placeholder_api_key`) is used
- For production deployments, you **must** set `ENVOY_API_KEYS` with your actual API keys

### Setting API Keys

1. Create or edit the `.env` file in the project root (if it doesn't exist, you can use `.env.example` as a template)
2. Add your API keys as a comma-separated list:
   ```bash
   ENVOY_API_KEYS=placeholder_api_key
   ```
3. Restart the Envoy service to apply changes:
   ```bash
   docker compose restart envoy
   ```

## Send a Test Span using Otel CLI

All requests must include the `X-API-Key` header. Example:

```bash
otel-cli span \
  --service "otel-test" \
  --name "demo-span" \
  --endpoint http://localhost:4318/v1/traces \
  --protocol http/protobuf \
  --attrs "env=dev,component=demo" \
  --start "$(date -Iseconds)" \
  --end "$(date -Iseconds)" \
  --headers "X-API-Key: placeholder_api_key"
```

Or using curl:

```bash
curl -X POST http://localhost:4318/v1/traces \
  -H "Content-Type: application/x-protobuf" \
  -H "X-API-Key: placeholder_api_key" \
  --data-binary @trace.pb
```

**Note:** If you send an empty payload like `{"resourceSpans":[]}`, you'll receive `{"partialSuccess":{}}` as a response. This is expected - it means the request was accepted but contained no spans to process. To test with actual data, use `otel-cli` or send a properly formatted trace payload.

## Testing Endpoints with curl

### OTel HTTP Receiver (port 4318)

**Send a test trace (JSON format):**
```bash
curl -X POST http://localhost:4318/v1/traces \
  -H "Content-Type: application/json" \
  -H "X-API-Key: placeholder_api_key" \
  -d '{"resourceSpans":[]}'
```

**Note:** The above command sends an empty trace array. For a valid trace, use `otel-cli` or send a properly formatted OTLP trace payload.

**Health check:**
```bash
curl -H "X-API-Key: placeholder_api_key" http://localhost:4318/
```

### Prometheus (port 9090)

**Check targets:**
```bash
curl -H "X-API-Key: placeholder_api_key" http://localhost:9090/targets
```

**Query metrics (instant query):**
```bash
curl -H "X-API-Key: placeholder_api_key" "http://localhost:9090/api/v1/query?query=up"
```

**Query specific metric:**
```bash
curl -H "X-API-Key: placeholder_api_key" "http://localhost:9090/api/v1/query?query=llm_traces_span_metrics_calls_total"
```

**Range query:**
```bash
curl -H "X-API-Key: placeholder_api_key" "http://localhost:9090/api/v1/query_range?query=up&start=$(date -u +%s -d '1 hour ago')&end=$(date -u +%s)&step=15s"
```

**Access Prometheus UI:**
```bash
# Open in browser: http://localhost:9090
# Or use curl:
curl -H "X-API-Key: placeholder_api_key" http://localhost:9090/
```

### VictoriaMetrics (port 8428)

**Health check:**
```bash
curl -H "X-API-Key: placeholder_api_key" http://localhost:8428/health
```

**Query metrics (instant query):**
```bash
curl -H "X-API-Key: placeholder_api_key" "http://localhost:8428/api/v1/query?query=up"
```

**Query specific metric:**
```bash
curl -H "X-API-Key: placeholder_api_key" "http://localhost:8428/api/v1/query?query=llm_traces_span_metrics_calls_total"
```

**Range query:**
```bash
curl -H "X-API-Key: placeholder_api_key" "http://localhost:8428/api/v1/query_range?query=up&start=$(date -u +%s -d '1 hour ago')&end=$(date -u +%s)&step=15s"
```

**Note:** Replace `placeholder_api_key` with your actual API key from the `ENVOY_API_KEYS` environment variable. If `ENVOY_API_KEYS` is not set, `placeholder_api_key` is used as the default.

## Verification Steps

### 1. Verify Collector is Receiving Spans

Run `docker compose logs -f otel-collector`

Expected Output:

```
otel-collector  | Span #0
otel-collector  |     Trace ID       : 9b7266251b277d8d9f131eaaa4073135
otel-collector  |     Parent ID      :
otel-collector  |     ID             : 00368ad1d1601f42
otel-collector  |     Name           : demo-span
otel-collector  |     Kind           : Client
otel-collector  |     Start time     : 2025-10-28 20:38:19 +0000 UTC
otel-collector  |     End time       : 2025-10-28 20:38:19 +0000 UTC
otel-collector  |     Status code    : Unset
otel-collector  |     Status message :
otel-collector  | Attributes:
otel-collector  |      -> env: Str(dev)
otel-collector  |      -> component: Str(demo)
otel-collector  | 	{"kind": "exporter", "data_type": "traces", "name": "logging"}
```

### 2. Verify Collector Internal Metrics

Visit `http://localhost:8888/metrics` and search for:

```
otelcol_receiver_accepted_spans
```

This counter should increment each time you send a span.

### 3. Verify Span Metrics in Prometheus Exporter

Visit `http://localhost:8889/metrics`

Search for the test metric `llm_traces_span_metrics_calls_total`

Expected Output:

```
# TYPE llm_traces_span_metrics_calls_total counter
llm_traces_span_metrics_calls_total{component="demo",env="dev",job="otel-test",otel_scope_name="spanmetricsconnector",otel_scope_schema_url="",otel_scope_version="",service_name="otel-test",span_kind="SPAN_KIND_CLIENT",span_name="demo-span",status_code="STATUS_CODE_UNSET"} 1
```

### 4. Verify Prometheus is Scraping

Visit `http://localhost:9090/targets` (include `X-API-Key: placeholder_api_key` header in your browser request, or use curl):

```bash
curl -H "X-API-Key: placeholder_api_key" http://localhost:9090/targets
```

You should see two targets both showing as **UP**:

-   `otel-collector` (otel-collector:8889)
-   `otel-collector-internal` (otel-collector:8888)

### 5. Query Metrics in Prometheus

Visit `http://localhost:9090` (include `X-API-Key: placeholder_api_key` header) or use the API:

```bash
curl -H "X-API-Key: placeholder_api_key" "http://localhost:9090/api/v1/query?query=llm_traces_span_metrics_calls_total"
```

Run a query:

```promql
llm_traces_span_metrics_calls_total{}
```

Expected Output:

```
llm_traces_span_metrics_calls_total{component="demo", env="dev", exported_job="otel-test", instance="otel-collector:8889", job="otel-collector", otel_scope_name="spanmetricsconnector", service_name="otel-test", span_kind="SPAN_KIND_CLIENT", span_name="demo-span", status_code="STATUS_CODE_UNSET"}
```

### 6. Verify VictoriaMetrics is Receiving Metrics

Verify VictoriaMetrics is running (include API key header):

```bash
curl -H "X-API-Key: placeholder_api_key" http://localhost:8428/health
```

Prometheus automatically remote_writes all metrics to VictoriaMetrics for long-term storage (12 months retention).

You can query metrics directly from VictoriaMetrics using its Prometheus-compatible API:

```bash
curl -H "X-API-Key: placeholder_api_key" "http://localhost:8428/api/v1/query?query=llm_traces_span_metrics_calls_total"
```

## AWS NLB Integration

This stack is designed to work behind AWS Network Load Balancer (NLB). The Envoy proxy handles all external traffic and provides API key authentication.

### NLB Configuration

-   **Target Groups**: NLB target groups should point to Envoy's exposed ports (4317, 4318, 9090, 8428) on EC2 instances
-   **Health Checks**: NLB performs TCP health checks directly on service ports (e.g., port 4318). Envoy accepts TCP connections on these ports, satisfying NLB health checks
-   **Security Groups**: Ensure EC2 security groups allow traffic from NLB to Envoy ports
-   **No Breaking Changes**: Existing NLB configuration remains the same - same ports, same health check settings. Traffic now flows through Envoy instead of directly to services

### Deployment Notes

After deploying Envoy, verify NLB health checks pass. Envoy will accept TCP connections on the configured ports, allowing NLB TCP health checks to succeed.

## Troubleshooting

### Authentication Errors

If you receive `401 Unauthorized` responses:

-   Ensure you're including the `X-API-Key` header in all requests
-   Verify the API key matches one of the valid keys configured via `ENVOY_API_KEYS` environment variable
-   Check Envoy logs: `docker compose logs envoy`

### Understanding OTLP Responses

**`{"partialSuccess":{}}` response:**
- This is a **successful** response (HTTP 200 OK)
- It indicates the request was accepted but contained no spans to process (e.g., empty `resourceSpans` array)
- This is expected behavior when sending empty or invalid trace payloads
- To verify authentication is working, check that you receive this response instead of `401 Unauthorized`

**Empty trace payload example:**
```bash
curl -X POST http://localhost:4318/v1/traces \
  -H "Content-Type: application/json" \
  -H "X-API-Key: placeholder_api_key" \
  -d '{"resourceSpans":[]}'
# Response: {"partialSuccess":{}} (HTTP 200 OK)
```

### Prometheus shows empty results

-   Check `http://localhost:9090/targets` (with API key header) - both targets should be UP
-   Verify metrics exist at `http://localhost:8889/metrics` (internal, no auth required)
-   Wait 5-10 seconds after sending a span for Prometheus to scrape
-   Ensure you're using the `otel/opentelemetry-collector-contrib` image (not the base image)

### Container fails to start

Check logs for errors:

```bash
docker compose logs envoy
docker compose logs otel-collector
docker compose logs prometheus
```

### Envoy configuration errors

If Envoy fails to start, validate the configuration:

```bash
docker compose exec envoy envoy --config-path /etc/envoy/envoy.yaml --mode validate
```

### Clear all data and restart

```bash
cd docker-compose
docker compose --profile full down -v
docker compose --profile full up -d
```

### Metrics not appearing after collector restart

Send a new span after restarting the collector - old spans won't persist across restarts unless you configure persistent storage.
