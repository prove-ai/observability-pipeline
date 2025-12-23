# Security Guide

[← Back to Observability Pipeline Guide](../index.md)

This guide covers security best practices for the Observability Pipeline, focusing on authentication and network security considerations.

## Table of Contents

- [Authentication](#authentication)
- [Network Security](#network-security)
- [Security Checklist](#security-checklist)

---

## Authentication

All external requests to the observability services are authenticated before requests reach backend services. The Envoy proxy acts as the authentication gateway for most services, with one exception:

- **OTLP receivers** (ports 4317 for gRPC, 4318 for HTTP) - Envoy handles authentication
- **Prometheus** (port 9090) - **Authentication method depends on your configuration:**
  - **API Key mode**: Envoy handles authentication
  - **Basic Auth mode**: Prometheus handles authentication using its native basic auth feature
- **VictoriaMetrics** (port 8428) - Envoy handles authentication

**Architecture:** Backend services (otel-collector, prometheus, victoriametrics) are not directly exposed externally. They communicate internally within the Docker network without authentication, which is appropriate for container-to-container communication. All external access must go through Envoy, which provides routing and (in most cases) authentication before forwarding requests.

### Supported Authentication Methods

The system supports two authentication methods, controlled by the `ENVOY_AUTH_METHOD` environment variable:

1. **API Key (`api-key`)**: Uses the `X-API-Key` header. This is the default.
2. **Basic Auth (`basic-auth`)**: Uses standard HTTP Basic Authentication (header `Authorization: Basic <base64_credentials>`).

### Configuration

Authentication is configured via environment variables in the `.env` file in the project root.

#### 1. Choose Authentication Method

Set the `ENVOY_AUTH_METHOD` variable:

```bash
# Options: api-key, basic-auth
ENVOY_AUTH_METHOD=api-key
```

#### 2. Configure Credentials

**For API Key Authentication:**

Add your API keys as a comma-separated list in `ENVOY_API_KEYS`:

```bash
ENVOY_API_KEYS=my_secret_key_1,my_secret_key_2
```

**For Basic Authentication:**

Add your credentials as a comma-separated list of `username:password` pairs in `ENVOY_BASIC_AUTH_CREDENTIALS`:

```bash
ENVOY_BASIC_AUTH_CREDENTIALS=user:secretpassword
```

**Important - Prometheus Basic Auth Configuration:**

When using Basic Authentication (`ENVOY_AUTH_METHOD=basic-auth`), Prometheus handles its own authentication using its native basic auth feature, not Envoy. You must configure Prometheus with basic auth credentials:

1. **Generate a bcrypt password hash:**

```bash
# Install htpasswd (if not already installed)
# Ubuntu/Debian: sudo apt-get install apache2-utils
# macOS: brew install httpd

# Generate password hash
htpasswd -nBC 10 "" | tr -d ':\n'
# Enter your password when prompted
# Copy the resulting hash
```

2. **Create Prometheus web config file** (`docker-compose/prometheus-web-config.yaml`):

```yaml
basic_auth_users:
  admin: $2y$10$your_bcrypt_password_hash_here
```

3. **Update docker-compose.yaml** to mount the web config file and enable Prometheus basic auth:

```yaml
prometheus:
  image: prom/prometheus:latest
  command:
    - "--config.file=/etc/prometheus/prometheus.yaml"
    - "--web.config.file=/etc/prometheus/web-config.yaml" # Add this line
  volumes:
    - ./prometheus.yaml:/etc/prometheus/prometheus.yaml
    - ./prometheus-web-config.yaml:/etc/prometheus/web-config.yaml # Add this line
    - prometheus_data:/prometheus
```

4. **Restart the stack** for changes to take effect:

```bash
docker compose restart prometheus
```

**Note:** For the OTLP receivers and VictoriaMetrics, basic auth credentials are still handled by Envoy using `ENVOY_BASIC_AUTH_CREDENTIALS`. Only Prometheus uses native basic auth when this mode is enabled.

### Default Behavior

- If `ENVOY_AUTH_METHOD` is not set, it defaults to `api-key`.
- If `ENVOY_API_KEYS` is not set, a placeholder key (`placeholder_api_key`) is used.
- If `ENVOY_BASIC_AUTH_CREDENTIALS` is not set, Basic Auth will fail if enabled.

**⚠️ Important:** The placeholder API key is not secure. Always configure proper credentials for production deployments.

### Authentication Failure

When authentication fails, Envoy returns a `401 Unauthorized` response:

- **API Key method**: Returns `"Missing or Invalid API Key"`
- **Basic Auth method**: Returns `"Unauthorized"` with `WWW-Authenticate: Basic realm="Observability Pipeline"` header

Requests are rejected at the Envoy layer and never reach backend services.

### Using Authentication in Requests

**API Key Authentication:**

```bash
# Send trace with API key (all services)
otel-cli span \
  --service "otel-test" \
  --name "demo-span" \
  --endpoint http://localhost:4318/v1/traces \
  --protocol http/protobuf \
  --attrs "env=dev,component=demo" \
  --start "$(date -Iseconds)" \
  --end "$(date -Iseconds)" \
  --otlp-headers "X-API-Key= Y"

# Query Prometheus with API key
curl -H "X-API-Key: my_secret_key_1" \
  "http://<host>:9090/api/v1/query?query=up"
```

**Basic Authentication:**

When using Basic Auth mode, authentication varies by service:

```bash
# OTLP receivers and VictoriaMetrics - authenticated by Envoy
otel-cli span \
  --service "otel-test" \
  --name "demo-span" \
  --endpoint http://localhost:4318/v1/traces \
  --protocol http/protobuf \
  --attrs "env=dev,component=demo" \
  --start "$(date -Iseconds)" \
  --end "$(date -Iseconds)" \
  --otlp-headers "Authorization=Basic $(echo -n 'user:secretpassword' | base64)"

curl -u user:secretpassword \
  "http://<host>:8428/api/v1/query?query=up"

# Prometheus - authenticated by Prometheus (not Envoy)
# Use credentials configured in prometheus-web-config.yaml
curl -u prometheus_user:prometheus_password \
  "http://<host>:9090/api/v1/query?query=up"
```

**Important:** In Basic Auth mode, Prometheus uses its own credentials (configured in `prometheus-web-config.yaml`), which may be different from the Envoy basic auth credentials used by other services.

---

## Network Security

### Port Exposure

The default Docker Compose configuration exposes the following ports:

| Port  | Service                 | Access Type          | Authentication                         | Purpose                      |
| ----- | ----------------------- | -------------------- | -------------------------------------- | ---------------------------- |
| 4317  | Envoy → OTLP            | External (via Envoy) | Envoy (API Key or Basic Auth)          | OTLP gRPC receiver           |
| 4318  | Envoy → OTLP            | External (via Envoy) | Envoy (API Key or Basic Auth)          | OTLP HTTP receiver           |
| 9090  | Envoy → Prometheus      | External (via Envoy) | API Key: Envoy; Basic Auth: Prometheus | Prometheus UI and API        |
| 8428  | Envoy → VictoriaMetrics | External (via Envoy) | Envoy (API Key or Basic Auth)          | VictoriaMetrics API          |
| 1888  | Collector               | External (direct)    | None                                   | pprof (disabled by default)  |
| 55679 | Collector               | External (direct)    | None                                   | zpages (disabled by default) |
| 13133 | Collector               | External (direct)    | None                                   | Health check                 |
| 8888  | Collector               | External (direct)    | None                                   | Internal collector metrics   |
| 8889  | Collector               | Internal only        | None                                   | Prometheus exporter          |
| 9901  | Envoy                   | Localhost only       | None                                   | Envoy admin interface        |

**Port Configuration Requirements:**

- **Externally accessible** (must be open in firewall): 4317, 4318, 9090, 8428
- **Internal only** (no firewall rules needed): 8889
- **Localhost only** (bind to 127.0.0.1): 9901
- **Optional/Debug** (typically disabled in production): 1888, 55679, 13133, 8888

**Key Points:**

- **Ports 4317, 4318, 8428**: Exposed externally but protected by Envoy authentication. All requests must include valid credentials.
- **Port 9090 (Prometheus)**: Exposed externally. Authentication depends on mode:
  - **API Key mode**: Protected by Envoy
  - **Basic Auth mode**: Protected by Prometheus native basic auth (Envoy passes through)
- **Ports 1888, 55679**: Only exposed if debugging extensions are enabled in collector config. Not protected by Envoy (direct access to collector).
- **Port 8889**: Internal only - Prometheus scrapes this port within the Docker network, no authentication needed.
- **Port 9901**: Envoy admin interface bound to localhost only, accessible from host machine for debugging.

### Security Considerations

1. **Firewall Rules**: Restrict access to exposed ports (4317, 4318, 9090, 8428) using firewall rules or security groups in your deployment environment. Even with authentication, limiting network access reduces attack surface.

2. **Network Isolation**: The default Docker Compose configuration uses a bridge network (`observability`) that isolates services from the host network. Backend services (collector, Prometheus, VictoriaMetrics) are not directly exposed externally; they are accessed only through the Envoy proxy, which provides routing and authentication.

3. **Internal Service Communication**: Services communicate internally within the Docker network without authentication. This is appropriate since the network is isolated and only accessible to containers in the same network. The Envoy proxy ensures all external access is properly routed and (in most cases) authenticated.

4. **Prometheus Authentication**: When using Basic Auth mode, Prometheus handles its own authentication using its native basic auth feature. This provides more flexibility and aligns with standard Prometheus deployment patterns. Ensure you configure strong passwords in the `prometheus-web-config.yaml` file.

5. **Envoy Admin Interface**: The Envoy admin interface (port 9901) is bound to localhost only, preventing external access. This interface provides debugging and monitoring capabilities for Envoy itself.

### Docker Network Configuration

The default configuration uses a single bridge network:

```yaml
networks:
  observability:
    driver: bridge
```

All services communicate within this isolated network. Only the Envoy proxy and explicitly exposed ports are accessible from outside the Docker network.

---

## Security Checklist

Before deploying to production, ensure:

- [ ] **Authentication configured** - Set `ENVOY_AUTH_METHOD` and appropriate credentials in `.env`
- [ ] **Placeholder keys removed** - Replace `placeholder_api_key` with secure credentials
- [ ] **Prometheus basic auth configured** - If using Basic Auth mode, configure `prometheus-web-config.yaml` with strong bcrypt password hashes
- [ ] **Debugging endpoints secured** - Keep pprof and zpages disabled, or bind to localhost only
- [ ] **Port exposure reviewed** - Verify only necessary ports are exposed
- [ ] **Firewall rules configured** - Restrict access to observability ports in your deployment environment
- [ ] **Secrets management** - Store credentials securely:
  - Use environment variables from `.env` file (ensure `.env` is in `.gitignore`)
  - For production, consider using Docker secrets, Kubernetes secrets, or external secrets management tools
  - Never commit credentials to version control
- [ ] **Regular updates** - Keep Docker images and dependencies up to date

---

## Next Steps

- **Configuration options**: [Configuration Reference](configuration-reference.md)
- **Production deployment**: [Production Guide](production-guide.md)

[← Back to Observability Pipeline Guide](../index.md)
