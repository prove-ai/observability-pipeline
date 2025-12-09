# Hybrid Cloud Integration

[← Back to Advanced Setup](../ADVANCED_SETUP.md)

This guide describes how to integrate the Observability Pipeline in a hybrid cloud architecture where on-premises applications send traces to a cloud-hosted observability stack.

## Overview

**Scenario**: On-premises applications send traces to cloud-hosted Observability Pipeline.

This pattern is ideal for organizations that:

- Have on-premises infrastructure but want centralized cloud observability
- Need to maintain some workloads on-prem due to compliance, latency, or legacy requirements
- Want to consolidate observability data from multiple locations into a single cloud platform

### Architecture

```
On-Premises:
  Apps → On-Prem Collector →
↓ (Secure tunnel: VPN / Direct Connect)
Cloud (AWS):
  Central Collector → Prometheus → VictoriaMetrics
```

### Key Benefits

- **Centralized Visibility**: All metrics from on-prem and cloud applications in one place
- **Cloud Storage**: Leverage cloud-native storage for long-term retention
- **Security**: Data encrypted in transit through VPN or Direct Connect
- **Scalability**: Scale observability infrastructure independently in the cloud

---

## Implementation

### Step 1: Deploy On-Prem Collector with Forward Exporter

Configure the on-prem collector to forward traces to your cloud collector:

**Configuration file**: `otel-collector-config.yaml` (on-premises)

```yaml
exporters:
  otlp:
    endpoint: <cloud-collector>:4317
    tls:
      insecure: false
      cert_file: /etc/otel/certs/client.crt
      key_file: /etc/otel/certs/client.key

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [otlp] # Forward to cloud
```

**Key Configuration Points:**

- Replace `<cloud-collector>` with your cloud collector's hostname or IP
- Use TLS certificates for secure communication
- The on-prem collector acts as a forwarding proxy

### Step 2: Deploy Cloud Collector with Full Stack

Deploy the complete observability stack in your cloud environment:

```bash
cd docker-compose
docker compose --profile full up -d
```

This deploys:

- OpenTelemetry Collector (receives traces from on-prem)
- Prometheus (scrapes and queries metrics)
- VictoriaMetrics (long-term storage)

**Cloud Configuration**: Ensure the cloud collector is configured to receive OTLP traffic on port 4317.

### Step 3: Configure Network Connectivity

Establish secure connectivity between on-premises and cloud:

#### Option 1: VPN Connection

Set up a VPN tunnel between your on-premises network and cloud VPC:

- **AWS**: AWS Site-to-Site VPN
- **Azure**: Azure VPN Gateway
- **GCP**: Cloud VPN

#### Option 2: Direct Connect / ExpressRoute

For higher bandwidth and lower latency:

- **AWS**: AWS Direct Connect
- **Azure**: Azure ExpressRoute
- **GCP**: Cloud Interconnect

#### Security Configuration

- **Firewall Rules**: Allow OTLP traffic (port 4317) from on-prem to cloud collector
- **Security Groups**: Configure cloud security groups to accept traffic from on-prem CIDR ranges
- **TLS**: Always use TLS for data in transit (see configuration above)
- **Authentication**: Consider mTLS for mutual authentication

---

## Verification

After deployment, verify the hybrid cloud setup is working:

### 1. Test On-Prem to Cloud Connectivity

From your on-premises network:

```bash
# Test network connectivity
telnet <cloud-collector> 4317

# Send test trace from on-prem
otel-cli span \
  --service "on-prem-app" \
  --name "test-operation" \
  --endpoint http://<on-prem-collector>:4318/v1/traces \
  --protocol http/protobuf \
  --attrs "location=on-prem"
```

### 2. Check Cloud Metrics

Wait 15 seconds, then query metrics in the cloud:

```bash
# Query Prometheus in cloud
curl 'http://<cloud-prometheus>:9090/api/v1/query?query=llm_traces_span_metrics_calls_total{location="on-prem"}' | jq
```

### 3. Monitor On-Prem Collector

Check on-prem collector logs for successful forwarding:

```bash
docker compose logs otel-collector | grep "traces"
```

---

## Troubleshooting

### Issue: Traces Not Reaching Cloud

**Possible Causes:**

- Network connectivity issues (VPN/Direct Connect down)
- Firewall blocking port 4317
- Security group misconfiguration
- TLS certificate issues

**Solutions:**

1. **Check network connectivity:**

   ```bash
   telnet <cloud-collector> 4317
   ```

2. **Verify firewall rules:**

   - Check on-prem firewall allows outbound 4317
   - Check cloud security groups allow inbound 4317

3. **Validate TLS certificates:**

   ```bash
   openssl s_client -connect <cloud-collector>:4317
   ```

4. **Check collector logs:**

   ```bash
   # On-prem collector
   docker compose logs otel-collector | grep "error"

   # Cloud collector
   docker compose logs otel-collector | grep "connection"
   ```

### Issue: High Latency

**Possible Causes:**

- Network path not optimized
- Batch processor settings too conservative

**Solutions:**

1. **Use Direct Connect** instead of VPN for lower latency

2. **Optimize batch processor** (on-prem collector):
   ```yaml
   processors:
     batch:
       timeout: 5s # Reduce for lower latency
       send_batch_size: 512
   ```

---

## Best Practices

### Security

- ✅ Always use TLS for data in transit
- ✅ Use mTLS for mutual authentication
- ✅ Restrict security groups to known CIDR ranges
- ✅ Rotate TLS certificates regularly
- ✅ Monitor for unauthorized access attempts

### Performance

- ✅ Use Direct Connect/ExpressRoute for production workloads
- ✅ Configure appropriate batch sizes to balance latency and throughput
- ✅ Monitor network bandwidth utilization
- ✅ Consider deploying multiple on-prem collectors for high availability

### Operational

- ✅ Set up monitoring for VPN/Direct Connect connectivity
- ✅ Configure alerts for collector health
- ✅ Document your network architecture and CIDR ranges
- ✅ Test failover scenarios
- ✅ Maintain on-prem collector as lightweight forwarding proxy

---

## Next Steps

- **Secure your deployment**: [Security Guide](security.md)
- **Prepare for production**: [Production Guide](production-guide.md)
- **Configure components**: [Configuration Reference](configuration-reference.md)
- **Reference materials**: [Reference Guide](reference.md)

[← Back to Advanced Setup](../ADVANCED_SETUP.md)
