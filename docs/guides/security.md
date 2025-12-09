# Security & Compliance Guide

[← Back to Advanced Setup](../ADVANCED_SETUP.md)

---

## ⚠️ Work in progress

The current doc is only referencing [this config](https://github.com/CasperLabs/observability-pipeline/pull/6/files).

---

This guide covers security best practices for the Observability Pipeline including TLS/SSL, authentication, network security, and data privacy.

## Table of Contents

- [Securing Debugging Endpoints](#securing-debugging-endpoints)
- [TLS/SSL Configuration](#tlsssl-configuration)
- [Authentication & Authorization](#authentication--authorization)
- [Network Security](#network-security)
- [Data Privacy](#data-privacy)

---

## Securing Debugging Endpoints

The OpenTelemetry Collector debugging extensions (pprof and zpages) expose sensitive information about your system and should be secured in production.

### Recommendations

#### 1. Disable in Production (Recommended)

For production environments, disable debugging extensions entirely:

```yaml
service:
  extensions: [health_check] # Remove pprof and zpages
```

#### 2. Restrict Access via Firewall

If you need debugging capabilities in production, restrict access to specific IPs:

```bash
# iptables example
iptables -A INPUT -p tcp --dport 1888 -s 10.0.0.100 -j ACCEPT
iptables -A INPUT -p tcp --dport 1888 -j DROP
iptables -A INPUT -p tcp --dport 55679 -s 10.0.0.100 -j ACCEPT
iptables -A INPUT -p tcp --dport 55679 -j DROP
```

#### 3. Use Reverse Proxy with Authentication

Place a reverse proxy (nginx, Envoy) in front of debugging endpoints with authentication:

```nginx
# nginx example
location /debug/ {
    auth_basic "Restricted";
    auth_basic_user_file /etc/nginx/.htpasswd;
    proxy_pass http://localhost:55679/debug/;
}
```

#### 4. Bind to Localhost Only

For local debugging only, bind to localhost:

```yaml
extensions:
  pprof:
    endpoint: 127.0.0.1:1888 # Only accessible from localhost
  zpages:
    endpoint: 127.0.0.1:55679 # Only accessible from localhost
```

---

## TLS/SSL Configuration

### Collector TLS

Enable TLS for OTLP receivers:

```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
        tls:
          cert_file: /etc/otel/certs/server.crt
          key_file: /etc/otel/certs/server.key
          client_ca_file: /etc/otel/certs/ca.crt # Optional: mTLS
      http:
        endpoint: 0.0.0.0:4318
        tls:
          cert_file: /etc/otel/certs/server.crt
          key_file: /etc/otel/certs/server.key
```

**Mount certificates in Docker Compose**:

```yaml
otel-collector:
  volumes:
    - ./otel-collector-config.yaml:/etc/otel/config.yaml:ro
    - ./certs:/etc/otel/certs:ro # Add this
```

### Generate Self-Signed Certificates (for testing)

```bash
# Generate CA
openssl genrsa -out ca.key 4096
openssl req -new -x509 -days 3650 -key ca.key -out ca.crt

# Generate server certificate
openssl genrsa -out server.key 4096
openssl req -new -key server.key -out server.csr
openssl x509 -req -days 365 -in server.csr -CA ca.crt -CAkey ca.key -set_serial 01 -out server.crt
```

### Prometheus TLS

Protect Prometheus endpoints with TLS:

**Create `web-config.yml`**:

```yaml
tls_server_config:
  cert_file: /etc/prometheus/certs/server.crt
  key_file: /etc/prometheus/certs/server.key
  client_ca_file: /etc/prometheus/certs/ca.crt # Optional: mTLS
  client_auth_type: RequireAndVerifyClientCert
```

**Update Docker Compose**:

```yaml
prometheus:
  image: prom/prometheus:latest
  command:
    - "--config.file=/etc/prometheus/prometheus.yaml"
    - "--web.config.file=/etc/prometheus/web-config.yml" # Add this
  volumes:
    - ./prometheus.yaml:/etc/prometheus/prometheus.yaml:ro
    - ./web-config.yml:/etc/prometheus/web-config.yml:ro
    - ./certs:/etc/prometheus/certs:ro
```

---

## Authentication & Authorization

### Basic Auth (Prometheus)

Protect Prometheus endpoints:

**Create `web-config.yml`**:

```yaml
basic_auth_users:
  admin: $2y$10$... # bcrypt hash of password
  # Generate with: htpasswd -nBC 10 "" | tr -d ':\n'
```

**Generate password hash**:

```bash
htpasswd -nBC 10 "" | tr -d ':\n'
# Enter password when prompted
```

**Update Docker Compose**:

```yaml
prometheus:
  image: prom/prometheus:latest
  command:
    - "--config.file=/etc/prometheus/prometheus.yaml"
    - "--web.config.file=/etc/prometheus/web-config.yml"
  volumes:
    - ./prometheus.yaml:/etc/prometheus/prometheus.yaml:ro
    - ./web-config.yml:/etc/prometheus/web-config.yml:ro
```

### Bearer Token Auth (VictoriaMetrics)

Use a reverse proxy (nginx) for token-based auth:

```nginx
# nginx.conf
server {
    listen 8429 ssl;

    ssl_certificate /etc/nginx/certs/server.crt;
    ssl_certificate_key /etc/nginx/certs/server.key;

    location / {
        if ($http_authorization != "Bearer YOUR_SECRET_TOKEN") {
            return 401;
        }
        proxy_pass http://victoriametrics:8428;
    }
}
```

### OAuth2/OIDC (Advanced)

For enterprise authentication, use OAuth2 Proxy:

```yaml
services:
  oauth2-proxy:
    image: quay.io/oauth2-proxy/oauth2-proxy:latest
    command:
      - --provider=oidc
      - --upstream=http://prometheus:9090
      - --http-address=0.0.0.0:4180
      - --client-id=YOUR_CLIENT_ID
      - --client-secret=YOUR_CLIENT_SECRET
      - --oidc-issuer-url=https://your-idp.com
    ports:
      - "4180:4180"
```

---

## Network Security

### Firewall Rules (iptables)

```bash
# Allow OTLP from specific CIDR
iptables -A INPUT -p tcp --dport 4317 -s 10.0.0.0/8 -j ACCEPT
iptables -A INPUT -p tcp --dport 4318 -s 10.0.0.0/8 -j ACCEPT

# Allow Prometheus from specific IPs
iptables -A INPUT -p tcp --dport 9090 -s 192.168.1.100 -j ACCEPT

# Drop all other traffic to observability ports
iptables -A INPUT -p tcp --dport 4317 -j DROP
iptables -A INPUT -p tcp --dport 4318 -j DROP
iptables -A INPUT -p tcp --dport 9090 -j DROP
```

### AWS Security Group

```bash
# Create security group
aws ec2 create-security-group \
  --group-name observability-sg \
  --description "Observability Pipeline Security Group"

# Allow OTLP from VPC
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxx \
  --protocol tcp \
  --port 4317-4318 \
  --cidr 10.0.0.0/16

# Allow Prometheus from specific IP
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxx \
  --protocol tcp \
  --port 9090 \
  --cidr 1.2.3.4/32
```

### Network Segmentation

Use Docker networks to isolate components:

```yaml
networks:
  frontend:
    driver: bridge
  backend:
    driver: bridge
    internal: true # No external access

services:
  otel-collector:
    networks:
      - frontend # Exposed to external
      - backend # Internal communication

  prometheus:
    networks:
      - backend # Internal only

  victoriametrics:
    networks:
      - backend # Internal only
```

### VPN/Private Link

For AWS deployments, use AWS PrivateLink or VPN:

```bash
# Create VPC endpoint for secure access
aws ec2 create-vpc-endpoint \
  --vpc-id vpc-xxx \
  --service-name com.amazonaws.vpce.region.vpce-svc-xxx \
  --subnet-ids subnet-xxx
```

**For hybrid cloud deployments**, see the [Hybrid Cloud Integration](hybrid-cloud-integration.md) guide for detailed instructions on securing VPN and Direct Connect connections between on-premises and cloud environments.

---

## Data Privacy

### PII Scrubbing

Add processors to remove sensitive data:

```yaml
processors:
  attributes/scrub-pii:
    actions:
      - key: user.email
        action: delete
      - key: user.id
        action: hash
      - key: credit_card
        action: delete

  batch: {}

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [attributes/scrub-pii, batch]
      exporters: [spanmetrics]
```

### Hash Sensitive Attributes

```yaml
processors:
  attributes/hash:
    actions:
      - key: user.id
        action: hash
      - key: customer.id
        action: hash
```

### Filter by Attribute

Drop traces with sensitive data:

```yaml
processors:
  filter/drop-sensitive:
    spans:
      exclude:
        match_type: regexp
        attributes:
          - key: http.target
            value: ".*password.*"
          - key: http.target
            value: ".*token.*"
```

### Attribute Redaction

Redact specific patterns:

```yaml
processors:
  transform:
    trace_statements:
      - context: span
        statements:
          - replace_pattern(attributes["http.url"], "password=([^&]*)", "password=***")
          - replace_pattern(attributes["http.url"], "token=([^&]*)", "token=***")
```

---

## Compliance Considerations

### GDPR Compliance

- **Data Minimization**: Only collect necessary attributes
- **Right to be Forgotten**: Implement data deletion policies
- **Data Retention**: Configure appropriate retention periods
- **Access Controls**: Restrict access to observability data

### HIPAA Compliance

- **Encryption in Transit**: Enable TLS for all communication
- **Encryption at Rest**: Use encrypted volumes for data storage
- **Access Logging**: Enable audit logs for all access
- **PII Scrubbing**: Remove all PII from traces

### SOC 2 Compliance

- **Access Controls**: Implement RBAC and authentication
- **Monitoring**: Monitor the observability stack itself
- **Incident Response**: Document runbooks and escalation procedures
- **Change Management**: Version control all configurations

---

## Security Checklist

Before going to production, ensure:

- [ ] **TLS enabled** for all external endpoints
- [ ] **Authentication** configured for Prometheus and VictoriaMetrics
- [ ] **Firewall rules** restrict access to authorized networks
- [ ] **Debugging endpoints** (pprof, zpages) disabled or secured
- [ ] **PII scrubbing** configured in collector
- [ ] **Data retention** policies align with compliance requirements
- [ ] **Access logging** enabled for audit trails
- [ ] **Network segmentation** isolates internal components
- [ ] **Secrets management** (no hardcoded passwords)
- [ ] **Security patching** process in place

---

## Next Steps

- **Reference materials**: [Reference Guide](reference.md)
- **Return to main guide**: [Advanced Setup](../ADVANCED_SETUP.md)

[← Back to Advanced Setup](../ADVANCED_SETUP.md)
