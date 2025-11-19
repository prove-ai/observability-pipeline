# Docker Compose Profiles

This document describes the available Docker Compose profiles for customers who already have portions of the observability stack set up.

## Overview

Docker Compose profiles allow you to selectively run only the services you need. This is useful when you already have some components of the observability stack running in your environment.

## Available Profiles

### `full` (Default)

Runs the complete observability stack:

-   OpenTelemetry Collector
-   Prometheus
-   PostgreSQL
-   Grafana

**Usage:**

```bash
cd docker-compose
docker compose --profile full up -d
```

**Note:** If no profile is specified, you must use the `--profile full` flag to start all services since all services are assigned to profiles.

---

### `no-prometheus`

Use this profile when you already have Prometheus running in your environment.

**Services included:**

-   OpenTelemetry Collector
-   PostgreSQL
-   Grafana

**Services excluded:**

-   Prometheus

**Usage:**

```bash
cd docker-compose
docker compose --profile no-prometheus up -d
```

#### Customer Configuration Required

1. **Update Prometheus Configuration**

    - Your existing Prometheus instance needs to scrape metrics from the OpenTelemetry Collector
    - Add the following scrape configuration to your Prometheus `prometheus.yml`:

    ```yaml
    scrape_configs:
        - job_name: "otel-collector"
          static_configs:
              - targets: ["<collector-host>:8889"]
        - job_name: "otel-collector-internal"
          static_configs:
              - targets: ["<collector-host>:8888"]
    ```

    Replace `<collector-host>` with:

    - The hostname or IP address where the collector is running
    - If running on the same Docker network, use the container name: `otel-collector:8889`
    - If running on the host network, use `localhost:8889` or the host's IP address

2. **Update Grafana Data Source**

    - Update the Grafana datasource configuration to point to your existing Prometheus instance
    - Edit `grafana/provisioning/datasources/prometheus.yml` and change the URL:

    ```yaml
    url: http://<your-prometheus-host>:9090
    ```

    Replace `<your-prometheus-host>` with:

    - The hostname or IP address of your Prometheus instance
    - If Prometheus is on the same Docker network, use the service name
    - If Prometheus is external, use the full URL (e.g., `http://prometheus.example.com:9090`)

3. **Network Configuration**

    - Ensure the OpenTelemetry Collector can be reached by your Prometheus instance
    - If using Docker networks, ensure both services are on the same network or configure network connectivity
    - If the collector is on a different host, ensure firewall rules allow access to ports 8888 and 8889

4. **Verify Connectivity**
    - Test that your Prometheus can reach the collector:
        ```bash
        curl http://<collector-host>:8889/metrics
        curl http://<collector-host>:8888/metrics
        ```

---

### `no-collector`

Use this profile when you already have an OpenTelemetry Collector running in your environment.

**Services included:**

-   Prometheus
-   PostgreSQL
-   Grafana

**Services excluded:**

-   OpenTelemetry Collector

**Usage:**

```bash
cd docker-compose
docker compose --profile no-collector up -d
```

#### Customer Configuration Required

1. **Configure Your Existing Collector**

    - Your existing OpenTelemetry Collector must export metrics in Prometheus format
    - Ensure your collector has a Prometheus exporter configured and exposes metrics on an endpoint (typically port 8889)
    - The collector should expose metrics at an endpoint like `http://0.0.0.0:8889/metrics`

2. **Update Prometheus Configuration**

    - Update `prometheus.yaml` to scrape from your existing collector instead of the containerized one
    - Modify the scrape targets:

    ```yaml
    scrape_configs:
        - job_name: "otel-collector"
          static_configs:
              - targets: ["<your-collector-host>:8889"]
        - job_name: "otel-collector-internal"
          static_configs:
              - targets: ["<your-collector-host>:8888"]
    ```

    Replace `<your-collector-host>` with:

    - The hostname or IP address where your collector is running
    - If on the same Docker network, use the service/container name
    - If external, use the full hostname or IP address

3. **Network Configuration**

    - Ensure Prometheus can reach your existing collector
    - If your collector is on a different host, ensure network connectivity and firewall rules allow access
    - If using Docker networks, ensure Prometheus can access the collector's network

4. **Verify Collector Endpoint**

    - Test that Prometheus can reach your collector:
        ```bash
        curl http://<your-collector-host>:8889/metrics
        ```

5. **OTLP Receiver Configuration**
    - Ensure your existing collector is configured to receive OTLP traces on ports 4317 (gRPC) and/or 4318 (HTTP)
    - Verify your applications are sending traces to the correct collector endpoint

---

### `no-grafana`

Use this profile when you already have Grafana running in your environment.

**Services included:**

-   OpenTelemetry Collector
-   Prometheus

**Services excluded:**

-   PostgreSQL
-   Grafana

**Usage:**

```bash
cd docker-compose
docker compose --profile no-grafana up -d
```

#### Customer Configuration Required

1. **Add Prometheus Data Source in Grafana**

    - In your existing Grafana instance, add Prometheus as a data source
    - Go to Configuration → Data Sources → Add data source → Prometheus
    - Set the URL to: `http://<prometheus-host>:9090`

    Replace `<prometheus-host>` with:

    - The hostname or IP address where Prometheus is running
    - If Prometheus is on the same Docker network as Grafana, use the service name: `prometheus:9090`
    - If Prometheus is external, use the full URL (e.g., `http://prometheus.example.com:9090`)

2. **Network Configuration**

    - Ensure your Grafana instance can reach the Prometheus instance
    - If using Docker networks, ensure both services are on the same network or configure network connectivity
    - If Grafana is on a different host, ensure firewall rules allow access to port 9090

3. **Verify Connectivity**

    - Test that Grafana can reach Prometheus:
        ```bash
        curl http://<prometheus-host>:9090/api/v1/query?query=up
        ```

4. **Create Dashboards**
    - Import or create dashboards in your Grafana instance to visualize the metrics
    - Query for metrics like `llm_traces_span_metrics_calls_total` that are exported by the collector

---

## Profile Summary Table

| Profile         | Collector | Prometheus | Grafana | PostgreSQL |
| --------------- | --------- | ---------- | ------- | ---------- |
| `full`          | ✅        | ✅         | ✅      | ✅         |
| `no-prometheus` | ✅        | ❌         | ✅      | ✅         |
| `no-collector`  | ❌        | ✅         | ✅      | ✅         |
| `no-grafana`    | ✅        | ✅         | ❌      | ❌         |

## Combining Profiles

Docker Compose allows you to specify multiple profiles. However, the profiles in this setup are mutually exclusive. Use only one profile at a time:

```bash
# Correct usage
docker compose --profile no-prometheus up -d

# Incorrect - don't combine profiles
docker compose --profile no-prometheus --profile no-collector up -d
```

## Troubleshooting

### Services not starting

-   Ensure you've specified a profile: `docker compose --profile <profile-name> up -d`
-   Check that all required external services are running and accessible
-   Verify network connectivity between services

### Connection errors

-   Verify that external services are reachable from the Docker network
-   Check firewall rules and network configurations
-   Ensure service URLs and ports are correctly configured

### Metrics not appearing

-   Verify that scrape configurations point to the correct endpoints
-   Check that external services are exposing metrics on the expected ports
-   Ensure network connectivity between Prometheus and the metrics source

## Additional Notes

-   All services use the `observability` Docker network for internal communication
-   Port mappings are configured to avoid conflicts with common service ports
-   When using external services, ensure they are accessible from the Docker network or configure appropriate network bridges
-   Data volumes are preserved across container restarts for services that use them (Prometheus, PostgreSQL, Grafana)
