# vLLM Observability Integration

[← Back to Advanced Setup](../ADVANCED_SETUP.md)

## Overview

This guide provides detailed instructions for deploying vLLM with GPU acceleration using Docker Compose and configuring Prometheus to scrape vLLM’s built-in metrics.
It covers only what is required with minimal complexity.

**By the end of this guide, you will have:**

- A running vLLM OpenAI-compatible inference server
- GPU support via NVIDIA Container Toolkit
- vLLM metrics exposed at `/metrics`
- A Prometheus instance scraping these metrics
- A validated observability pipeline

# Architecture Overview

## High-Level Architecture

Integration of vLLM with the Observability Pipeline:

```
┌─────────────────────────────────────────┐
│ vLLM Deployment (Separate Stack)        │
│ ┌─────────────────────────────────────┐ │
│ │ vLLM Server                         │ │
│ │ - OpenAI API (port 8000)            │ │
│ │ - /metrics endpoint                 │ │
│ └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
                    ↓ (scrapes over network)
┌─────────────────────────────────────────┐
│ Observability Pipeline Stack            │
│ ┌─────────────────────────────────────┐ │
│ │ Prometheus                          │ │
│ │ - Scrapes vLLM metrics              │ │
│ │ - Stores metrics                    │ │
│ └─────────────────────────────────────┘ │
│ ┌─────────────────────────────────────┐ │
│ │ VictoriaMetrics                     │ │
│ │ - Long-term storage (12 months)     │ │
│ └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
```

**Key Points:**

- vLLM exposes a **Prometheus-compatible `/metrics` endpoint**

- Prometheus pulls (scrapes) metrics directly from the vLLM container.

**Example vLLM Metrics:**

```
vllm:time_to_first_token_seconds_bucket
vllm:time_to_first_token_seconds_count
vllm:time_per_output_token_seconds_bucket
vllm:e2e_request_latency_seconds_bucket
vllm:request_generation_tokens_count
```

**Full metric list:** Available at `http://<vllm-host>:8000/metrics`

---

## Prerequisites

### System Requirements

- **GPU**: NVIDIA GPU with Compute Capability ≥ 7.0
- **NVIDIA Driver**: Compatible with your GPU
- **NVIDIA Container Toolkit**: For GPU passthrough to Docker containers

**Verify GPU setup:**

```bash
nvidia-smi
docker run --rm --gpus all nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi
```

### Software Requirements

- **Docker**: Version 20.10 or higher
- **Docker Compose**: Version 2.0 or higher

### Network Requirements

- **Port 8000**: vLLM API and metrics endpoint
- **Port 9090**: Prometheus UI

**Network considerations:**

- If Prometheus and vLLM run in the same Docker network, Prometheus scrapes using the container name: `vllm-server:8000`
- If they run on different hosts, use: `http://<vllm-host-ip>:8000/metrics`
- Ensure Prometheus can reach the vLLM host and port (check firewall rules)

### Model Download Requirements

- **Public models**: Internet access required for first pull
- **Private models**: HuggingFace token required
  - Set `HF_HOME` or mount an auth file
  - Export `HUGGINGFACE_HUB_TOKEN` if needed

---

## vLLM Configuration

vLLM is configured using environment variables stored in a `.env` file.

### Create .env File

Create a `.env` file in the same directory as your `docker-compose.yml`:

```bash
# vLLM image version - v0.11.2 is latest stable as of Dec 2025
VLLM_IMAGE_VERSION=v0.11.2

# Model Configuration
VLLM_MODEL=Qwen/Qwen2.5-0.5B-Instruct

# Server Bindings
VLLM_HOST=0.0.0.0
VLLM_PORT=8000

# Runtime Settings
VLLM_MAX_MODEL_LEN=1024
VLLM_GPU_MEMORY_UTILIZATION=0.9
VLLM_DTYPE=half
```

### Configuration Variables

| Variable                      | Description                       | Common Values               |
| ----------------------------- | --------------------------------- | --------------------------- |
| `VLLM_IMAGE_VERSION`          | Docker image tag                  | v0.11.2 (latest Dec 2025)   |
| `VLLM_MODEL`                  | HuggingFace model ID              | Any compatible model        |
| `VLLM_HOST`                   | Bind HTTP server to interfaces    | 0.0.0.0                     |
| `VLLM_PORT`                   | Port for API + /metrics           | 8000                        |
| `VLLM_MAX_MODEL_LEN`          | Maximum context length            | 1024, 2048, 4096            |
| `VLLM_GPU_MEMORY_UTILIZATION` | GPU memory allocation (0.0 - 1.0) | 0.9 (recommended)           |
| `VLLM_DTYPE`                  | Model precision                   | `half`, `bfloat16`, `float` |

**Optional:** For private HuggingFace models:

```bash
HUGGINGFACE_HUB_TOKEN=your_token_here
```

### ⚠️ Important: Metrics Collection Requirement

For Prometheus to collect vLLM metrics, statistics logging must remain **enabled** (the default behavior).

**Critical:** Do NOT add the `--disable-log-stats` flag to your vLLM command configuration.

| Configuration            | Stats Logging | Prometheus Works? | Use This?                 |
| ------------------------ | ------------- | ----------------- | ------------------------- |
| No flag (default)        | ✅ Enabled    | ✅ Yes            | ✅ **Recommended**        |
| `--disable-log-stats`    | ❌ Disabled   | ❌ No             | ❌ **Never use**          |
| `--no-disable-log-stats` | ✅ Enabled    | ✅ Yes            | ⚠️ Explicit (unnecessary) |

**Why this matters:** The `--disable-log-stats` flag disables vLLM's internal statistics collection, which breaks the `/metrics` endpoint that Prometheus depends on.

### Verify .env Loading

The docker-compose file references these variables. To confirm they're loaded:

```bash
docker compose config
```

---

## Deploying vLLM

### Create docker-compose.yml

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
      - "${VLLM_PORT}:${VLLM_PORT}"
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
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

**Notes:**

- GPU passthrough handled by `deploy.resources.reservations.devices`
- `models` folder caches HuggingFace weights to avoid re-downloading
- Container restarts automatically if it stops
- **⚠️ Metrics requirement:** Do NOT include `--disable-log-stats` in the command section - this would break Prometheus metrics collection. Stats logging is enabled by default and must remain enabled.

### Start vLLM

From the directory containing `docker-compose.yml` and `.env`:

```bash
docker compose up -d
```

### Verify vLLM Deployment

**Check logs:**

```bash
docker logs -f vllm-server
```

Look for:

- "Loading model: Qwen/Qwen2.5-0.5B-Instruct"
- "vLLM OpenAI server running"
- "Uvicorn running on http://0.0.0.0:8000"

**Validate GPU access:**

```bash
docker exec -it vllm-server nvidia-smi
```

**Test API:**

```bash
curl http://localhost:8000/v1/models
```

**Test metrics endpoint:**

```bash
curl http://localhost:8000/metrics
```

---

## Deploying Prometheus

Prometheus scrapes the vLLM `/metrics` endpoint and stores metrics for querying.

You can run Prometheus on the same host or a separate machine. Below assumes a separate `prometheus-docker-compose.yml`.

### Create prometheus-docker-compose.yml

```yaml
services:
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    ports:
      - "9090:9090"
    restart: unless-stopped
```

### Create prometheus.yml

Minimal config to scrape a vLLM instance:

```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: "vllm"
    static_configs:
      - targets:
          - "vllm-server:8000" # Same Docker network as vLLM
```

**If Prometheus runs on a different host**, replace target with the vLLM host/IP:

```yaml
scrape_configs:
  - job_name: "vllm"
    static_configs:
      - targets:
          - "<VLLM_SERVER_IP>:8000"
```

### Start Prometheus

From the directory containing `prometheus-docker-compose.yml` and `prometheus.yml`:

```bash
docker compose -f prometheus-docker-compose.yml up -d
```

**Verify container:**

```bash
docker ps
```

You should see a `prometheus` container running.

### Validate Prometheus UI

Open in browser: `http://<PROMETHEUS_HOST>:9090`

Go to **Status → Targets** and check:

- job="vllm"
- State: **UP**

If it's **DOWN**, check:

- vLLM is reachable from Prometheus host
- Target hostname/IP is correct
- Port (8000) is open and not blocked by firewall

---

## End-to-End Validation

This section verifies that vLLM serves requests, metrics are exposed, and Prometheus is scraping.

### 1. Send Test Request to vLLM

```bash
curl http://<VLLM_HOST>:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen2.5-0.5B-Instruct",
    "messages": [
      {"role": "user", "content": "Say hello in one short sentence."}
    ],
    "max_tokens": 10
  }'
```

### 2. Check vLLM Metrics Endpoint

```bash
curl http://<VLLM_HOST>:8000/metrics | head -n 40
```

You should see Prometheus-formatted output, including:

```
# HELP vllm:time_to_first_token_seconds Histogram of time to first token in seconds.
# TYPE vllm:time_to_first_token_seconds histogram
vllm:time_to_first_token_seconds_bucket{...}
```

### 3. Verify Prometheus Target

Open Prometheus UI: `http://<PROMETHEUS_HOST>:9090`

Go to **Status → Targets** and check:

- `job="vllm"` is listed
- State is **UP**
- Last scrape shows a recent timestamp

### 4. Basic PromQL Checks

In the **Graph** tab, run:

```promql
up{job="vllm"}
```

Expected: value `1` for your vLLM instance.

After sending a few requests to vLLM, query:

```promql
vllm:request_success_total
vllm:generation_tokens_total
vllm:e2e_request_latency_seconds_count
```

You should see non-zero values and increasing counters as you generate more traffic.

---

## Troubleshooting

### vLLM Container Not Running

**Symptoms:**

- `docker ps` does not show `vllm-server`
- `docker compose up -d` fails

**Checks:**

```bash
docker compose up -d
docker ps
docker logs -f vllm-server
```

**Common causes:**

| Issue                   | Solution                                                  |
| ----------------------- | --------------------------------------------------------- |
| Invalid model name      | Verify `VLLM_MODEL` exists on HuggingFace                 |
| Wrong dtype for model   | Try `half`, `bfloat16`, or `float` in `VLLM_DTYPE`        |
| GPU not available       | Run `nvidia-smi` and check NVIDIA Container Toolkit       |
| Insufficient GPU memory | Reduce `VLLM_GPU_MEMORY_UTILIZATION` or use smaller model |

### GPU Not Detected in Container

**Symptoms:**

- vLLM crashes on startup
- Logs mention CUDA or device errors

**Checks:**

On host:

```bash
nvidia-smi
```

Inside container:

```bash
docker exec -it vllm-server nvidia-smi
```

**Fixes:**

- Install/fix NVIDIA driver on host
- Install NVIDIA Container Toolkit
- Ensure Docker is configured with `--gpus` support
- Verify `deploy.resources.reservations.devices` block is present in compose file

### /metrics Endpoint Not Reachable

**Symptoms:**

- `curl http://<VLLM_HOST>:8000/metrics` fails or times out

**Checks:**

From the vLLM host:

```bash
curl http://localhost:8000/metrics
```

From the Prometheus host:

```bash
curl http://<VLLM_HOST>:8000/metrics
```

**Fixes:**

| Issue                              | Solution                                                 |
| ---------------------------------- | -------------------------------------------------------- |
| Container not running              | Check `docker ps` and container logs                     |
| Wrong port                         | Confirm `VLLM_PORT` in `.env`                            |
| Firewall blocking                  | Allow port 8000 in firewall/security groups              |
| Wrong hostname                     | Update Prometheus config with correct host               |
| `--disable-log-stats` flag present | Remove this flag from docker-compose.yml command section |

**Important:** If you added the `--disable-log-stats` flag to your vLLM command configuration, **remove it**. This flag disables the statistics collection that Prometheus requires. By default, stats logging is enabled - keep it that way.

**To fix:**

1. Check your `docker-compose.yml` command section
2. Remove `--disable-log-stats` if present
3. Restart the vLLM container: `docker compose restart vllm`
4. Verify metrics are now available: `curl http://localhost:8000/metrics`

### Prometheus Target is DOWN

**Symptoms:**

- In Prometheus UI → **Status → Targets** → `job="vllm"` shows **DOWN**

**Verify target in prometheus.yaml:**

```yaml
scrape_configs:
  - job_name: "vllm"
    static_configs:
      - targets: ["vllm-server:8000"] # or <VLLM_HOST>:8000
```

If Prometheus and vLLM are not on the same Docker network, `vllm-server` will not resolve. Use the host IP instead.

**Common errors:**

| Error Message               | Cause                     | Solution                            |
| --------------------------- | ------------------------- | ----------------------------------- |
| `no such host`              | Hostname doesn't resolve  | Use IP address or correct hostname  |
| `connection refused`        | Port closed or wrong port | Verify vLLM is running on port 8000 |
| `context deadline exceeded` | Firewall/network blocking | Check firewall rules                |

### Metrics Are Empty or Not Increasing

**Symptoms:**

- `up{job="vllm"}` returns `1` but `vllm:*` metrics stay `0`

**Checks:**

- Have you sent any requests to vLLM?
- Re-run queries after sending test traffic

**Fixes:**

Send some test traffic (see validation section above).

Lower scrape interval if needed (default 15s may delay updates):

```yaml
global:
  scrape_interval: 5s
```

---

## Useful Commands

### Container Management

```bash
docker compose up -d
docker compose down
docker logs -f vllm-server
docker logs -f prometheus
```

### GPU Debugging

```bash
nvidia-smi
docker exec -it vllm-server nvidia-smi
```

### Test Endpoints

```bash
curl http://<host>:8000/v1/models
curl http://<host>:8000/metrics
```

### PromQL Quick Checks

```promql
up{job="vllm"}
vllm:request_success_total
vllm:generation_tokens_total
```

---

## Next Steps

### For Development Environments

- ✅ vLLM metrics now visible in Prometheus
- **Send inference requests** and monitor performance
- **Create dashboards** using PromQL queries

### Additional Resources

- **vLLM Documentation**: [https://docs.vllm.ai](https://docs.vllm.ai)
- **Prometheus Documentation**: [https://prometheus.io/docs/](https://prometheus.io/docs/)

---

[← Back to Advanced Setup](../ADVANCED_SETUP.md)
