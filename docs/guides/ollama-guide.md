# Ollama Observability Setup Guide

## Overview

This document provides a practical guide for instrumenting a FastAPI service that uses Ollama, exporting telemetry via OpenTelemetry (OTLP) to an OTel Collector, and exposing metrics to Prometheus.

It focuses on the minimum required setup.

By the end of this guide, you will have:
- A FastAPI service calling Ollama for LLM inference
- Traces and metrics exported via OTLP to an OTel Collector
- An OTel Collector exposing a Prometheus /metrics endpoint
- A Prometheus instance scraping these metrics
- A validated end-to-end observability pipeline

## Intended Audience 

This guide targets:
- Backend / Platform / DevOps engineers
- ML / MLOps engineers integrating Ollama in services

It assumes familiarity with Python, FastAPI, Docker, and Prometheus.

## Architecture Overview 

(Add the image here)

- FastAPI app uses:
    - `opentelemetry-sdk for traces + metrics`
    - `opentelemetry-instrumentation-fastapi`
    - `opentelemetry-instrumentation-ollama`
    - `opentelemetry-instrumentation-system-metrics`
- Telemetry is exported via OTLP gRPC to the OTel Collector.
- OTel Collector exposes a Prometheus /metrics endpoint.
- Prometheus scrapes metrics from the Collector 

### Example Metrics 

- `llm_process_cpu_utilization_ratio`
- `llm_system_disk_time_seconds_total`
- `llm_system_network_packets_total`
- `llm_gen_ai_client_token_usage_bucket`

### Prerequisites

System requirements:
- Docker & Docker Compose
- Ollama installed and running:
    - On host: ollama serve
    - Or as a separate container reachable via OLLAMA_URL

Network Requirements:
- The FastAPI container can reach:
    - `otel-collector:4317`
    - OLLAMA_URL (host or container)
- Prometheus must be able to reach:
    - `otel-collector:8889`
    - **Note**: Ports can be customized in .env and docker-compose.yml.

File Requirements:
- requirements.txt
- Dockerfile
- docker-compose.yml
- otel-collector-config.yaml
- prometheus.yml
- .env (template for service + Ollama + OTEL config)

Application Code Requirements:
- telemetry.py (OTEL setup)
- main.py (FastAPI app, endpoints)

These files are referenced in later sections.

## Application Configuration 

### `.env` variables

```bash 
# OpenTelemetry
OTEL_SERVICE_NAME=ollama-fastapi
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4317

# Ollama
OLLAMA_URL=http://host.docker.internal:11434
OLLAMA_MODEL=llama3.2
```

- `OTEL_SERVICE_NAME` — service name used in OTEL.
- `OTEL_EXPORTER_OTLP_ENDPOINT` — OTLP endpoint (Collector).
- `OLLAMA_URL` — URL of the Ollama server (host or container).
- `OLLAMA_MODEL` — model name to use.

## Telemetry Setup in FastAPI

### Dependencies (requirements.txt)

```txt
# Web Framework
fastapi>=0.111.0
uvicorn[standard]>=0.29.0

# Configuration
pydantic>=2.11.7
pydantic-settings>=2.9.1

# Ollama client
ollama>=0.3.0

# OpenTelemetry Core
opentelemetry-api>=1.38.0
opentelemetry-sdk>=1.38.0

# OTLP Exporter (to Collector)
opentelemetry-exporter-otlp-proto-grpc>=1.38.0

# Instrumentation
opentelemetry-instrumentation-fastapi>=0.59b0
opentelemetry-instrumentation-system-metrics>=0.59b0
opentelemetry-instrumentation-ollama>=0.47.5
```

### Telemetry Initialization (telemetry.py)

```python 
import os

from opentelemetry import metrics, trace
from opentelemetry.exporter.otlp.proto.grpc.metric_exporter import OTLPMetricExporter
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.ollama import OllamaInstrumentor
from opentelemetry.instrumentation.system_metrics import SystemMetricsInstrumentor
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor


def setup_telemetry() -> None:
endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT", "http://otel-collector:4317")
service_name = os.getenv("OTEL_SERVICE_NAME", "ollama-fastapi")

os.environ["OTEL_EXPORTER_OTLP_ENDPOINT"] = endpoint
os.environ["OTEL_SERVICE_NAME"] = service_name
os.environ["OTEL_METRICS_EXPORTER"] = "otlp"

# Traces
tracer_provider = TracerProvider()
trace.set_tracer_provider(tracer_provider)
span_exporter = OTLPSpanExporter(endpoint=endpoint, insecure=True)
tracer_provider.add_span_processor(BatchSpanProcessor(span_exporter))

# Metrics
metric_exporter = OTLPMetricExporter(endpoint=endpoint, insecure=True)
reader = PeriodicExportingMetricReader(
metric_exporter,
export_interval_millis=5000,
)
meter_provider = MeterProvider(metric_readers=[reader])
metrics.set_meter_provider(meter_provider)

# System metrics
SystemMetricsInstrumentor().instrument(meter_provider=meter_provider)

# Ollama metrics / traces
OllamaInstrumentor().instrument()
```

### FastAPI App + Instrumentation (main.py)

```python 
import os
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.ollama import OllamaInstrumentor
from pydantic import BaseModel
from ollama import Client

from telemetry import setup_telemetry


class AskRequest(BaseModel):
question: str


class AskResponse(BaseModel):
answer: str

@asynccontextmanager
async def lifespan(app: FastAPI):
setup_telemetry()
yield
OllamaInstrumentor().uninstrument()


app = FastAPI(lifespan=lifespan)

# IMPORTANT: instrument FastAPI AFTER app is created
FastAPIInstrumentor.instrument_app(app)


@app.post(
"/v1/ask",
response_model=AskResponse,
)
def ask_endpoint(request: AskRequest):
client = Client(host=os.getenv("OLLAMA_URL", "http://ollama:11434"))
model = os.getenv("OLLAMA_MODEL", "llama3.2")

res = client.chat(
model=model,
messages=[{"role": "user", "content": request.question}],
options={"temperature": 0.2},
)
return AskResponse(answer=res["message"]["content"])
```

## Infrastructure Setup

### Dockerfile

```bash 
FROM python:3.12-slim

WORKDIR /app
ENV PYTHONPATH=/app/src

RUN apt-get update && apt-get install -y build-essential curl && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY requirements.txt ./
RUN pip install --upgrade pip && pip install -r requirements.txt

COPY . .
EXPOSE 8000
# Create a simple entrypoint script inline or copy one
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### Prometheus Configuration

Create `prometheus.yml`

```bash
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'otel-collector'
    static_configs:
      - targets: ['otel-collector:8889']
```

### OTel Collector Configuration

Create `otel-collector-config.yaml`. This pipeline receives data via OTLP and exports it to Prometheus.

```bash 
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317

exporters:
  prometheus:
    endpoint: "0.0.0.0:8889"
    namespace: "ollama"
  logging:
    loglevel: info

processors:
  batch: {}

service:
  pipelines:
    metrics:
      receivers: [otlp]
      processors: [batch]
      exporters: [prometheus, logging]
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [logging]
```

### Docker Compose

```bash
services:
  otel-llm-api:
    build: .
    container_name: otel-llm-api
    env_file: [.env]
    ports: ["8002:8000"]
    extra_hosts: ["host.docker.internal:host-gateway"]
    depends_on: [otel-collector]

  otel-collector:
    image: otel/opentelemetry-collector:latest
    container_name: otel-collector
    volumes: ["./otel-collector-config.yaml:/etc/otelcol/config.yaml"]
    ports: ["4317:4317", "8889:8889"]
    restart: unless-stopped

  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    volumes: ["./prometheus.yml:/etc/prometheus/prometheus.yml"]
    ports: ["9090:9090"]
    restart: unless-stopped
```

## End-to-End Validation

### Start the Stack

```bash
docker compose up -d
```

### Generate Traffic

```bash
curl http://localhost:8002/v1/ask \ -H "Content-Type: application/json" \ -d '{"question":"Explain quantum mechanics in 5 words."}'
```

You should get a JSON response:

```bash
{ "answer": "..." }
```

### Verify OTel Collector

Check if metrics are being exposed by the Collector.

```bash
curl http://localhost:8889/metrics | head -n 20
```

Success criteria: Output should look like Prometheus metrics (e.g., `# HELP, # TYPE, ollama_request_duration`, etc.)

### Verify Prometheus

- Open: `http://localhost:9090`
- Navigate to Status -> Targets
- Ensure otel-collector is UP

*Basic PromQL Checks*

In Prometheus Graph UI, run: `up{job="otel-collector"}`

You should get 1.

After some traffic, you can also explore metrics coming from the OTEL SDK and system metrics, query:

```bash 
llm_process_cpu_utilization_ratio
llm_system_disk_time_seconds_total
llm_system_network_packets_total
llm_gen_ai_client_token_usage_bucket
```

## Troubleshooting

### FastAPI Container Not Running

Symptoms:
- `docker ps does not show otel-llm-api`
- `docker compose up -d fails`

Checks:

```bash 
docker compose up -d
docker ps
docker logs -f otel-llm-api
```

Common causes:
- Import errors in `main.py` or `telemetry.py`
- Missing or invalid `.env` values
- Ollama not reachable at `OLLAMA_URL`

### Collector Not Receiving Telemetry

Symptoms:
- No metrics visible at `http://localhost:8889/metrics`

Checks:
- `OTEL_EXPORTER_OTLP_ENDPOINT` in `.env` points to `http://otel-collector:4317`
- `'otel-collector'` is resolvable inside the `otel-llm-api` container.
- Collector logs: `docker logs -f otel-collector`

### Prometheus Target is DOWN

Symptoms:
- `job="otel-collector"` shows DOWN in Prometheus Targets

Check the target in `prometheus.yml`:

```bash
- targets:
    - 'otel-collector:8889'
```
- Collector running and 8889 exposed.
- On host:  `curl http://localhost:8889/metrics`

### Metrics Not Changing

Symptoms:

- `up{job="otel-collector"}` is 1, but metrics stay flat

Checks:
- Are you sending traffic to `/v1/ask`?
- Wait at least one scrape interval (15s by default).
- Optionally lower scrape interval:

```bash
global:
  scrape_interval: 5s
```


