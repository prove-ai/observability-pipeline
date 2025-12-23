# Getting Started

[← Back to Advanced Setup](../ADVANCED_SETUP.md)

## What This Pipeline Does

This observability pipeline, when deployed with the [full deployment profile](deployment-profiles.md#profile-1-full-complete-stack), solves a common problem: **how to monitor distributed applications using OpenTelemetry traces**. Instead of instrumenting your application twice (once for traces, once for metrics), this pipeline automatically derives metrics from traces and stores them for long-term analysis.

**At a Glance:**

- Your application sends traces (using OpenTelemetry)
- The pipeline converts those traces into useful metrics (request rate, errors, latency)
- You can query and visualize these metrics in any Prometheus-compatible tool
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

### Authentication

By default, the pipeline uses **API Key authentication** with placeholder credentials for quick testing. All external requests to observability services (OTLP receivers, Prometheus, VictoriaMetrics) are authenticated via the Envoy proxy.

**Default credentials for testing:**

- API Key: `placeholder_api_key` (header: `X-API-Key: placeholder_api_key`)
- Basic Auth: `user:secretpassword` (if switching to Basic Auth mode)

**⚠️ For production:** Change these credentials before deployment. See the [detailed authentication guide](security.md#authentication) for configuration options, security best practices, and how to switch authentication methods.

### Start the Full Stack (Greenfield Setup)

If you're starting from scratch with no existing monitoring infrastructure:

```bash
# Clone or navigate to the repository
cd /path/to/observability-pipeline

# Start everything with one command
cd docker-compose
docker compose --profile full up -d --build
```

**That's it!** You now have a complete observability stack running:

```
✓ OpenTelemetry Collector (receiving traces)
✓ Prometheus (scraping and querying metrics)
✓ VictoriaMetrics (storing metrics for 12 months)
```

### Verify It's Working

> **Note**: `obs-dev.proveai.com` should be used for internal testing

```bash
# 1. Check all services are healthy
docker compose ps
```

```bash
# 2. Verify OpenTelemetry Collector is ready
curl http://localhost:13133/health/status
# Expected: {"status":"Server available"}
```

```bash
# 3. Verify Prometheus can reach targets
# Note: Prometheus authentication depends on your ENVOY_AUTH_METHOD setting
# For API Key auth (default):
curl -H "X-API-Key: placeholder_api_key" http://localhost:9090/api/v1/targets | jq
# Expected: All targets showing "up"

# For Basic Auth (uses Prometheus native authentication):
curl -u prometheus_user:prometheus_password http://localhost:9090/api/v1/targets | jq
# Note: Use credentials from prometheus-web-config.yaml, not ENVOY_BASIC_AUTH_CREDENTIALS
```

```bash
# 4. Verify VictoriaMetrics is running
# Note: VictoriaMetrics endpoints are authenticated via Envoy
# For API Key auth (default):
curl -H "X-API-Key: placeholder_api_key" http://localhost:8428/health
# Expected: "OK"

# For Basic Auth (uses Envoy credentials):
curl -u user:secretpassword http://localhost:8428/health
# Note: Use credentials from ENVOY_BASIC_AUTH_CREDENTIALS in .env file
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
# Note: OTLP receivers are authenticated via Envoy
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

# For Basic Auth (uses Envoy credentials from ENVOY_BASIC_AUTH_CREDENTIALS):
otel-cli span \
  --service "otel-test" \
  --name "demo-span" \
  --endpoint http://localhost:4318/v1/traces \
  --protocol http/protobuf \
  --attrs "env=dev,component=demo" \
  --start "$(date -Iseconds)" \
  --end "$(date -Iseconds)" \
  --otlp-headers "Authorization=Basic $(echo -n 'user:secretpassword' | base64)"
```

**View the results** (wait 10-15 seconds for metrics to appear):

```bash
# Open Prometheus in your browser
open http://obs-dev.proveai.com:9090

# Run this query in the Prometheus UI
llm_traces_span_metrics_calls_total{service_name="otel-test"}
```

---

## Monitor LLM Inference

Monitor your LLM inference servers to track metrics like latency, throughput, and token generation. Choose the framework that matches your deployment:

### Option 1: vLLM

**Prerequisites:** NVIDIA GPU with Compute Capability ≥ 7.0, NVIDIA Container Toolkit

> **Note:** This guide uses vLLM v0.11.2 (latest stable as of December 2025). Check the [vLLM releases page](https://github.com/vllm-project/vllm/releases) for newer versions. If upgrading from v0.6.x or earlier, review the [changelog](https://github.com/vllm-project/vllm/releases) for breaking changes.

**Quick Setup:**

1. **Create configuration** (`.env` file):

```bash
VLLM_IMAGE_VERSION=v0.11.2 # latest stable as of Dec 2025
VLLM_MODEL=Qwen/Qwen2.5-0.5B-Instruct
VLLM_HOST=0.0.0.0
VLLM_PORT=8000
VLLM_MAX_MODEL_LEN=1024
VLLM_GPU_MEMORY_UTILIZATION=0.9
VLLM_DTYPE=half
```

2. **Create `docker-compose.yml`** with GPU support:

```yaml
services:
  vllm:
    image: vllm/vllm-openai:${VLLM_IMAGE_VERSION}
    container_name: vllm-server
    command: >
      --model ${VLLM_MODEL}
      --host ${VLLM_HOST}
      --port ${VLLM_PORT}
      --max-model-len ${VLLM_MAX_MODEL_LEN}
      --gpu-memory-utilization ${VLLM_GPU_MEMORY_UTILIZATION}
      --dtype ${VLLM_DTYPE}
    ports:
      - "8000:8000"
    volumes:
      - ./models:/root/.cache/huggingface
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: 1
              capabilities: [gpu]
    restart: unless-stopped
```

> **⚠️ Important for Metrics:** Do NOT add `--disable-log-stats` to the command above. This flag would disable the statistics collection that Prometheus needs. The default configuration (without this flag) is correct for observability.

3. **Deploy vLLM:**

```bash
docker compose up -d
```

4. **Add vLLM to Prometheus** - Edit `docker-compose/prometheus.yaml`:

```yaml
scrape_configs:
  # ... existing configs ...

  - job_name: "vllm"
    static_configs:
      - targets: ["<vllm-host>:8000"] # Use hostname or IP where vLLM is running
```

Then restart Prometheus:

```bash
cd docker-compose
docker compose restart prometheus
```

5. **Verify metrics:**

```bash
curl http://localhost:8000/metrics | grep vllm:request_success_total
```

**If metrics endpoint returns empty or no vLLM metrics appear:**

- Ensure you did NOT add `--disable-log-stats` to your vLLM command
- Check vLLM logs: `docker logs vllm-server`
- Verify vLLM is running: `docker ps | grep vllm`

**📖 Full guide with troubleshooting and validation:** [vLLM Observability Guide](vllm-guide.md)

---

### Option 2: Ollama

**Coming soon** - Ollama integration guide

**📖 Full guide:** [Ollama Observability Guide](ollama-guide.md) _(Coming soon)_

---

[← Back to Advanced Setup](../ADVANCED_SETUP.md)
