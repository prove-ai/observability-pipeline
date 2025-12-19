# Advanced Setup Guide - Observability Pipeline

This guide provides comprehensive instructions for deploying and configuring the Observability Pipeline in production environments. The pipeline converts OpenTelemetry (OTLP) traces into Prometheus metrics, stores them in VictoriaMetrics for long-term retention, and provides flexible deployment options to integrate with your existing infrastructure.

### What This Pipeline Does

- Receives OTLP traces via gRPC (port 4317) and HTTP (port 4318)
- Converts spans to metrics using the spanmetrics connector
- Exports metrics to Prometheus format (port 8889)
- Scrapes metrics into Prometheus (10-second interval)
- Stores metrics long-term in VictoriaMetrics (12-month retention)
- Exposes Prometheus-compatible query API via VictoriaMetrics

### Prerequisites

- **Familiarity with**: Docker, Prometheus, basic observability concepts
- **Infrastructure**: Docker and Docker Compose installed
- **Network Access**: Appropriate firewall rules and security group configurations

## Quick Start Decision Tree

**Which guide do you need?**

| If you want to...                                       | Start here                                                                  |
| ------------------------------------------------------- | --------------------------------------------------------------------------- |
| Get started quickly with basic setup                    | [Quick Start Guide](guides/quick-start.md)                                  |
| Understand how the pipeline works                       | [Architecture Overview](guides/architecture.md)                             |
| Choose the right deployment profile                     | [Deployment Profiles Guide](guides/deployment-profiles.md)                  |
| Configure the collector, Prometheus, or VictoriaMetrics | [Configuration Reference](guides/configuration-reference.md)                |
| Deploy via Docker Compose                               | [Deployment Guide](guides/deployment-guide.md)                              |
| Integrate LLM observability (vLLM, Ollama)              | [vLLM Guide](guides/vllm-guide.md) / [Ollama Guide](guides/ollama-guide.md) |
| Integrate via Hybrid Cloud (On-Prem + Cloud)            | [Hybrid Cloud Integration](guides/hybrid-cloud-integration.md)              |
| Prepare for production (HA, backups, sizing)            | [Production Guide](guides/production-guide.md)                              |
| Secure your deployment (auth, firewalls)                | [Security Guide](guides/security.md)                                        |
| Look up metrics, ports, queries, or commands            | [Reference Guide](guides/reference.md)                                      |

## Documentation Structure

### Getting Started

1. **[Quick Start Guide](guides/quick-start.md)**  
   Fast-track setup for new users. Deploy the full stack with one command, send your first trace, and integrate LLM inference monitoring. **Start [here](guides/quick-start.md) if you're new to the pipeline.**

### Core Setup Guides

2. **[Architecture Overview](guides/architecture.md)**  
   Understand the data flow, component responsibilities, and network architecture.

3. **[Deployment Profiles Guide](guides/deployment-profiles.md)**  
   Choose the right profile (full, no-prometheus, no-vm, no-collector, vm-only, prom-only) based on your existing infrastructure.

4. **[Configuration Reference](guides/configuration-reference.md)**  
   Detailed configuration options for OpenTelemetry Collector, Prometheus, and VictoriaMetrics.

5. **[Deployment Guide](guides/deployment-guide.md)**  
   Step-by-step instructions for deploying via Docker Compose.

### LLM Integration Guides

6. **[vLLM Observability Guide](guides/vllm-guide.md)**  
   Integrate vLLM inference servers with the observability pipeline. Covers GPU setup, Docker deployment, metrics configuration, and end-to-end validation.

7. **[Ollama Observability Guide](guides/ollama-guide.md)**  
   Integrate Ollama with the observability pipeline for CPU-based LLM inference monitoring. _(Coming soon)_

### Advanced Topics

8. **[Hybrid Cloud Integration](guides/hybrid-cloud-integration.md)**  
   Hybrid cloud integration pattern for connecting on-premises infrastructure to cloud-hosted observability.

9. **[Production Guide](guides/production-guide.md)**  
   Resource sizing, data persistence, backup strategies, and performance tuning.

10. **[Security Guide](guides/security.md)**  
    Authentication and network security

### Reference

11. **[Reference Guide](guides/reference.md)**  
    Metric reference, example queries, port reference, useful commands, and common configurations.

## Getting Started

1. **Just getting started?** Begin with the [Quick Start Guide](guides/quick-start.md) to deploy the full stack, send your first trace, and monitor LLM inference performance in minutes.

2. **New to this pipeline?** Read the [Architecture Overview](guides/architecture.md) to understand how it works.

3. **Have specific LLM inference needs?** Detailed information on monitoring LLM inference is available in the [vLLM](guides/vllm-guide.md) and [Ollama](guides/ollama-guide.md) guides.

4. **Ready to deploy in a specific configuration?** Go to [Deployment Profiles Guide](guides/deployment-profiles.md) to choose your profile, then follow [Deployment Guide](guides/deployment-guide.md).

5. **Configuring for your use case?** See [Configuration Reference](guides/configuration-reference.md) for tuning options.

6. **Preparing for production?** Review [Production Guide](guides/production-guide.md) and [Security Guide](guides/security.md).

## Additional Resources

- **Project README**: [../README.md](../README.md) - Quick start and basic usage
- **Docker Compose Profiles**: [../docker-compose/PROFILES.md](../docker-compose/PROFILES.md) - Profile overview
- **Ansible Playbooks**: [../playbooks/README.md](../playbooks/README.md) - Ansible deployment details
