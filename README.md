# Getting Started

## Prerequisites

- Docker and Docker Compose installed
- (Optional) otel-cli for testing

## Architecture

```
otel-cli → OTel Collector (OTLP receiver)
           ↓
       spanmetrics connector (converts spans to metrics)
           ↓
       Prometheus exporter (:8889)
           ↓
       Prometheus (scrapes every 5s)
```

## Starting the Application

This application runs primarily off of the docker compose. To start run:

```bash
cd docker-compose
docker compose up -d
```

This will start:

- **OTel Collector** on ports 4317 (gRPC), 4318 (HTTP), 8888 (internal metrics), 8889 (Prometheus exporter)
- **Prometheus** on port 9090
- **Grafana** on port 3100 (admin/admin)

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
make logs-grafana      # View logs from Grafana
make logs-postgres     # View logs from PostgreSQL
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

## Send a Test Span using Otel CLI

```bash
otel-cli span \
  --service "otel-test" \
  --name "demo-span" \
  --endpoint http://localhost:4318/v1/traces \
  --protocol http/protobuf \
  --attrs "env=dev,component=demo" \
  --start "$(date -Iseconds)" \
  --end "$(date -Iseconds)"
```

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

Visit `http://localhost:9090/targets`

You should see two targets both showing as **UP**:

- `otel-collector` (otel-collector:8889)
- `otel-collector-internal` (otel-collector:8888)

### 5. Query Metrics in Prometheus

Visit `http://localhost:9090`

Run a query:

```promql
llm_traces_span_metrics_calls_total{}
```

Expected Output:

```
llm_traces_span_metrics_calls_total{component="demo", env="dev", exported_job="otel-test", instance="otel-collector:8889", job="otel-collector", otel_scope_name="spanmetricsconnector", service_name="otel-test", span_kind="SPAN_KIND_CLIENT", span_name="demo-span", status_code="STATUS_CODE_UNSET"}
```

### 6. Query Metrics in Grafana

Visit `http://localhost:3100

Click on Dashboards > + Create Dashboard > Add Visualization > Prometheus

Query for metric `llm_traces_span_metrics_calls_total`

You should see data in the panel

Save Dashboard (optional)

## Troubleshooting

### Prometheus shows empty results

- Check `http://localhost:9090/targets` - both targets should be UP
- Verify metrics exist at `http://localhost:8889/metrics`
- Wait 5-10 seconds after sending a span for Prometheus to scrape
- Ensure you're using the `otel/opentelemetry-collector-contrib` image (not the base image)

### Container fails to start

Check logs for errors:

```bash
docker compose logs otel-collector
docker compose logs prometheus
```

### Clear all data and restart

```bash
docker compose down -v
docker compose up -d
```

### Metrics not appearing after collector restart

Send a new span after restarting the collector - old spans won't persist across restarts unless you configure persistent storage.
