# Getting Started Guide

[← Back to Advanced Setup](../ADVANCED_SETUP.md)

## What This Pipeline Does

This observability pipeline, when deployed with the [full deployment profile](guides/deployment-profiles.md#profile-1-full-complete-stack), solves a common problem: **how to monitor distributed applications using OpenTelemetry traces**. Instead of instrumenting your application twice (once for traces, once for metrics), this pipeline automatically derives metrics from traces and stores them for long-term analysis.

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
```

```bash
# 2. Verify OpenTelemetry Collector is ready
curl https://obs-dev.proveai.com:13133/health/status
# Expected: {"status":"Server available"}
```

```bash
# 3. Verify Prometheus can reach targets
# Note: Prometheus endpoints require authentication via Envoy
# For API Key auth (default):
curl -H "X-API-Key: placeholder_api_key" https://obs-dev.proveai.com:9090/api/v1/targets | jq
# Expected: All targets showing "up"

# For Basic Auth:
curl -u user:secretpassword https://obs-dev.proveai.com:9090/api/v1/targets | jq
```

```bash
# 4. Verify VictoriaMetrics is running
# Note: VictoriaMetrics endpoints require authentication via Envoy
# For API Key auth (default):
curl -H "X-API-Key: placeholder_api_key" https://obs-dev.proveai.com:8428/health
# Expected: "OK"

# For Basic Auth:
curl -u user:secretpassword https://obs-dev.proveai.com:8428/health
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

## Send a test trace:

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

**View the results** (wait 10-15 seconds for metrics to appear):

```bash
# Open Prometheus in your browser
open https://obs-dev.proveai.com:9090

# Run this query in the Prometheus UI
llm_traces_span_metrics_calls_total{service_name="otel-test"}
```
