# Production Deployment Guide

[← Back to Advanced Setup](../ADVANCED_SETUP.md)

This guide walks you through evaluating your production requirements and directs you to the appropriate documentation for implementing your observability pipeline in production.

## Overview

Deploying to production requires careful consideration of several key areas:

1. **Deployment Profile** - What components do you need?
2. **Deployment Architecture** - Where and how will you deploy?
3. **Security Requirements** - How will you secure your deployment?
4. **Production Considerations** - Performance, and operational needs

This guide will help you make informed decisions in each area and point you to the detailed implementation guides.

---

## Step 1: Evaluate Your Infrastructure

### What components do you already have?

Before deploying, assess what infrastructure you already have in place:

| Question                             | If YES →                         | If NO →             |
| ------------------------------------ | -------------------------------- | ------------------- |
| Do you have Prometheus?              | Consider `no-prometheus` profile | Continue evaluation |
| Do you have VictoriaMetrics?         | Consider `no-vm` profile         | Continue evaluation |
| Do you have OpenTelemetry Collector? | Consider `no-collector` profile  | Continue evaluation |
| Starting from scratch?               | Use `full` profile               | -                   |

### Decision: Choose Your Deployment Profile

Based on your existing infrastructure, select the appropriate profile:

| Your Situation                | Recommended Profile | What You Get                                                 |
| ----------------------------- | ------------------- | ------------------------------------------------------------ |
| **New/Greenfield deployment** | `full`              | Complete stack: Collector + Prometheus + VictoriaMetrics     |
| **Have Prometheus**           | `no-prometheus`     | Collector + VictoriaMetrics (integrate with your Prometheus) |
| **Have VictoriaMetrics**      | `no-vm`             | Collector + Prometheus (integrate with your VM)              |
| **Have OTel Collector**       | `no-collector`      | Prometheus + VictoriaMetrics (integrate with your collector) |
| **Need storage only**         | `vm-only`           | VictoriaMetrics only                                         |
| **Need scraper only**         | `prom-only`         | Prometheus only                                              |

**📖 Next:** See the [Deployment Profiles Guide](deployment-profiles.md) for detailed information on each profile, configuration requirements, and integration steps.

---

## Step 2: Evaluate Your Deployment Architecture

| Deployment Method    | Best For                            | Complexity | Automation |
| -------------------- | ----------------------------------- | ---------- | ---------- |
| Local Docker Compose | Development, testing, single server | Low        | Manual     |

**📖 Next:** See the [Deployment Guide](deployment-guide.md) for step-by-step instructions on deploying with Docker Compose.

---

## Step 3: Evaluate Your Security Requirements

### What are your security and compliance needs?

Consider these security aspects for your production deployment:

| Security Area        | Questions to Consider                        | Priority |
| -------------------- | -------------------------------------------- | -------- |
| **Access Control**   | Who should access Prometheus/VM UIs?         | High     |
| **Network Security** | Should services be on private networks only? | Medium   |
| **Debug Endpoints**  | Should pprof/zpages be disabled?             | Medium   |

### Security Checklist

Before going to production, ensure you address:

- [ ] **Authentication** - Protect Prometheus and VictoriaMetrics endpoints
- [ ] **Network Restrictions** - Limit access via firewalls/security groups
- [ ] **Debug Endpoints** - Disable or restrict pprof (1888) and zpages (55679)

**📖 Next:** See the [Security Guide](security.md) for detailed configuration instructions for authentication and network security.

---

## Step 4: Production Operational Considerations

After choosing your profile, deployment method, and security configuration, consider these operational aspects:

### Resource Sizing

**What resources do you need?**

**Workload Definitions:**

- **Small**: <10k spans/sec, <100k active time series
- **Medium**: 10k-50k spans/sec, 100k-1M active time series
- **Large**: >50k spans/sec, >1M active time series

### Data Persistence

**How will you store data?**

- **Development**: Docker volumes (default)
- **Production**: Host-mounted directories or block storage
- **Retention**: VictoriaMetrics default is 12 months (configurable)

### Backup Strategy

**What's your backup plan?**

- **VictoriaMetrics**: Supports snapshot API for backups
- **Prometheus**: Supports TSDB snapshots (requires admin API)
- **Automation**: Implement automated backups via cron/scheduled tasks

### Performance Tuning

<a id="performance-tuning"></a>
**Do you need to optimize for high throughput?**

Key tuning areas:

- **Batch Processor** (`otel-collector-config.yaml`):

  ```yaml
  batch:
    timeout: 10s
    send_batch_size: 1024
    send_batch_max_size: 2048
  ```

- **Memory Limiter** (add to `processors:`):

  ```yaml
  memory_limiter:
    check_interval: 1s
    limit_mib: 512
    spike_limit_mib: 128
  ```

- **Histogram Buckets** (`spanmetrics.histogram.explicit.buckets`):

  ```yaml
  buckets: [0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1, 5, 10] # seconds
  ```

- **Prometheus Scraping** (`prometheus.yaml`):
  ```yaml
  scrape_interval: 10s # increase to 15s-30s for lower overhead
  ```

---

## Production Deployment Workflow

Follow this recommended sequence for a successful production deployment:

```
1. Choose Profile → 2. Deploy → 3. Verify → 4. Monitor

```

### Verification Checklist

After deployment, verify everything is working:

#### Infrastructure Checks

- [ ] All expected services are running
- [ ] No containers in "Restarting" or "Exited" state
- [ ] Correct deployment profile is active

#### Health Checks

- [ ] Collector health: `curl http://<host>:13133/health/status`
- [ ] Prometheus health: `curl http://<host>:9090/-/healthy`
- [ ] VictoriaMetrics health: `curl http://<host>:8428/health`

#### Data Flow Checks

- [ ] Prometheus targets show "UP": `http://<host>:9090/targets`
- [ ] Can send test traces to collector
- [ ] Metrics appear in Prometheus
- [ ] Metrics are stored in VictoriaMetrics

#### Security Checks (Production Only)

- [ ] Only required ports are open
- [ ] Debug ports (1888, 55679) are NOT exposed publicly
- [ ] Authentication is configured

**📖 Details:** See [Post-Deployment Verification in Deployment Guide](deployment-guide.md#post-deployment-verification)

---

## Quick Start: Common Production Scenarios

### Scenario 1: New Production Deployment (Full Stack)

**You need:** Complete observability stack from scratch

**Steps:**

1. ✅ Choose **`full`** profile ([Deployment Profiles Guide](deployment-profiles.md))
2. ✅ Configure **authentication** ([Security Guide](security.md))
3. ✅ Configure **backups**

### Scenario 2: Adding to Existing Prometheus

**You have:** Prometheus already, need trace-to-metrics + long-term storage

**Steps:**

1. ✅ Choose **`no-prometheus`** profile ([Deployment Profiles Guide](deployment-profiles.md))
2. ✅ Deploy **Collector + VictoriaMetrics**
3. ✅ Configure your Prometheus to **scrape collector** and **remote_write to VM**
4. ✅ Configure **security** ([Security Guide](security.md))

---

## Troubleshooting Production Issues

Common production issues and where to find solutions:

| Issue                  | Likely Cause                       | Where to Look                                           |
| ---------------------- | ---------------------------------- | ------------------------------------------------------- |
| High memory usage      | Cardinality explosion, batch sizes | [Performance Tuning](#performance-tuning)               |
| Connection refused     | Network/firewall rules             | [Deployment Guide](deployment-guide.md#troubleshooting) |
| Authentication failing | Auth credentials config            | [Security Guide](security.md)                           |
| High disk usage        | Retention settings, cardinality    | [Configuration Reference](configuration-reference.md)   |

---

## Additional Resources

### Detailed Implementation Guides

- **[Deployment Profiles Guide](deployment-profiles.md)** - Choose the right profile for your infrastructure
- **[Deployment Guide](deployment-guide.md)** - Step-by-step deployment instructions
- **[Security Guide](security.md)** - Authentication, network security, and securing debugging endpoints
- **[Configuration Reference](configuration-reference.md)** - Detailed configuration options
- **[ADVANCED_SETUP_DOCS.md](../../ADVANCED_SETUP_DOCS.md)** - Comprehensive reference with all implementation details

### Architecture and Integration

- **[Architecture Guide](architecture.md)** - System architecture and data flow
- **[Hybrid Cloud Integration](hybrid-cloud-integration.md)** - Hybrid cloud integration pattern

### Reference Materials

- **[Reference Guide](reference.md)** - Metric reference, example queries, port reference

---

[← Back to Advanced Setup](../ADVANCED_SETUP.md)
