# Docker Compose Profiles

This document describes the available Docker Compose profiles and how to integrate them with components you may already have (Prometheus, OpenTelemetry Collector, VictoriaMetrics).

## Overview

Docker Compose profiles allow you to selectively run only the services you need.

All services in `docker-compose.yaml` are assigned to one or more profiles, so you **must** specify a profile when starting the stack:

```bash
docker compose --profile <profile-name> up -d
```

```bash
docker compose --profile <profile-name> down
```

**Prometheus:**

-   Prometheus uses the shared prometheus.yaml configuration. For some profiles you will need to edit this file to match your environment (remote_write target, scrape targets, etc.), more info in [prometheus.yaml](/docker-compose/prometheus.yaml).

**VictoriaMetrics Integration:**

-   Prometheus automatically remote_writes all metrics to VictoriaMetrics for long-term retention (12 months by default)
-   VictoriaMetrics provides a Prometheus-compatible query API on port 8428

## Available Profiles

### `full`

Runs the complete observability stack:

-   OpenTelemetry Collector (otel-collector)
-   Prometheus (prometheus)
-   VictoriaMetrics (victoriametrics)

**Usage:**

```bash
cd docker-compose
docker compose --profile full up -d
```

**What this profile does**

-   Applications send OTLP telemetry to otel-collector (4317/4318).
-   otel-collector exposes Prometheus metrics on :8889 (and internal metrics on :8888).
-   Prometheus scrapes otel-collector.
-   Prometheus remote_writes all metrics to VictoriaMetrics for long-term storage.

**Prometheus config (prometheus.yaml)**

-   remote_write block: leave enabled (points to internal victoriametrics).
-   scrape_configs:
    -   Keep the otel-collector jobs as-is.
    -   Optionally add more jobs for other exporters/services.

**Verification**

-   Prometheus UI: http://localhost:9090
-   VictoriaMetrics health: http://localhost:8428/health
-   Collector health: http://localhost:13133/health/status

---

### `no-prometheus`

Use this profile when you already have Prometheus and only want us to provide:

-   OpenTelemetry Collector (otel-collector)
-   VictoriaMetrics (victoriametrics)

**Usage:**

```bash
cd docker-compose
docker compose --profile no-prometheus up -d
```

**What this profile does**

-   Starts otel-collector (OTLP in, Prometheus metrics out).
-   Starts VictoriaMetrics for long-term storage.
-   Does **not** start Prometheus; you use your own.

#### Customer Configuration Required

1. **Scrape the collector**

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

    - `otel-collector` if your Prometheus runs on the same Docker network,
    - or the host/IP where the collector is exposed (e.g. localhost:8889).

2. **Configure Remote Write to VictoriaMetrics**

    - Your existing Prometheus instance should be configured to remote_write metrics to VictoriaMetrics
    - Add the following remote_write configuration to your Prometheus `prometheus.yml`:

    ```yaml
    remote_write:
        - url: http://<victoriametrics-host>:8428/api/v1/write
    ```

    Replace `<victoriametrics-host>` with:

    - `victoriametrics` if on the same Docker network,
    - or the host/IP where VM is exposed (e.g. `localhost:8428`).

3. **Network Configuration**

    - Ensure the OpenTelemetry Collector can be reached by your Prometheus instance
    - Ensure VictoriaMetrics can be reached by your Prometheus instance for remote_write
    - If using Docker networks, ensure all services are on the same network or configure network connectivity
    - If services are on different hosts, ensure firewall rules allow access to required ports

4. **Verify Connectivity**
    - Test that your Prometheus can reach the collector:
        ```bash
        curl http://<collector-host>:8889/metrics
        curl http://<collector-host>:8888/metrics
        ```

---

### `no-vm`

Use this profile when you already have a VictoriaMetrics instance and want us to provide:

-   OpenTelemetry Collector (otel-collector)
-   Prometheus (prometheus)

**What this profile does**

-   Starts otel-collector.
-   Starts Prometheus.
-   Does **not** start VictoriaMetrics; you use your own.

**Usage:**

```bash
cd docker-compose
docker compose --profile no-vm up -d
```

#### Customer Configuration Required

1. **Configure Remote Write to VictoriaMetrics**

    - In [Prometheus.yaml](./prometheus.yaml) configure remote_write metrics to your VictoriaMetrics address

    ```yaml
    remote_write:
        - url: http://<victoriametrics-host>:8428/api/v1/write
    ```

    Replace `<victoriametrics-host>` with:

    - The hostname or IP address where VictoriaMetrics is running
    - If you do not want long-term storage, you can comment out / remove the remote_write block entirely.

2. **Network Configuration**

    - Ensure Prometheus can reach your existing VM
    - If using Docker networks, ensure Prometheus can access the VM's network

3. **Verify VictoriaMetrics Endpoint**

    - Test that Prometheus can reach your VM:
        ````bash
        curl http://<your-VM-host>:8428/api/v1/write
        ``` sending traces to the correct collector endpoint
        ````

---

### `vm-only`

Use this profile when you only want VictoriaMetrics and will use your own Prometheus / collectors.

Services included:

-   victoriametrics

Services excluded:

-   otel-collector
-   prometheus

**Usage:**

```bash
cd docker-compose
docker compose --profile vm-only up -d
```

### Customer configuration required (your Prometheus)

-   In [Prometheus.yaml](./prometheus.yaml) configure remote_write metrics to your VictoriaMetrics address

    ```yaml
    remote_write:
        - url: http://<victoriametrics-host>:8428/api/v1/write
    ```

**Verification**

curl http://localhost:8428/health

> Note: prometheus.yaml in this repo is an example only and is not used in this profile.

---

### `no-collector`

Use this profile when you already have an OpenTelemetry Collector running in your environment.

**Services included:**

-   Prometheus
-   VictoriaMetrics (long-term storage)

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

    - Update [prometheus.yaml](./prometheus.yaml) to scrape from your existing collector instead of the containerized one
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

**VictoriaMetrics Integration:**

-   Prometheus automatically remote_writes all metrics to VictoriaMetrics for long-term retention

---

## `prom-only`

Use this profile when you only want Prometheus and no collector / no VictoriaMetrics.

**Services included:**

-   prometheus-standalone

Services excluded:

-   otel-collector
-   victoriametrics

**Usage:**

```bash
cd docker-compose
docker compose --profile prom-only up -d
```

#### Customer configuration required

1. **Update, set the correct URL:**

```bash
remote_write:
-   url: http://<victoriametrics-host>:8428/api/v1/write
```

2. **Replace scrape targets**

Since our `otel-collector` is not running in this profile, you must point Prometheus at your own exporters:

    ```bash
    scrape_configs:
    -   job_name: "your-services"
        static_configs:
        -   targets:
            -   "your-app:9100"
            -   "another-exporter:9200"
    ```

3. **Verify**

```bash
curl http://localhost:9090/-/ready
```

## Profile Summary Table

| Profile         | Collector | Prometheus | VictoriaMetrics |
| --------------- | --------- | ---------- | --------------- |
| `full`          | ✅        | ✅         | ✅              |
| `no-prometheus` | ✅        | ❌         | ✅              |
| `no-vm`         | ✅        | ✅         | ❌              |
| `vm-only`       | ❌        | ❌         | ✅              |
| `no-collector`  | ❌        | ✅         | ✅              |
| `prom-only`     | ❌        | ✅         | ❌              |

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
-   Data volumes are preserved across container restarts for services that use them (Prometheus, VictoriaMetrics)
-   **VictoriaMetrics Configuration:**
    -   VictoriaMetrics is configured with 12 months retention by default (`-retentionPeriod=12`)
    -   Prometheus automatically remote_writes all scraped metrics to VictoriaMetrics
    -   VictoriaMetrics provides a Prometheus-compatible query API, making it a drop-in replacement for Prometheus queries
    -   This setup enables long-term metric retention without changing Prometheus scraping behavior
