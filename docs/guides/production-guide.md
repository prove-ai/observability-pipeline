# Production Deployment Guide

[← Back to Advanced Setup](../ADVANCED_SETUP.md)

This guide walks you through evaluating your production requirements and directs you to the appropriate documentation for implementing your observability pipeline in production.

## Overview

Deploying to production requires careful consideration of several key areas:

1. **Deployment Profile** - What components do you need?
2. **Deployment Architecture** - Where and how will you deploy?
3. **Security Requirements** - How will you secure your deployment?
4. **Production Considerations** - High availability, performance, and operational needs

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

### Where will you deploy?

Choose your deployment method based on your infrastructure and operational requirements:

| Deployment Method        | Best For                                         | Complexity | Automation |
| ------------------------ | ------------------------------------------------ | ---------- | ---------- |
| **Local Docker Compose** | Development, testing, single server              | Low        | Manual     |
| **AWS EC2 via Ansible**  | Production, multi-server, repeatable deployments | Medium     | High       |
| **Kubernetes**           | Container orchestration, auto-scaling            | High       | High       |

### Decision: Choose Your Deployment Method

**For Development/Testing:**

- Use local Docker Compose
- Quick setup (2 minutes)
- Easy to iterate and test changes

**For Production:**

- Use Ansible for AWS EC2 (recommended for most cases)
- Repeatable, automated deployments
- Infrastructure as code

**For Kubernetes Environments:**

- Deploy collector via Helm or OpenTelemetry Operator
- Use our Prometheus + VictoriaMetrics for storage (`no-collector` profile)

**📖 Next:** See the [Deployment Methods Guide](deployment-methods.md) for step-by-step instructions on deploying using your chosen method.

---

## Step 3: Evaluate Your Security Requirements

### What are your security and compliance needs?

Consider these security aspects for your production deployment:

| Security Area          | Questions to Consider                        | Priority |
| ---------------------- | -------------------------------------------- | -------- |
| **Transport Security** | Do you need TLS/mTLS?                        | High     |
| **Access Control**     | Who should access Prometheus/VM UIs?         | High     |
| **Data Privacy**       | Do you need to scrub PII from traces?        | High     |
| **Network Security**   | Should services be on private networks only? | Medium   |
| **Compliance**         | GDPR, HIPAA, SOC 2 requirements?             | Varies   |
| **Debug Endpoints**    | Should pprof/zpages be disabled?             | Medium   |

### Security Checklist

Before going to production, ensure you address:

- [ ] **TLS Configuration** - Encrypt communication between components
- [ ] **Authentication** - Protect Prometheus and VictoriaMetrics endpoints
- [ ] **Network Restrictions** - Limit access via firewalls/security groups
- [ ] **Debug Endpoints** - Disable or restrict pprof (1888) and zpages (55679)
- [ ] **PII Scrubbing** - Remove sensitive data from traces
- [ ] **Compliance Requirements** - Meet regulatory requirements

**📖 Next:** See the [Security Guide](security.md) for detailed configuration instructions for TLS, authentication, network security, and PII scrubbing.

---

## Step 4: Production Operational Considerations

After choosing your profile, deployment method, and security configuration, consider these operational aspects:

### High Availability

**Do you need redundancy?**

- **Collector HA**: Deploy multiple collector instances behind a load balancer
- **Prometheus HA**: Run multiple Prometheus instances (VictoriaMetrics deduplicates)
- **VictoriaMetrics HA**: Use VictoriaMetrics cluster mode for horizontal scaling

**📖 Details:** See [High Availability section in ADVANCED_SETUP_DOCS.md](../../ADVANCED_SETUP_DOCS.md#high-availability)

### Resource Sizing

**What resources do you need?**

Quick sizing guide for planning:

| Component           | Small Workload   | Medium Workload   | Large Workload      |
| ------------------- | ---------------- | ----------------- | ------------------- |
| **Collector**       | 2 cores, 2GB RAM | 4 cores, 4GB RAM  | 8+ cores, 8GB+ RAM  |
| **Prometheus**      | 2 cores, 4GB RAM | 4 cores, 8GB RAM  | 8+ cores, 16GB+ RAM |
| **VictoriaMetrics** | 2 cores, 8GB RAM | 4 cores, 16GB RAM | 8+ cores, 32GB+ RAM |

**Workload Definitions:**

- **Small**: <10k spans/sec, <100k active time series
- **Medium**: 10k-50k spans/sec, 100k-1M active time series
- **Large**: >50k spans/sec, >1M active time series

**📖 Details:** See [Resource Sizing section in ADVANCED_SETUP_DOCS.md](../../ADVANCED_SETUP_DOCS.md#resource-sizing)

### Data Persistence

**How will you store data?**

- **Development**: Docker volumes (default)
- **Production**: Host-mounted directories or EBS volumes
- **Retention**: VictoriaMetrics default is 12 months (configurable)

**📖 Details:** See [Data Persistence section in ADVANCED_SETUP_DOCS.md](../../ADVANCED_SETUP_DOCS.md#data-persistence)

### Backup Strategy

**What's your backup plan?**

- **VictoriaMetrics**: Supports snapshot API for backups
- **Prometheus**: Supports TSDB snapshots (requires admin API)
- **Automation**: Implement automated backups via cron/scheduled tasks

**📖 Details:** See [Backup Strategy section in ADVANCED_SETUP_DOCS.md](../../ADVANCED_SETUP_DOCS.md#backup-strategy)

### Performance Tuning

**Do you need to optimize for high throughput?**

Key tuning areas:

- **Batch Processor**: Adjust batch sizes and timeouts
- **Memory Limiter**: Prevent OOM crashes under load
- **Histogram Buckets**: Customize for your latency profile
- **Prometheus Scraping**: Tune intervals and relabeling

**📖 Details:** See [Performance Tuning section in ADVANCED_SETUP_DOCS.md](../../ADVANCED_SETUP_DOCS.md#performance-tuning)

---

## Production Deployment Workflow

Follow this recommended sequence for a successful production deployment:

```
1. Choose Profile → 2. Configure Security → 3. Deploy → 4. Verify → 5. Monitor
     (Step 1)           (Step 3)          (Step 2)   (Below)    (Below)
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
- [ ] TLS is enabled (if required)
- [ ] Authentication is configured (if required)

**📖 Details:** See [Post-Deployment Verification in Deployment Methods Guide](deployment-methods.md#post-deployment-verification)

### Monitoring Your Observability Stack

**Monitor the monitors:**

- **Collector Metrics**: Available at `:8888/metrics`
- **Prometheus Metrics**: Built-in self-monitoring
- **VictoriaMetrics Metrics**: Available at `:8428/metrics`

Key metrics to alert on:

- Collector: `otelcol_receiver_refused_spans` (backpressure)
- Prometheus: `prometheus_remote_storage_samples_failed_total` (remote write failures)
- VictoriaMetrics: `vm_free_disk_space_bytes` (disk space)

**📖 Details:** See [Monitoring the Observability Stack in ADVANCED_SETUP_DOCS.md](../../ADVANCED_SETUP_DOCS.md#monitoring-the-observability-stack)

---

## Quick Start: Common Production Scenarios

### Scenario 1: New Production Deployment (Full Stack)

**You need:** Complete observability stack from scratch

**Steps:**

1. ✅ Choose **`full`** profile ([Deployment Profiles Guide](deployment-profiles.md))
2. ✅ Deploy via **Ansible to AWS EC2** ([Deployment Methods Guide](deployment-methods.md))
3. ✅ Configure **TLS and authentication** ([Security Guide](security.md))
4. ✅ Set up **HA with load balancer** ([ADVANCED_SETUP_DOCS.md](../../ADVANCED_SETUP_DOCS.md#high-availability))
5. ✅ Configure **backups** ([ADVANCED_SETUP_DOCS.md](../../ADVANCED_SETUP_DOCS.md#backup-strategy))

### Scenario 2: Adding to Existing Prometheus

**You have:** Prometheus already, need trace-to-metrics + long-term storage

**Steps:**

1. ✅ Choose **`no-prometheus`** profile ([Deployment Profiles Guide](deployment-profiles.md))
2. ✅ Deploy **Collector + VictoriaMetrics**
3. ✅ Configure your Prometheus to **scrape collector** and **remote_write to VM**
4. ✅ Configure **security** ([Security Guide](security.md))

### Scenario 3: Multi-Region Deployment

**You need:** Collectors in multiple regions, centralized storage

**Steps:**

1. ✅ Choose **`no-vm`** profile for each region ([Deployment Profiles Guide](deployment-profiles.md))
2. ✅ Deploy regional **Collector + Prometheus** in each region
3. ✅ Deploy central **VictoriaMetrics** (`vm-only` profile)
4. ✅ Configure all Prometheus instances to **remote_write to central VM**
5. ✅ Add **external_labels** to identify regions

**📖 Details:** See [Multi-Region Deployment Pattern in ADVANCED_SETUP_DOCS.md](../../ADVANCED_SETUP_DOCS.md#pattern-1-multi-region-deployment-with-central-storage)

---

## Troubleshooting Production Issues

Common production issues and where to find solutions:

| Issue                            | Likely Cause                       | Where to Look                                                            |
| -------------------------------- | ---------------------------------- | ------------------------------------------------------------------------ |
| High memory usage                | Cardinality explosion, batch sizes | [Performance Tuning](../../ADVANCED_SETUP_DOCS.md#performance-tuning)    |
| Traces not converting to metrics | Spanmetrics config                 | [Troubleshooting](../../ADVANCED_SETUP_DOCS.md#advanced-troubleshooting) |
| Connection refused               | Network/firewall rules             | [Deployment Methods Guide](deployment-methods.md#troubleshooting)        |
| Authentication failing           | TLS/auth config                    | [Security Guide](security.md)                                            |
| High disk usage                  | Retention settings, cardinality    | [Configuration Reference](configuration-reference.md)                    |

**📖 Full Troubleshooting Guide:** See [Advanced Troubleshooting in ADVANCED_SETUP_DOCS.md](../../ADVANCED_SETUP_DOCS.md#advanced-troubleshooting)

---

## Production Readiness Checklist

Use this final checklist before going live:

### Deployment

- [ ] Chosen appropriate deployment profile for your infrastructure
- [ ] Deployed using repeatable method (Ansible/IaC)
- [ ] Verified all services are running and healthy

### Security

- [ ] TLS configured for external endpoints (if required)
- [ ] Authentication configured for Prometheus/VictoriaMetrics
- [ ] Firewall rules restrict access to authorized networks
- [ ] Debug endpoints disabled or secured
- [ ] PII scrubbing configured (if handling sensitive data)

### Operations

- [ ] High availability configured (if required)
- [ ] Resource sizing appropriate for expected load
- [ ] Data persistence configured (host volumes/EBS)
- [ ] Backup strategy implemented and tested
- [ ] Monitoring configured for observability stack itself

### Testing

- [ ] End-to-end trace ingestion tested
- [ ] Metrics appearing in Prometheus and VictoriaMetrics
- [ ] Query performance acceptable
- [ ] Failover tested (if HA configured)
- [ ] Backup and restore tested

### Documentation

- [ ] Runbooks created for common operations
- [ ] Escalation procedures documented
- [ ] Configuration changes tracked in version control
- [ ] Team trained on operations and troubleshooting

---

## Additional Resources

### Detailed Implementation Guides

- **[Deployment Profiles Guide](deployment-profiles.md)** - Choose the right profile for your infrastructure
- **[Deployment Methods Guide](deployment-methods.md)** - Step-by-step deployment instructions
- **[Security Guide](security.md)** - TLS, authentication, network security, PII scrubbing
- **[Configuration Reference](configuration-reference.md)** - Detailed configuration options
- **[ADVANCED_SETUP_DOCS.md](../../ADVANCED_SETUP_DOCS.md)** - Comprehensive reference with all implementation details

### Architecture and Integration

- **[Architecture Guide](architecture.md)** - System architecture and data flow
- **[Integration Patterns](integration-patterns.md)** - Multi-region, Kubernetes, hybrid cloud patterns

### Reference Materials

- **[Reference Guide](reference.md)** - Metric reference, example queries, port reference

---

## Getting Help

If you encounter issues or have questions:

1. **Check the guides** linked throughout this document
2. **Review troubleshooting sections** in the relevant guides
3. **Consult the comprehensive guide**: [ADVANCED_SETUP_DOCS.md](../../ADVANCED_SETUP_DOCS.md)
4. **Contact your infrastructure team** for environment-specific guidance

---

[← Back to Advanced Setup](../ADVANCED_SETUP.md)
