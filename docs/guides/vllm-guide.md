# vLLM Observability Integration

[← Back to Advanced Setup](../ADVANCED_SETUP.md)

This guide shows how to monitor vLLM inference servers by exposing and scraping vLLM's built-in Prometheus metrics.

## Overview

vLLM provides built-in Prometheus metrics at its `/metrics` endpoint, making it straightforward to integrate with observability systems. This guide covers two deployment approaches:

**Option 1: Standalone Setup** - Deploy vLLM with a dedicated Prometheus instance (ideal for development or isolated deployments)

**Option 2: Integration with Observability Pipeline** - Add vLLM as a scrape target to an existing Prometheus deployment (recommended for production)

### Key vLLM Metrics

vLLM exposes metrics for inference performance monitoring:

```
vllm:time_to_first_token_seconds        # Latency to first token
vllm:time_per_output_token_seconds      # Per-token generation time
vllm:e2e_request_latency_seconds        # End-to-end request latency
vllm:request_success_total              # Successful requests
vllm:generation_tokens_total            # Total tokens generated
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

- Docker (20.10+)
- Docker Compose (2.0+)

### Network Requirements

- **Port 8000**: vLLM API and metrics endpoint
- **Port 9090**: Prometheus UI (if using standalone setup)

---

## Option 1: Standalone Setup

Deploy vLLM with a dedicated Prometheus instance for quick setup or isolated environments.

### Step 1: Configure vLLM

Create a `.env` file with vLLM configuration:

```bash
# vLLM Image Version
VLLM_IMAGE_VERSION=v0.6.3.post1

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

**Configuration Notes:**

| Variable                      | Description                       | Common Values               |
| ----------------------------- | --------------------------------- | --------------------------- |
| `VLLM_MODEL`                  | HuggingFace model ID              | Any compatible model        |
| `VLLM_MAX_MODEL_LEN`          | Maximum context length            | 1024, 2048, 4096            |
| `VLLM_GPU_MEMORY_UTILIZATION` | GPU memory allocation (0.0 - 1.0) | 0.9 (recommended)           |
| `VLLM_DTYPE`                  | Model precision                   | `half`, `bfloat16`, `float` |

**Optional:** For private HuggingFace models, add:

```bash
HUGGINGFACE_HUB_TOKEN=your_token_here
```

### Step 2: Deploy vLLM

Create `docker-compose.yml`:

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

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus
    ports:
      - "9090:9090"
    restart: unless-stopped

volumes:
  prometheus_data:
```

Create `prometheus.yml`:

```yaml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: "vllm"
    static_configs:
      - targets: ["vllm-server:8000"]
```

**Start the services:**

```bash
docker compose up -d
```

### Step 3: Verify Deployment

**Check container status:**

```bash
docker compose ps
# Expected: Both vllm-server and prometheus showing "Up"
```

**Verify GPU access:**

```bash
docker exec -it vllm-server nvidia-smi
```

**Check vLLM logs:**

```bash
docker logs -f vllm-server
# Look for: "Uvicorn running on http://0.0.0.0:8000"
```

**Test vLLM API:**

```bash
curl http://localhost:8000/v1/models
```

**Test metrics endpoint:**

```bash
curl http://localhost:8000/metrics | grep vllm
```

**Verify Prometheus scraping:**

Open `http://localhost:9090/targets` and confirm:

- Job: `vllm`
- State: **UP**

---

## Option 2: Integration with Observability Pipeline

Add vLLM monitoring to an existing Prometheus deployment from the main observability pipeline.

### Prerequisites

Ensure the observability pipeline is already deployed. See:

- [Quick Start](../quick-start.md) for initial deployment
- [Deployment Guide](deployment-guide.md) for detailed setup instructions
- [Deployment Profiles](deployment-profiles.md) for profile selection

### Step 1: Deploy vLLM

Use the same vLLM configuration from Option 1, but deploy only the vLLM service:

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
```

**Start vLLM:**

```bash
docker compose up -d
```

### Step 2: Add vLLM to Prometheus Configuration

Edit your existing `docker-compose/prometheus.yaml` to add vLLM as a scrape target:

```yaml
global:
  scrape_interval: 10s

scrape_configs:
  - job_name: "otel-collector"
    static_configs:
      - targets: ["otel-collector:8889"]

  - job_name: "otel-collector-internal"
    static_configs:
      - targets: ["otel-collector:8888"]

  # Add vLLM scrape target
  - job_name: "vllm"
    static_configs:
      - targets: ["<vllm-host>:8000"] # Replace with vLLM hostname or IP
```

**Network Considerations:**

- **Same Docker network**: Use container name (e.g., `vllm-server:8000`)
- **Different host**: Use hostname or IP (e.g., `192.168.1.100:8000`)
- **Ensure firewall rules** allow Prometheus to reach vLLM on port 8000

**Restart Prometheus to apply changes:**

```bash
cd docker-compose
docker compose restart prometheus
```

### Step 3: Verify Integration

**Check Prometheus targets:**

```bash
# For API Key auth (default):
curl -H "X-API-Key: placeholder_api_key" http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="vllm")'

# For Basic Auth:
curl -u user:secretpassword http://localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="vllm")'
```

**Expected:** `health: "up"` for the vLLM target

**Query vLLM metrics:**

```bash
# For API Key auth (default):
curl -H "X-API-Key: placeholder_api_key" 'http://localhost:9090/api/v1/query?query=up{job="vllm"}' | jq

# For Basic Auth:
curl -u user:secretpassword 'http://localhost:9090/api/v1/query?query=up{job="vllm"}' | jq
```

**Expected:** `value: [<timestamp>, "1"]`

For more information on authentication, see the [Security Guide](security.md).

---

## Validation

After deployment, verify the complete monitoring stack:

### 1. Send Test Request to vLLM

```bash
curl http://localhost:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen2.5-0.5B-Instruct",
    "messages": [
      {"role": "user", "content": "Say hello in one sentence."}
    ],
    "max_tokens": 10
  }'
```

### 2. Check Metrics are Exposed

```bash
curl http://localhost:8000/metrics | grep -E "(vllm:request_success|vllm:generation_tokens)"
```

**Expected output:**

```
vllm:request_success_total{...} 1
vllm:generation_tokens_total{...} 10
```

### 3. Query Metrics in Prometheus

Open Prometheus UI (`http://localhost:9090`) or use the API:

```bash
# Standalone setup:
curl 'http://localhost:9090/api/v1/query?query=vllm:request_success_total' | jq

# Integrated with observability pipeline (API Key):
curl -H "X-API-Key: placeholder_api_key" 'http://localhost:9090/api/v1/query?query=vllm:request_success_total' | jq

# Integrated with observability pipeline (Basic Auth):
curl -u user:secretpassword 'http://localhost:9090/api/v1/query?query=vllm:request_success_total' | jq
```

---

## Useful PromQL Queries

Query vLLM metrics in Prometheus for monitoring and dashboards:

### Request Rate

```promql
# Requests per second
rate(vllm:request_success_total[5m])

# Requests per second by model
rate(vllm:request_success_total[5m]) by (model_name)
```

### Latency Percentiles

```promql
# p95 time to first token
histogram_quantile(0.95, rate(vllm:time_to_first_token_seconds_bucket[5m]))

# p99 end-to-end latency
histogram_quantile(0.99, rate(vllm:e2e_request_latency_seconds_bucket[5m]))

# Median time per output token
histogram_quantile(0.50, rate(vllm:time_per_output_token_seconds_bucket[5m]))
```

### Throughput

```promql
# Tokens generated per second
rate(vllm:generation_tokens_total[5m])

# Average tokens per request
rate(vllm:generation_tokens_total[5m]) / rate(vllm:request_success_total[5m])
```

### Error Rate

```promql
# Failed requests per second
rate(vllm:request_failure_total[5m])

# Error percentage
(rate(vllm:request_failure_total[5m]) / rate(vllm:request_success_total[5m])) * 100
```

For more information on Prometheus queries and configuration, see the [Configuration Reference](configuration-reference.md#prometheus-configuration).

---

## Troubleshooting

### vLLM Container Not Starting

**Symptoms:**

- Container exits immediately after starting
- `docker ps` doesn't show `vllm-server`

**Check logs:**

```bash
docker logs vllm-server
```

**Common causes:**

| Issue                   | Solution                                                  |
| ----------------------- | --------------------------------------------------------- |
| Invalid model name      | Verify `VLLM_MODEL` exists on HuggingFace                 |
| Wrong dtype for model   | Try `half`, `bfloat16`, or `float` in `VLLM_DTYPE`        |
| GPU not available       | Run `nvidia-smi` and check NVIDIA Container Toolkit       |
| Insufficient GPU memory | Reduce `VLLM_GPU_MEMORY_UTILIZATION` or use smaller model |

### GPU Not Detected

**Symptoms:**

- Logs show CUDA errors
- vLLM falls back to CPU

**Verify GPU access:**

```bash
# On host
nvidia-smi

# Inside container
docker exec -it vllm-server nvidia-smi
```

**Fixes:**

1. Install/update NVIDIA driver
2. Install NVIDIA Container Toolkit:
   ```bash
   # Ubuntu/Debian
   curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
   curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
     sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
     sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
   sudo apt-get update
   sudo apt-get install -y nvidia-container-toolkit
   sudo systemctl restart docker
   ```
3. Verify `deploy.resources.reservations.devices` in docker-compose.yml

### Metrics Endpoint Not Reachable

**Symptoms:**

- `curl http://localhost:8000/metrics` fails
- Prometheus target shows DOWN

**Checks:**

```bash
# From vLLM host
curl http://localhost:8000/metrics

# From Prometheus host
curl http://<vllm-host>:8000/metrics
```

**Fixes:**

| Issue                 | Solution                                    |
| --------------------- | ------------------------------------------- |
| Container not running | Check `docker ps` and container logs        |
| Wrong port            | Verify `VLLM_PORT` in `.env`                |
| Firewall blocking     | Allow port 8000 in firewall/security groups |
| Wrong hostname        | Update Prometheus config with correct host  |

### Prometheus Target DOWN

**Symptoms:**

- In Prometheus UI: Status → Targets → `job="vllm"` shows **DOWN**

**Verify target configuration:**

```yaml
scrape_configs:
  - job_name: "vllm"
    static_configs:
      - targets: ["<vllm-host>:8000"] # Check this is correct
```

**Common errors:**

| Error Message               | Cause                     | Solution                            |
| --------------------------- | ------------------------- | ----------------------------------- |
| `no such host`              | Hostname doesn't resolve  | Use IP address or correct hostname  |
| `connection refused`        | Port closed or wrong port | Verify vLLM is running on port 8000 |
| `context deadline exceeded` | Firewall/network blocking | Check firewall rules                |

**Network debugging:**

```bash
# From Prometheus container
docker exec prometheus wget -O- http://<vllm-host>:8000/metrics
```

### Metrics Not Increasing

**Symptoms:**

- `up{job="vllm"}` returns `1` but request counters stay at 0

**Verify:**

1. Have you sent requests to vLLM? See [Validation](#validation) section
2. Check metrics are being generated:
   ```bash
   curl http://localhost:8000/metrics | grep vllm:request_success_total
   ```
3. Wait for next scrape (default: 15 seconds)

**Increase scrape frequency** (if needed):

```yaml
global:
  scrape_interval: 5s # Reduce from 15s
```

---

## Next Steps

### For Development Environments

- ✅ vLLM metrics now visible in Prometheus
- **Send inference requests** and monitor performance
- **Create dashboards** using the PromQL queries above

### For Production Environments

- **Secure your deployment**: See [Security Guide](security.md) for authentication and network security
- **Configure alerts**: Set up alerting for latency, error rates, and throughput
- **Long-term storage**: If not already using VictoriaMetrics, see [Architecture Guide](architecture.md#why-victoriametrics)
- **Performance tuning**: Adjust vLLM and Prometheus settings based on load

### Additional Resources

- **vLLM Documentation**: [https://docs.vllm.ai](https://docs.vllm.ai)
- **Configuration tuning**: [Configuration Reference](configuration-reference.md)
- **Production best practices**: [Production Guide](production-guide.md)
- **Prometheus configuration**: [Prometheus Documentation](https://prometheus.io/docs/)

---

[← Back to Advanced Setup](../ADVANCED_SETUP.md)
