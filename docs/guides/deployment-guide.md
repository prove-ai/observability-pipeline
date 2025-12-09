# Deployment Guide

[← Back to Advanced Setup](../ADVANCED_SETUP.md)

This guide provides step-by-step instructions for deploying the Observability Pipeline using Docker Compose for development, testing, or single-server deployments.

---

## Prerequisites

| Requirement    | Minimum Version | Check Command            |
| -------------- | --------------- | ------------------------ |
| Docker         | 20.10+          | `docker --version`       |
| Docker Compose | 2.0+            | `docker compose version` |

---

## Available Profiles

Before deploying, choose your profile based on existing infrastructure:

| Profile         | Command                   | Services Deployed            | Use When                            |
| --------------- | ------------------------- | ---------------------------- | ----------------------------------- |
| `full`          | `--profile full`          | All 3 services               | Starting from scratch (recommended) |
| `no-prometheus` | `--profile no-prometheus` | Collector + VictoriaMetrics  | You have Prometheus                 |
| `no-vm`         | `--profile no-vm`         | Collector + Prometheus       | You have VictoriaMetrics            |
| `no-collector`  | `--profile no-collector`  | Prometheus + VictoriaMetrics | You have OTel Collector             |
| `vm-only`       | `--profile vm-only`       | VictoriaMetrics only         | You need storage only               |
| `prom-only`     | `--profile prom-only`     | Prometheus only              | You need scraper only               |

---

## Deployment

**Location:** All commands run from `docker-compose/` directory

### Command Reference

```bash
# Navigate to docker-compose directory
cd docker-compose

# Start with your chosen profile
docker compose --profile full up -d

# View logs from all services
docker compose logs -f

# View logs from specific service
docker compose logs -f otel-collector
docker compose logs -f prometheus
docker compose logs -f victoriametrics

# Check service status
docker compose ps

# Restart services
docker compose restart

# Stop services (keeps data)
docker compose down

# Stop and remove all data
docker compose down -v
```

### Common Docker Compose Variables

| Variable     | Set Via   | Example                  | Purpose                      |
| ------------ | --------- | ------------------------ | ---------------------------- |
| Profile      | CLI flag  | `--profile full`         | Choose which services to run |
| Project name | `-p` flag | `-p observability`       | Isolate multiple deployments |
| Config file  | `-f` flag | `-f custom-compose.yaml` | Use custom config            |

**Example: Custom project name**

```bash
docker compose -p my-observability --profile full up -d
```

---

## Post-Deployment Verification

After deploying, verify all services are working:

### 1. Check Container Status

```bash
cd docker-compose
docker compose ps
```

**Expected Output:**

```
NAME              STATUS    PORTS
otel-collector    Up        0.0.0.0:4317->4317/tcp, ...
prometheus        Up        0.0.0.0:9090->9090/tcp
victoriametrics   Up        0.0.0.0:8428->8428/tcp
```

### 2. Health Check Endpoints

| Service         | Endpoint                                    | Expected Response               |
| --------------- | ------------------------------------------- | ------------------------------- |
| OTel Collector  | `curl http://localhost:13133/health/status` | `{"status":"Server available"}` |
| Prometheus      | `curl http://localhost:9090/-/healthy`      | `Prometheus is Healthy.`        |
| VictoriaMetrics | `curl http://localhost:8428/health`         | `OK`                            |

### 3. Test Trace Ingestion

**Install otel-cli if not already installed:**

```bash
# macOS
brew install equinix-labs/otel-cli/otel-cli

# Linux
# See architecture.md for installation
```

**Send test trace:**

```bash
otel-cli span \
  --service "test-app" \
  --name "test-operation" \
  --endpoint http://localhost:4318/v1/traces \
  --protocol http/protobuf \
  --attrs "env=dev"
```

**Wait 15 seconds, then verify metrics appear:**

```bash
curl 'http://localhost:9090/api/v1/query?query=llm_traces_span_metrics_calls_total' | jq
```

---

## Complete Verification Checklist

Use this checklist after deployment:

### Infrastructure Checks

- [ ] All expected services are running (`docker compose ps`)
- [ ] No containers in "Restarting" or "Exited" state
- [ ] Correct deployment profile is active

### Health Checks

- [ ] OTel Collector health: `curl http://localhost:13133/health/status`
- [ ] Prometheus health: `curl http://localhost:9090/-/healthy`
- [ ] VictoriaMetrics health: `curl http://localhost:8428/health`

### Data Flow Checks

- [ ] Prometheus targets show "UP": `http://localhost:9090/targets`
- [ ] Collector is receiving traces (check logs)
- [ ] Metrics appear in Prometheus: `llm_traces_span_metrics_calls_total`
- [ ] Metrics are stored in VictoriaMetrics: `curl http://localhost:8428/api/v1/query?query=up`

### Network Checks

- [ ] Can send traces from external source to port 4317/4318
- [ ] Prometheus can scrape collector on port 8889
- [ ] VictoriaMetrics receives remote_write from Prometheus

---

## Troubleshooting

### Services Not Starting

**Check Docker is running:**

```bash
sudo systemctl status docker
```

**Check what profile is active:**

```bash
cd docker-compose
cat docker-compose.yaml | grep profiles
```

**Try restarting services:**

```bash
docker compose --profile full down
docker compose --profile full up -d
```

**Check logs for errors:**

```bash
docker compose logs --tail=100 otel-collector
```

### Metrics Not Appearing

**Check if collector is receiving traces:**

```bash
docker compose logs otel-collector | grep "Span #"
```

**Check if Prometheus is scraping:**

```bash
curl http://localhost:9090/api/v1/targets | jq
```

**Check if spanmetrics are exported:**

```bash
curl http://localhost:8889/metrics | grep llm_traces
```

**Check network connectivity:**

```bash
docker exec prometheus wget -O- http://otel-collector:8889/metrics
```

---

## Next Steps

### For Development Environments

1. ✅ Deployment complete
2. **Next:** [Send traces from your application](hybrid-cloud-integration.md)

### For Production Environments

1. ✅ Deployment complete
2. **Then:** [Configure security (TLS, auth)](security.md)
3. **Finally:** [Backups](production-guide.md)

### Additional Resources

- **Configuration tuning**: [Configuration Reference](configuration-reference.md)
- **Hybrid cloud integration**: [Hybrid Cloud Integration](hybrid-cloud-integration.md)
- **Production best practices**: [Production Guide](production-guide.md)
- **Security hardening**: [Security Guide](security.md)

---

[← Back to Advanced Setup](../ADVANCED_SETUP.md)
