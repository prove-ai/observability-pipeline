# Getting Started

## What This Pipeline Does

When deployed with the full deployment profile (i.e., with `full` in the `docker compose` command), this observability pipeline solves a common problem: **how to monitor distributed applications using OpenTelemetry traces**. Instead of instrumenting your application twice (once for traces, once for metrics), this pipeline automatically derives metrics from traces and stores them for long-term analysis.

**At a Glance:**

- Your application sends traces (using OpenTelemetry)
- The pipeline converts those traces into useful metrics (request rate, errors, latency)
- You can query and visualize these metrics in any Prometheus-compatible tool
- All metrics are efficiently compressed and stored for 12 months in VictoriaMetrics

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

**Clone the repository:**

```bash
git clone https://github.com/prove-ai/observability-pipeline.git
```

### Initial Setup

In going through this guide, there are two modes you can operate in:

- Default mode
- Custom configuration mode

**Default mode** 

Because the default `.env.example` file uses **API Key authentication** with placeholder credentials suitable for testing, the pipeline works out-of-the-box without requiring a `.env` file. The system automatically uses `placeholder_api_key` as the API key, allowing you to run the demo immediately. When making requests, include `placeholder_api_key` in your `X-API-Key` header like so:

- API Key: `placeholder_api_key` (header: `X-API-Key: placeholder_api_key`)

All subsequent code snippets designated as 'default mode' are written with this convention.

**Custom configuration mode**

If you want to customize credentials or use Basic Auth mode, there are a handful of extra steps. 

Make sure you're in the repository root:

```bash
# Navigate to the repository root
cd /path/to/observability-pipeline
```

Create your environment configuration file by copying the provided `env.example` file into your own `.env` file:

```bash 
cp .env.example .env
```

(The pipeline will work with its defaults if you skip this)

`.env.example` uses **API Key authentication** with placeholder credentials suitable for testing:

- Basic Auth: `user:secretpassword` (for Basic Auth mode)

By default, the `env_file` directives in `docker-compose/docker-compose.yaml` are commented out so that the pipeline will work without a `.env` file. If you created your own `.env` file in the previous step, you'll need to uncomment the `env_file` sections in the `docker-compose.yaml` file for the `envoy` and `prometheus-base` services.

Look for these lines:

```yaml
# env_file:
#   - ../.env
```

And uncomment them so Docker Compose will load your `.env` file.

**⚠️ For production:** Edit `.env` to change these credentials before deployment. 

### Start the Full Stack (Greenfield Setup)
Whether you went through default or custom configuration mode, you're ready to stand up the observability pipeline.

To do so, navigate to the repository root if you're not already there:

```bash
cd /path/to/observability-pipeline
```

> **💡 Note:** Before proceeding, make sure Docker Desktop (or Docker Engine) is running. Start Docker Desktop from your applications menu and wait for it to fully boot up before proceeding.

With that done, you can start everything with the following command:

```bash
cd docker-compose
docker compose --profile full up -d --build
```

**That's it!** You now have a complete observability stack running with:

```
✓ OpenTelemetry Collector (receiving traces)
✓ Prometheus (scraping and querying metrics)
✓ VictoriaMetrics (storing metrics for 12 months)
```

### Verify It's Working
To make sure that the observability stack is functioning as expected, run through the steps below. 

1. Check all services are healthy

```bash
docker compose ps
```

**Expected output:** A table listing the stack’s containers (for example, envoy, otel-collector, prometheus, and victoriametrics) with their STATUS shown as Up/Running, plus the PORTS each service is exposing. If all services are healthy, you should see each container listed and running with no error or restart loops.

2. Verify OpenTelemetry Collector is ready

```bash
curl http://localhost:13133/health/status
```

**Expected output:** You should see `{"status":"Server available"}`, and you may also see `"upSince":"<some_datetime_string>"` and `"uptime":"<some_number_of_milliseconds>"`

3. Verify Prometheus can reach targets

This snippet will use the default API key and should work out of the box:

```bash
curl -H "X-API-Key: placeholder_api_key" http://localhost:9090/api/v1/targets | jq
```

For Basic Auth, there are a few preliminary configuration steps that must be completed, because our Prometheus build's authentication depends on your ENVOY_AUTH_METHOD setting. You must:

- Create a `.env` file (or modify the one you created above) with:
  - `ENVOY_AUTH_METHOD=basic-auth`
  - `ENVOY_BASIC_AUTH_CREDENTIALS=username:password`
- Uncomment the `env_file` sections in `docker-compose.yaml` if you haven't already
- Restart the services with the `--build` flag

Then use the credentials from your `ENVOY_BASIC_AUTH_CREDENTIALS` setting:

```bash 
curl -u username:password http://localhost:9090/api/v1/targets | jq
```

**Expected output:** Whether you use default or Basic Auth, all targets should be showing `"up"`.

4. Verify VictoriaMetrics is running

To use the default API Key authentication, run:

```bash
# Note: VictoriaMetrics endpoints are authenticated via Envoy

curl -H "X-API-Key: placeholder_api_key" http://localhost:8428/health
```

For Basic Auth, use the credentials from `ENVOY_BASIC_AUTH_CREDENTIALS` in the `.env` file:

```bash
curl -u user:secretpassword http://localhost:8428/health
```

**Expected output:** `"OK"`

## Send Your First Trace

This requires you to install `otel-cli`; this is optional but helpful for testing. The snippets provided below will help you install `otel-cli` on different systems: 

```bash
# macOS
brew install equinix-labs/otel-cli/otel-cli

# Linux
curl -L https://github.com/equinix-labs/otel-cli/releases/latest/download/otel-cli-linux-amd64 -o /usr/local/bin/otel-cli
chmod +x /usr/local/bin/otel-cli
```

### Send a test trace:

OTLP receivers are authenticated via Envoy. To use the default API Key authentication, run:

```bash
otel-cli span \
  --service "otel-test" \
  --name "demo-span" \
  --endpoint http://localhost:4318/v1/traces \
  --protocol http/protobuf \
  --attrs "env=dev,component=demo" \
  --start "$(date -Iseconds)" \
  --end "$(date -Iseconds)" \
  --otlp-headers "X-API-Key=placeholder_api_key"
```

For Basic Auth, use Envoy credentials from `ENVOY_BASIC_AUTH_CREDENTIALS` in the `.env` file:

```bash
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

**View the results**
(It will likely take 10-15 seconds for metrics to appear):

To use the default API Key authentication, use curl:

```bash
curl -H "X-API-Key: placeholder_api_key" \
  --data-urlencode 'query=llm_traces_span_metrics_calls_total{service_name="otel-test"}' \
  'http://localhost:9090/api/v1/query' | jq
```

For Basic Auth, configure `prometheus-web-config.yaml` and navigate to `http://localhost:9090` in a browser and login with your Prometheus credentials when prompted. Then run `llm_traces_span_metrics_calls_total{service_name="otel-test"}` in the Prometheus UI.

**Expected output:** With the default API key authentication approach, you should see a JSON response from the Prometheus HTTP API with "status": "success", along with a "data" object containing "resultType": "vector" and a "result" array. For the Basic Auth approach, you should see roughly the same information in the Prometheus UI.

---

## Monitor LLM Inference

Monitor your LLM inference servers to track metrics like latency, throughput, and token generation. Choose the framework that matches your deployment:

### Option 1: vLLM

**Prerequisites:** NVIDIA GPU with Compute Capability ≥ 7.0, NVIDIA Container Toolkit

> **Note:** This guide uses vLLM v0.11.2 (latest stable as of December 2025). Check the [vLLM releases page](https://github.com/vllm-project/vllm/releases) for newer versions. If upgrading from v0.6.x or earlier, review the [changelog](https://github.com/vllm-project/vllm/releases) for breaking changes.

> **Note:** There is no 'default mode' for running vLLM; if you didn't create and modify a `.env` file as part of the 'Basic Auth' workflow above, you'll need to do it to proceed.

**Quick Setup:**

1. **Create configuration**:

Add the following vLLM-specific values to your `.env` file.

```bash
VLLM_IMAGE_VERSION=v0.11.2 # latest stable as of Dec 2025
VLLM_MODEL=Qwen/Qwen2.5-0.5B-Instruct
VLLM_HOST=0.0.0.0
VLLM_PORT=8000
VLLM_MAX_MODEL_LEN=1024
VLLM_GPU_MEMORY_UTILIZATION=0.9
VLLM_DTYPE=half
```

2. **Modify `docker-compose.yml`:**

Under `services:`, add the following vLLM-specific values to `docker-compose.yml` to run vLLM with GPU support. Note that Docker Compose does **not** automatically populate the `${...}` values in `docker-compose.yaml` from your repo-root `.env` when you run Compose from the `docker-compose/` directory. You can either:

- Replace the `${...}` placeholders with the values above (or your own), or
- Run `docker compose` with the repo-root env file explicitly: `cd docker-compose && docker compose --env-file ../.env --profile full up -d --build`.

```yaml
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

4. **Add vLLM to Prometheus** 

Edit `docker-compose/prometheus.yaml` by adding the new target below (this should replace the `- targets: ["existing-target:port"]` line that already exists in `prometheus.yaml`):

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
docker compose --profile full restart prometheus
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
