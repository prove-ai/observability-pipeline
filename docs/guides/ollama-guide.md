# Ollama Observability Integration

## Overview

This guide provides detailed instructions for deploying Ollama with comprehensive observability using LiteLLM proxy and DCGM exporter. It covers only what is required with minimal complexity.

Ollama provides powerful local LLM inference and [exposes some metrics](https://docs.ollama.com/api/usage) but, without instrumentation, you cannot track token usage, request latencies, error rates, or GPU utilization. This creates a problematic observability gap for production deployments.

This guide solves that problem using a proxy-based architecture that requires no application code changes while capturing 90% of the metrics you would get from full OpenTelemetry instrumentation.

**By the end of this guide, you will have:**

- A running Ollama server with GPU acceleration
- LiteLLM proxy providing inference metrics (tokens, latency, TTFT, errors)
- DCGM exporter providing GPU metrics (utilization, memory, temperature, power)
- A Prometheus instance scraping these metrics
- A validated observability pipeline

---

## Architecture Overview

### High-Level Architecture

Integration of Ollama with the observability pipeline:

```
┌──────────────────────────────────────────┐
│ Ollama Server                            │
│ - Runs on host or in container           │
│ - OpenAI-compatible API (port 11434)     │
│ - No native metrics                      │
└──────────────────────────────────────────┘
                    ↓
┌──────────────────────────────────────────┐
│ LiteLLM Proxy (Container)                │
│ - Routes requests to Ollama              │
│ - Exposes /metrics endpoint (port 4000)  │
│ - Tracks tokens, latency, TTFT, errors   │
└──────────────────────────────────────────┘
                    ↓
┌──────────────────────────────────────────┐
│ Prometheus (Container)                   │
│ - Scrapes LiteLLM metrics                │
│ - Scrapes DCGM metrics                   │
│ - Stores time-series data                │
└──────────────────────────────────────────┘
                    ↑
┌──────────────────────────────────────────┐
│ DCGM Exporter (Container)                │
│ - Monitors GPU hardware                  │
│ - Exposes /metrics endpoint (port 9400)  │
│ - Tracks utilization, memory, temp       │
└──────────────────────────────────────────┘
```

**Key Points:**

- LiteLLM proxy sits between your application and Ollama, providing metrics without code changes
- DCGM exporter runs alongside Ollama to capture GPU-level telemetry
- Prometheus pulls metrics from both exporters
- Applications send requests to LiteLLM (port 4000) instead of Ollama directly (port 11434)

### Observability Approach Comparison

| Approach | Tokens | Latency | TTFT | GPU | Code Changes | Effort |
|----------|--------|---------|------|-----|--------------|--------|
| Code Instrumentation (OTel) | ✅ | ✅ | ✅ | ❌ | Required | High |
| Exporters Only (ollama-exporter) | ❌ | ❌ | ❌ | ❌ | None | Low |
| **LiteLLM Proxy + DCGM** | ✅ | ✅ | ✅ | ✅ | None | Medium |

**Why LiteLLM Proxy is recommended:**

LiteLLM provides 90% of instrumentation capabilities without requiring application modifications. It works with 100+ inference backends (Ollama, vLLM, OpenAI, Anthropic, Azure, Bedrock) and exposes unified metrics regardless of which backend you use. This eliminates vendor lock-in at the observability layer and enables meaningful cross-backend comparisons.

DCGM exporter fills the GPU metrics gap that neither code instrumentation nor LiteLLM can address, providing hardware-level visibility essential for capacity planning and thermal management.

### Key Metrics Exposed

**LiteLLM Proxy Metrics:**

[NOTE: I need to check that each of these metrics works as written.]

```
litellm_input_tokens_metric
litellm_output_tokens_metric
litellm_request_total_latency_metric
litellm_llm_api_time_to_first_token_metric # check
litellm_deployment_failure_responses
```

**DCGM Exporter Metrics:**

```
DCGM_FI_DEV_GPU_UTIL
DCGM_FI_DEV_MEM_COPY_UTIL
DCGM_FI_DEV_FB_USED
DCGM_FI_DEV_GPU_TEMP
DCGM_FI_DEV_POWER_USAGE
```

**Full metric lists:** Available at `http://localhost:4000/metrics` (LiteLLM) and `http://localhost:9400/metrics` (DCGM)

---

## Prerequisites

### System Requirements

- **GPU**: NVIDIA GPU with Compute Capability ≥ 7.0
- **NVIDIA Driver**: Compatible with your GPU
- **NVIDIA Container Toolkit**: For GPU passthrough to Docker containers

#### macOS or non-NVIDIA Setups

On macOS (or any machine without an NVIDIA GPU), you can still use this guide for Ollama + LiteLLM + Prometheus. GPU metrics (DCGM) will not be available.

- **Ollama:** Run Ollama on the host (native app; uses Metal on Apple Silicon). Do not run the GPU verification commands below.
- **Start only the services you need.** Do not run `docker compose --profile ollama up -d` without naming services—that would try to start the DCGM exporter and fail. Instead run:

  ```bash
  docker compose --profile ollama up -d litellm
  ```
  
  Add `prometheus`, `victoriametrics`, or other services to the list if you use those profiles.
- **Optional:** In `docker-compose/prometheus.yaml`, comment out the `job_name: "dcgm-exporter"` scrape block to avoid a DOWN target in Prometheus (the pipeline will run with or without this step, it just changes what information you get back from Prometheus).

**Verify GPU setup:**

```bash
nvidia-smi
docker run --rm --gpus all nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi
```

**Note:** The second command fails if NVIDIA Container Toolkit isn't installed or configured.

### Software Requirements

- **Docker**: Version 20.10 or higher
- **Docker Compose**: Version 2.0 or higher
- **Ollama**: Latest version (installed on host or containerized)

You can check your versions:

```bash
docker --version
docker compose version
ollama --version # This will fail if you haven't installed ollama; details about that process can be found below.
```

### Network Requirements

- **Port 11434**: Ollama API
- **Port 4000**: LiteLLM proxy API and metrics
- **Port 9400**: DCGM exporter metrics
- **Port 9090**: Prometheus UI

**Network considerations:**

- LiteLLM proxy must reach Ollama (uses `host.docker.internal:11434` if Ollama runs on host)
- Prometheus scrapes LiteLLM and DCGM using Docker service names
- All containers must be on the same Docker network

---

## Ollama Configuration

### Installing Ollama

**On Linux:**

```bash
curl -fsSL https://ollama.com/install.sh | sh
```

**On macOS/Windows:**

Download from https://ollama.com/download, or run:

```
curl -fsSL https://ollama.com/install.sh | sh
```

**Verify installation:**

```bash
ollama --version
ollama serve
```

The server starts on `http://localhost:11434` by default. 

### Pulling Models

Ollama supports hundreds of models from the central registry at ollama.com. Model choice impacts hardware requirements, inference speed, and quality.

**Example models (2025/2026 recommendations):**

```bash
ollama pull gemma3:27b    # 27B model, outperforms models 2× its size
ollama pull gemma3:9b     # 9B model, good balance of speed and quality
ollama pull llama3.2:3b   # 3B model, fastest inference on consumer hardware
```

If you've run `ollama serve` from the step above and want to pull models now, open a new terminal and run `ollama pull <model>` there; the server handles pulls while it's running. You should expect an output like:

```
pulling manifest 
pulling dde5aa3fc5ff: 100% ▕████████████████████████████████████▏ 2.0 GB                         
verifying sha256 digest 
writing manifest 
success 
```

**Model size considerations:**

- 3B models need ~4GB RAM/VRAM
- 9B models need ~8GB RAM/VRAM
- 27B models need ~16GB RAM/VRAM
- 70B models need 32GB+ RAM/VRAM

Quantization reduces these requirements automatically based on available hardware.

**Verify model download:**

```bash
ollama list
```

### Environment Variables

Ollama's resource management is controlled entirely through environment variables. Here are some key settings for production deployments:

| Variable | Description | Default | Common Values |
|----------|-------------|---------|---------------|
| `OLLAMA_NUM_PARALLEL` | Concurrent request handling | 1 | 4, 8 (requires sufficient memory) |
| `OLLAMA_MAX_LOADED_MODELS` | Models kept in memory | 1 | 2, 3 (based on GPU capacity) |
| `OLLAMA_KEEP_ALIVE` | Model unload delay | 5m | 10m, 30m, -1 (never unload) |
| `OLLAMA_MAX_QUEUE` | Request queue depth | 512 | 1024, 2048 |
| `OLLAMA_FLASH_ATTENTION` | Memory optimization | disabled | enabled (for supported GPUs) |

**To set environment variables (Linux and macOS):**

When you start Ollama from the terminal, set variables in the same shell before running the server:

```bash
export OLLAMA_NUM_PARALLEL=4
export OLLAMA_KEEP_ALIVE=10m
ollama serve
```

These `export` commands do not save the variables to a file—they apply only to that shell and to the `ollama serve` process you start from it. When you close the terminal, they're gone. To change a value, stop the server (Ctrl+C), run the exports again with the new values, then run `ollama serve` again. To have the same variables every time you open a terminal, add the `export` lines to `~/.zshrc` or `~/.bashrc`.

On macOS, if you start Ollama from the app (menu bar) instead of the terminal, environment variables you set in the shell are not used. To use custom settings, run `ollama serve` from a terminal with the exports above, or configure them for the app (e.g. via launchd) if you need the GUI.

**Note:** Parallel requests multiply context window size (4 parallel × 2K context = 8K total memory usage).

---

## LiteLLM Proxy Deployment

### Create (or Modify) Configuration File

Create (or modify) a `litellm_config.yaml` file in the same directory as your docker-compose file (e.g. `docker-compose/litellm_config.yaml` when using this repo's `docker-compose/docker-compose.yaml`):

```yaml
model_list:
  - model_name: gemma3-27b # or tinyllama if you're on a Mac and want to quickly test
    litellm_params:
      model: ollama/gemma3:27b # or ollama/tinyllama if you're on a Mac and want to quickly test
      api_base: http://host.docker.internal:11434

litellm_settings:
  callbacks: ["prometheus"]
```

**Configuration details:**

- `model_name`: Alias used by your application
- `model`: Backend format is `ollama/<model-name>`
- `api_base`: Ollama endpoint (use `host.docker.internal` for host-based Ollama)

### Create (or modify) docker-compose.yaml

Create `docker-compose.yaml` with LiteLLM, DCGM, and Prometheus services:

```yaml
services:
  litellm:
    image: ghcr.io/berriai/litellm:main-latest
    container_name: litellm-proxy
    volumes:
      - ./litellm_config.yaml:/app/config.yaml
    environment:
      - DATABASE_URL=  # Optional: for persistence
    command: --config /app/config.yaml --port 4000
    ports:
      - "4000:4000"
    networks:
      - observability
    restart: unless-stopped
    extra_hosts:
      - "host.docker.internal:host-gateway"
    profiles:
      - ollama

  dcgm-exporter:
    image: nvcr.io/nvidia/k8s/dcgm-exporter:3.1.3-3.1.4-ubuntu20.04
    container_name: dcgm-exporter
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    ports:
      - "9400:9400"
    networks:
      - observability
    restart: unless-stopped
    profiles:
      - ollama

  # Only add the prometheus service below if you're creating this file from scratch.
  # If you already have this repo's docker-compose.yaml, skip this block—it already includes Prometheus.
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    ports:
      - "9090:9090"
    restart: unless-stopped
```

**Notes:**

- `extra_hosts` enables LiteLLM to reach Ollama on the host machine
- DCGM requires GPU passthrough via `deploy.resources.reservations.devices`
- All services restart automatically on failure

**Using this repo's docker-compose instead?**  
If you are using this repository's existing `docker-compose/docker-compose.yaml` (and not creating a new file from the snippet above), LiteLLM and DCGM exporter are already defined there behind the **`ollama`** profile. Use that profile in every `docker compose` command in this guide, and start the observability stack first. Examples:

- Start the full stack plus LiteLLM (and optionally DCGM):  
  `docker compose --profile full --profile ollama up -d`
- Start only LiteLLM (Prometheus must already be running elsewhere):  
  `docker compose --profile ollama up -d litellm`
- Start only DCGM exporter:  
  `docker compose --profile ollama up -d dcgm-exporter`

Prometheus and scrape configs for LiteLLM/DCGM are already in this repo; no need to add the standalone `prometheus` block or a separate `prometheus.yml` if you use the repo's compose.

### Start LiteLLM Proxy

If you created a **standalone** compose file from the snippet above:

```bash
docker compose up -d litellm
```

If you're using **this repo's** `docker-compose/docker-compose.yaml` (runs everything in the `ollama` profile except DCGM—i.e. LiteLLM only):

```bash
docker compose --profile ollama up -d litellm
```

**Check logs:**

```bash
docker logs -f litellm-proxy
```

Look for:

```
INFO: Uvicorn running on http://0.0.0.0:4000
✅ Prometheus metrics enabled on /metrics
```

**Test the proxy:**

```bash
curl http://localhost:4000/health
```

Expected response: `{"status":"healthy"}`

---

## DCGM Exporter Deployment

### Why DCGM is Required

Neither LiteLLM proxy nor OpenTelemetry instrumentation can access GPU hardware metrics. DCGM (NVIDIA Data Center GPU Manager) provides low-level telemetry including utilization percentages, memory allocation, temperature, and power consumption. These metrics are essential for understanding hardware costs, detecting thermal issues, and making capacity planning decisions.

### DCGM Configuration

DCGM is already included in the `docker-compose.yml` from the previous section. Start it:

- **Standalone compose:** `docker compose up -d dcgm-exporter`
- **This repo's compose:** `docker compose --profile ollama up -d dcgm-exporter`

**Check logs:**

```bash
docker logs dcgm-exporter
```

Look for successful GPU detection and exporter startup.

### Verify DCGM Metrics

```bash
curl http://localhost:9400/metrics | grep DCGM_FI_DEV
```

You should see output like:

```
DCGM_FI_DEV_GPU_UTIL{gpu="0",UUID="GPU-...",device="nvidia0"} 45
DCGM_FI_DEV_FB_USED{gpu="0",UUID="GPU-...",device="nvidia0"} 8192
DCGM_FI_DEV_GPU_TEMP{gpu="0",UUID="GPU-...",device="nvidia0"} 62
```

---

## Prometheus Configuration

### Create (or modify) prometheus.yml

This repository includes an existing `docker-compose/prometheus.yaml` that may differ from the recommendations below (e.g. scrape targets, job names, or other jobs). You may need to make small changes so it matches your setup or merge the relevant scrape configs into the existing file.

Create `prometheus.yml` (or edit the existing one):

```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: "litellm"
    static_configs:
      - targets:
          - "litellm-proxy:4000"

  - job_name: "dcgm"
    static_configs:
      - targets:
          - "dcgm-exporter:9400"
```

**Configuration details:**

- `scrape_interval`: How often Prometheus pulls metrics (15 seconds is standard)
- `targets`: Docker service names and ports (works because all containers share a network)

### Deploy Prometheus

Prometheus is already included in `docker-compose.yml` (or, if using this repo's compose, it's part of the main stack). Start it:

- **Standalone compose:** `docker compose up -d prometheus`
- **This repo's compose:** Prometheus starts with `docker compose --profile full up -d`; use `--profile full --profile ollama up -d` to run the full stack plus LiteLLM/DCGM so Prometheus can scrape them.

**Verify Prometheus UI:**

Open `http://localhost:9090`

Go to **Status → Targets** and check:

- `job="litellm"` → State: **UP**
- `job="dcgm"` → State: **UP**

If either shows **DOWN**, verify the container is running and ports are accessible.

---

## End-to-End Validation

This section verifies that Ollama serves requests through LiteLLM, metrics are exposed, and Prometheus is scraping successfully.

### Send Test Request via LiteLLM

```bash
curl http://localhost:4000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gemma3-27b",
    "messages": [
      {"role": "user", "content": "Say hello in one sentence."}
    ],
    "max_tokens": 20
  }'
```

**Expected response:**

```json
{
  "id": "chatcmpl-...",
  "choices": [
    {
      "message": {
        "role": "assistant",
        "content": "Hello! How can I help you today?"
      }
    }
  ],
  "usage": {
    "prompt_tokens": 12,
    "completion_tokens": 8,
    "total_tokens": 20
  }
}
```

### Check LiteLLM Metrics Endpoint

```bash
curl http://localhost:4000/metrics | grep litellm
```

You should see Prometheus-formatted output including:

```
litellm_input_tokens_total{...} 12.0
litellm_output_tokens_total{...} 8.0
litellm_request_total_latency_seconds_sum{...} 1.234
```

### Check DCGM Metrics Endpoint

```bash
curl http://localhost:9400/metrics | grep DCGM_FI_DEV_GPU_UTIL
```

Expected output:

```
DCGM_FI_DEV_GPU_UTIL{gpu="0",...} 78
```

### Verify Prometheus Targets

Open Prometheus UI: `http://localhost:9090`

Go to **Status → Targets** and verify:

- Both `job="litellm"` and `job="dcgm"` show **UP**
- Last scrape shows recent timestamp (within last 15 seconds)

### Basic PromQL Checks

In the **Graph** tab, run these queries:

**Check targets are up:**

```promql
up{job="litellm"}
up{job="dcgm"}
```

Expected: value `1` for both.

**Check LiteLLM metrics after sending requests:**

```promql
litellm_input_tokens_total
litellm_request_total_latency_seconds_count
litellm_time_to_first_token_seconds_bucket
```

**Check GPU metrics:**

```promql
DCGM_FI_DEV_GPU_UTIL
DCGM_FI_DEV_FB_USED
DCGM_FI_DEV_GPU_TEMP
```

You should see non-zero values and increasing counters as you generate more traffic.

---

## Troubleshooting

### Ollama Not Responding

**Symptoms:**

- LiteLLM proxy returns connection errors
- `curl http://localhost:11434` fails

**Checks:**

```bash
ollama list                    # Verify Ollama is running
curl http://localhost:11434/   # Test API endpoint
```

**Common causes:**

| Issue | Solution |
|-------|----------|
| Ollama not running | Run `ollama serve` |
| Wrong port | Verify Ollama is on port 11434 |
| Firewall blocking | Allow port 11434 |
| Model not loaded | Run `ollama pull <model-name>` |

### LiteLLM Proxy Cannot Reach Ollama

**Symptoms:**

- LiteLLM health check passes but requests fail
- Logs show connection refused to `host.docker.internal`

**Checks:**

From inside the LiteLLM container:

```bash
docker exec -it litellm-proxy curl http://host.docker.internal:11434
```

**Fixes:**

| Issue | Solution |
|-------|----------|
| `host.docker.internal` not resolving | Add `extra_hosts` to docker-compose.yml |
| Ollama not accessible from container | Use host IP instead of `host.docker.internal` |
| Wrong port in config | Update `api_base` in litellm_config.yaml |

**Docker networking note:** The `extra_hosts` section in docker-compose.yml enables container-to-host communication. Without it, `host.docker.internal` won't resolve.

### DCGM Exporter Not Running

**Symptoms:**

- Container crashes on startup
- Prometheus target shows DOWN for `job="dcgm"`

**Checks:**

```bash
docker logs dcgm-exporter
nvidia-smi                                      # On host
docker exec -it dcgm-exporter nvidia-smi        # Inside container
```

**Fixes:**

| Issue | Solution |
|-------|----------|
| GPU not detected | Verify NVIDIA Container Toolkit is installed |
| Wrong GPU driver | Update NVIDIA driver on host |
| Missing GPU capabilities | Add `capabilities: [gpu]` to docker-compose.yml |
| DCGM version incompatible | Try different DCGM exporter image version |

### Prometheus Targets DOWN

**Symptoms:**

- In Prometheus UI → **Status → Targets** → shows **DOWN**

**Verify targets in prometheus.yml:**

```yaml
scrape_configs:
  - job_name: "litellm"
    static_configs:
      - targets: ["litellm-proxy:4000"]
  - job_name: "dcgm"
    static_configs:
      - targets: ["dcgm-exporter:9400"]
```

**Common errors:**

| Error Message | Cause | Solution |
|---------------|-------|----------|
| `no such host` | Service name doesn't resolve | Verify all containers are on same Docker network |
| `connection refused` | Wrong port or service not running | Check `docker ps` and container logs |
| `context deadline exceeded` | Timeout | Increase scrape timeout or check network |

### Metrics Not Updating

**Symptoms:**

- `up{job="litellm"}` returns `1` but `litellm_*` metrics stay at `0`

**Checks:**

- Have you sent any requests through LiteLLM?
- Re-run queries after generating test traffic
- Verify Prometheus scrape interval hasn't been set too high

**Fixes:**

Send test traffic (see validation section). Lower scrape interval if needed:

```yaml
global:
  scrape_interval: 5s
```

---

## Privacy Considerations

Prometheus only receives numeric metrics from LiteLLM (token counts, latencies, error counts, etc.). Prompt and response content is not sent to Prometheus by default.

If you add **OpenTelemetry** (e.g. for distributed tracing), LiteLLM may include message content in traces by default, which can expose sensitive user data. If you use Traceloop or OpenLLMetry for OTel instrumentation, refer to their documentation for options to disable content in traces.

---

## Useful Commands

### Container Management

```bash
docker compose up -d                    # Start all services
docker compose down                     # Stop all services
docker logs -f litellm-proxy            # View LiteLLM logs
docker logs -f dcgm-exporter            # View DCGM logs
docker logs -f prometheus               # View Prometheus logs
```

### Ollama Management

```bash
ollama list                             # Show downloaded models
ollama ps                               # Show running models and memory usage
ollama pull <model>                     # Download a model
ollama rm <model>                       # Remove a model
```

### GPU Debugging

```bash
nvidia-smi                                      # GPU status on host
docker exec -it dcgm-exporter nvidia-smi        # GPU status in container
watch -n 1 nvidia-smi                           # Monitor GPU in real-time
```

### Test Endpoints

```bash
curl http://localhost:11434                     # Ollama health
curl http://localhost:4000/health               # LiteLLM health
curl http://localhost:4000/metrics              # LiteLLM metrics
curl http://localhost:9400/metrics              # DCGM metrics
```

### PromQL Quick Checks

```promql
up{job="litellm"}                               # LiteLLM target status
up{job="dcgm"}                                  # DCGM target status
litellm_input_tokens_total                      # Total input tokens
litellm_deployment_failure_responses            # Error count
DCGM_FI_DEV_GPU_UTIL                           # GPU utilization %
DCGM_FI_DEV_FB_USED                            # GPU memory used (MB)
```

---

## Notes

- **LiteLLM persistence (optional):** To persist LiteLLM state (e.g. spend tracking, request history), add an `environment` block to the `litellm` service with `DATABASE_URL=<your-connection-string>`.