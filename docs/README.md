# Advanced Documentation

This directory contains the advanced setup documentation for the Observability Pipeline, broken down into focused, navigable guides.

## Documentation Structure

### Main Guide

**[ADVANCED_SETUP.md](ADVANCED_SETUP.md)** - Start here! This is the main hub with an overview and links to all specialized guides.

### Specialized Guides

The documentation is organized into 8 focused guides in the `guides/` directory:

#### Setup & Configuration

1. **[architecture.md](guides/architecture.md)** - Data flow, component responsibilities, and network architecture
2. **[deployment-profiles.md](guides/deployment-profiles.md)** - Choose the right profile for your infrastructure (full, no-prometheus, no-vm, etc.)
3. **[configuration-reference.md](guides/configuration-reference.md)** - Detailed configuration for OpenTelemetry Collector, Prometheus, and VictoriaMetrics
4. **[deployment-guide.md](guides/deployment-guide.md)** - Docker Compose instructions

#### Advanced Topics

5. **[hybrid-cloud-integration.md](guides/hybrid-cloud-integration.md)** - Hybrid cloud integration pattern for on-premises and cloud deployments

6. **[production-guide.md](guides/production-guide.md)** - HA, sizing, persistence, backups, and performance tuning

7. **[security.md](guides/security.md)** - TLS, authentication, network security, and data privacy

#### Reference

8. **[reference.md](guides/reference.md)** - Metrics, ports, queries, commands, and configurations

## Quick Navigation

### I want to...

- **Understand how it works** → [architecture.md](guides/architecture.md)
- **Choose a deployment profile** → [deployment-profiles.md](guides/deployment-profiles.md)
- **Deploy the stack** → [deployment-guide.md](guides/deployment-guide.md)
- **Configure components** → [configuration-reference.md](guides/configuration-reference.md)
- **Prepare for production** → [production-guide.md](guides/production-guide.md)
- **Secure my deployment** → [security.md](guides/security.md)
- **Look up a command or metric** → [reference.md](guides/reference.md)
