# Getting Started

This application runs primarily off of the docker compose. To start run

```bash
docker compose up -d
```

### Testing Locally without LLM via Otel CLI

##### Mac OS Installation

```bash
brew install equinix-labs/otel-cli/otel-cli
```

##### Linux Installation

```bash
curl -L https://github.com/equinix-labs/otel-cli/releases/latest/download/otel-cli-linux-amd64 -o /usr/local/bin/otel-cli
chmod +x /usr/local/bin/otel-cli

```

##### Windows Installation

Download from the [Github Releases Page](https://github.com/equinix-labs/otel-cli/releases)

#### Send a Test Metric using Otel CLI

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

Run `docker compose logs -f otel-collector`

Expected Output:

```nginx
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

#### Verify in the Collector Metrics

Visit `http://localhost:8889/metrics`

Search for test metric
`llm_calls_total`

Expected Output

```bash
# TYPE llm_calls_total counter
llm_calls_total{component="demo",env="dev",job="otel-test",service="llm-collector",service_name="otel-test",span_kind="SPAN_KIND_CLIENT",span_name="demo-span",status_code="STATUS_CODE_UNSET"} 1 1761689870268
```

#### Verify Prometheus

Visit `http://localhost:9090`

Run a query:

```nginx
llm_calls_total
```

Expected Output:

```nginx
llm_calls_total{component="demo", env="dev", exported_job="otel-test", instance="otel-collector:8889", job="otel-collector", service="llm-collector", service_name="otel-test", span_kind="SPAN_KIND_CLIENT", span_name="demo-span", status_code="STATUS_CODE_UNSET"}
```
