# Deployment Methods Guide

[← Back to Advanced Setup](../ADVANCED_SETUP.md)

This guide provides step-by-step instructions for deploying the Observability Pipeline using two methods:

1. **Local Docker Compose** - For development, testing, or single-server deployments
2. **AWS EC2 via Ansible** - For automated production deployments to cloud infrastructure

## Deployment Strategy Selection

Choose your deployment method based on your requirements:

| Deployment Method        | Best For                                         | Time to Deploy | Complexity | Automation |
| ------------------------ | ------------------------------------------------ | -------------- | ---------- | ---------- |
| **Local Docker Compose** | Development, testing, single server              | 2 minutes      | Low        | Manual     |
| **Ansible to AWS EC2**   | Production, multi-server, repeatable deployments | 5-10 minutes   | Medium     | High       |

---

## Method 1: Local Docker Compose Deployment

### Prerequisites

| Requirement    | Minimum Version | Check Command            |
| -------------- | --------------- | ------------------------ |
| Docker         | 20.10+          | `docker --version`       |
| Docker Compose | 2.0+            | `docker compose version` |

### Deployment Strategy

**Choose your approach:**

1. **Direct Docker Compose** - Full control, explicit commands
2. **Makefile Shortcuts** - Convenience wrappers (recommended for daily use)

---

### Option A: Using Docker Compose Directly

**Location:** All commands run from `docker-compose/` directory

#### Available Profiles

Before deploying, choose your profile based on existing infrastructure:

| Profile         | Command                   | Services Deployed            | Use When                            |
| --------------- | ------------------------- | ---------------------------- | ----------------------------------- |
| `full`          | `--profile full`          | All 3 services               | Starting from scratch (recommended) |
| `no-prometheus` | `--profile no-prometheus` | Collector + VictoriaMetrics  | You have Prometheus                 |
| `no-vm`         | `--profile no-vm`         | Collector + Prometheus       | You have VictoriaMetrics            |
| `no-collector`  | `--profile no-collector`  | Prometheus + VictoriaMetrics | You have OTel Collector             |
| `vm-only`       | `--profile vm-only`       | VictoriaMetrics only         | You need storage only               |
| `prom-only`     | `--profile prom-only`     | Prometheus only              | You need scraper only               |

#### Command Reference

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

#### Common Docker Compose Variables

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

### Option B: Using the Makefile (Recommended)

**Location:** All commands run from **repository root**

The Makefile provides convenient shortcuts for common operations.

#### Quick Command Reference

| Command                     | Equivalent Docker Compose Command                              | Description          |
| --------------------------- | -------------------------------------------------------------- | -------------------- |
| `make up`                   | `cd docker-compose && docker compose --profile full up -d`     | Start full stack     |
| `make down`                 | `cd docker-compose && docker compose down`                     | Stop services        |
| `make restart`              | `cd docker-compose && docker compose restart`                  | Restart services     |
| `make status`               | `cd docker-compose && docker compose ps`                       | Check status         |
| `make logs`                 | `cd docker-compose && docker compose logs -f`                  | View all logs        |
| `make logs-otel`            | `cd docker-compose && docker compose logs -f otel-collector`   | View collector logs  |
| `make logs-prometheus`      | `cd docker-compose && docker compose logs -f prometheus`       | View Prometheus logs |
| `make logs-victoriametrics` | `cd docker-compose && docker compose logs -f victoriametrics`  | View VM logs         |
| `make clean`                | `cd docker-compose && docker compose down -v --remove-orphans` | Remove everything    |
| `make help`                 | -                                                              | Show all commands    |

#### Usage Examples

```bash
# From repository root

# Start the stack
make up

# Check if services are running
make status

# Watch logs in real-time
make logs-otel

# View VictoriaMetrics logs
make logs-victoriametrics

# Stop everything and clean up
make clean
```

#### Customizing the Makefile

To use a different profile, edit the `Makefile` in the repository root:

```makefile
# Change this line
up:
	cd docker-compose && docker compose --profile full up -d

# To this (for example, if you have Prometheus already)
up:
	cd docker-compose && docker compose --profile no-prometheus up -d
```

---

### Post-Deployment Verification

After deploying locally, verify all services are working:

#### 1. Check Container Status

```bash
# Using Docker Compose
cd docker-compose
docker compose ps

# Using Makefile
make status
```

**Expected Output:**

```
NAME              STATUS    PORTS
otel-collector    Up        0.0.0.0:4317->4317/tcp, ...
prometheus        Up        0.0.0.0:9090->9090/tcp
victoriametrics   Up        0.0.0.0:8428->8428/tcp
```

#### 2. Health Check Endpoints

| Service         | Endpoint                                    | Expected Response               |
| --------------- | ------------------------------------------- | ------------------------------- |
| OTel Collector  | `curl http://localhost:13133/health/status` | `{"status":"Server available"}` |
| Prometheus      | `curl http://localhost:9090/-/healthy`      | `Prometheus is Healthy.`        |
| VictoriaMetrics | `curl http://localhost:8428/health`         | `OK`                            |

#### 3. Test Trace Ingestion

```bash
# Install otel-cli if not already installed
# macOS: brew install equinix-labs/otel-cli/otel-cli
# Linux: See architecture.md for installation

# Send test trace
otel-cli span \
  --service "test-app" \
  --name "test-operation" \
  --endpoint http://localhost:4318/v1/traces \
  --protocol http/protobuf \
  --attrs "env=dev"

# Wait 15 seconds, then verify metrics appear
curl 'http://localhost:9090/api/v1/query?query=llm_traces_span_metrics_calls_total' | jq
```

---

## Method 2: AWS EC2 Deployment via Ansible

Ansible provides automated, repeatable deployments to AWS EC2 instances with a single command.

### When to Use This Method

- ✅ Production deployments
- ✅ Multiple servers requiring identical configuration
- ✅ Repeatable deployments (infrastructure as code)
- ✅ Remote server management without manual SSH
- ✅ Team environments requiring standardized setups

### Prerequisites Checklist

| Component            | Requirement                      | How to Check                 | Installation          |
| -------------------- | -------------------------------- | ---------------------------- | --------------------- |
| **Ansible**          | Version 2.9+                     | `ansible --version`          | See below             |
| **AWS EC2 Instance** | Ubuntu 20.04+ or Amazon Linux 2+ | SSH access working           | AWS Console           |
| **SSH Key**          | Private key for EC2 access       | `ssh -i key.pem ubuntu@<ip>` | AWS Console           |
| **Security Group**   | Ports configured                 | AWS Console                  | See below             |
| **Python on EC2**    | Python 3.6+                      | Auto-checked by Ansible      | Usually pre-installed |

#### Install Ansible Locally

```bash
# macOS
brew install ansible

# Ubuntu/Debian
sudo apt-get update
sudo apt-get install ansible

# CentOS/RHEL
sudo yum install ansible

# Via pip (any OS)
pip install ansible

# Verify installation
ansible --version
```

### AWS Security Group Configuration

You need to configure your EC2 security group to allow traffic on specific ports.

#### Required Ports for Production

| Port  | Protocol | Service              | Required For                    | Allow From                  |
| ----- | -------- | -------------------- | ------------------------------- | --------------------------- |
| 22    | TCP      | SSH                  | Ansible deployment              | Your IP                     |
| 4317  | TCP      | OTLP gRPC            | Application traces (production) | Your application servers    |
| 4318  | TCP      | OTLP HTTP            | Application traces (testing)    | Your application servers    |
| 8889  | TCP      | Spanmetrics exporter | Prometheus scraping             | Prometheus server           |
| 9090  | TCP      | Prometheus UI/API    | Queries and dashboards          | Your IP / Dashboard servers |
| 8428  | TCP      | VictoriaMetrics      | Long-term storage queries       | Your IP / Dashboard servers |
| 13133 | TCP      | Health checks        | Monitoring/load balancers       | Monitoring systems          |

#### Optional Monitoring Ports

| Port | Protocol | Service                    | Required For                | Allow From                           |
| ---- | -------- | -------------------------- | --------------------------- | ------------------------------------ |
| 8888 | TCP      | Collector internal metrics | Collector health monitoring | Prometheus (if monitoring collector) |

#### Debug Ports (NOT for Production)

| Port  | Protocol | Service | Required For            | Allow From   |
| ----- | -------- | ------- | ----------------------- | ------------ |
| 1888  | TCP      | pprof   | Performance profiling   | Your IP only |
| 55679 | TCP      | zpages  | Live pipeline debugging | Your IP only |

⚠️ **Security Best Practices:**

1. **NEVER expose debug ports (1888, 55679) to 0.0.0.0/0**
2. **Restrict 9090 and 8428** to specific IPs or VPN
3. **Use VPC security groups** to allow internal traffic between services
4. **Consider using a bastion host** for SSH access instead of direct SSH

**Example AWS Security Group Rules (Terraform):**

```hcl
resource "aws_security_group_rule" "otlp_grpc" {
  type              = "ingress"
  from_port         = 4317
  to_port           = 4317
  protocol          = "tcp"
  cidr_blocks       = ["10.0.0.0/16"]  # Your application VPC
  security_group_id = aws_security_group.observability.id
}

resource "aws_security_group_rule" "prometheus_ui" {
  type              = "ingress"
  from_port         = 9090
  to_port           = 9090
  protocol          = "tcp"
  cidr_blocks       = ["YOUR_IP/32"]  # Your specific IP only
  security_group_id = aws_security_group.observability.id
}
```

### Configuration Steps

#### Step 1: Prepare Your EC2 Instance Information

Gather this information before configuring Ansible:

| Variable                         | What It Is                       | Example                  | How to Find It                                   |
| -------------------------------- | -------------------------------- | ------------------------ | ------------------------------------------------ |
| **Inventory Name**               | Friendly name for your server    | `observability-pipeline` | Your choice                                      |
| **ansible_host**                 | Public IP or DNS of EC2 instance | `3.144.2.209`            | AWS Console → EC2 → Instance → Public IPv4       |
| **ansible_user**                 | SSH user for the instance        | `ubuntu`                 | `ubuntu` for Ubuntu, `ec2-user` for Amazon Linux |
| **ansible_ssh_private_key_file** | Path to your SSH private key     | `~/.ssh/my-key.pem`      | Local path to .pem file downloaded from AWS      |

#### Step 2: Edit Inventory File

Edit `playbooks/inventory.ini` with your EC2 details:

**Single Instance Deployment:**

```ini
[ec2_instances]
observability-pipeline ansible_host=YOUR_EC2_IP ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/YOUR_KEY.pem

[ec2_instances:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
```

**Multi-Instance Deployment (deploys to all listed):**

```ini
[ec2_instances]
obs-prod-us-east-1a ansible_host=1.2.3.4 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/prod-key.pem
obs-prod-us-east-1b ansible_host=5.6.7.8 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/prod-key.pem
obs-dev ansible_host=9.10.11.12 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/dev-key.pem

[ec2_instances:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no'
```

#### Step 3: Configure Deployment Variables

Edit `playbooks/deploy.yml` to customize your deployment:

**Available Configuration Variables:**

| Variable          | Default                       | Description                   | When to Change                  |
| ----------------- | ----------------------------- | ----------------------------- | ------------------------------- |
| `deploy_path`     | `/opt/observability-pipeline` | Installation directory on EC2 | If you want a different path    |
| `deploy_user`     | `ubuntu`                      | User to run services as       | For Amazon Linux use `ec2-user` |
| `compose_profile` | `full`                        | Which services to deploy      | See profile options below       |

**Profile Options:**

| Profile Value   | Services Deployed                        | Use When                 |
| --------------- | ---------------------------------------- | ------------------------ |
| `full`          | Collector + Prometheus + VictoriaMetrics | New deployment (default) |
| `no-prometheus` | Collector + VictoriaMetrics              | You have Prometheus      |
| `no-vm`         | Collector + Prometheus                   | You have VictoriaMetrics |
| `no-collector`  | Prometheus + VictoriaMetrics             | You have OTel Collector  |
| `vm-only`       | VictoriaMetrics only                     | Storage only             |
| `prom-only`     | Prometheus only                          | Scraping only            |

**Example Customization:**

```yaml
# In playbooks/deploy.yml
vars:
  deploy_user: "{{ ansible_user | default('ubuntu') }}"
  deploy_path: "/home/ubuntu/observability" # Custom path
  compose_profile: "no-prometheus" # Use existing Prometheus
```

---

### Deployment Strategy

Follow this sequence for a successful deployment:

```
1. Test Connectivity → 2. Validate Configuration → 3. Dry Run → 4. Deploy → 5. Verify
```

#### Step 1: Test Connectivity

Verify Ansible can reach your EC2 instance:

```bash
cd playbooks
ansible all -m ping
```

**Expected Output:**

```
observability-pipeline | SUCCESS => {
    "changed": false,
    "ping": "pong"
}
```

**If it fails:**

| Error                           | Cause                     | Solution                                      |
| ------------------------------- | ------------------------- | --------------------------------------------- |
| `Permission denied (publickey)` | Wrong SSH key             | Check `ansible_ssh_private_key_file` path     |
| `Host key verification failed`  | Known hosts issue         | Already handled by `StrictHostKeyChecking=no` |
| `Connection timeout`            | Security group blocks SSH | Allow port 22 from your IP                    |
| `Host unreachable`              | Wrong IP                  | Verify `ansible_host` value                   |

#### Step 2: Validate Ansible Syntax

Check your playbook for syntax errors:

```bash
ansible-playbook deploy.yml --syntax-check
```

**Expected Output:**

```
playbook: deploy.yml
```

#### Step 3: Dry Run (Preview Changes)

See what will change WITHOUT actually deploying:

```bash
ansible-playbook deploy.yml --check --diff
```

This shows:

- ✓ Files that will be created/modified
- ✓ Commands that will run
- ✓ Services that will start
- ✗ Doesn't actually make changes

#### Step 4: Deploy to EC2

Deploy the observability stack:

```bash
ansible-playbook deploy.yml
```

**Or use Makefile shortcuts:**

```bash
# From repository root

make ansible-ping           # Step 1: Test connectivity
make ansible-check          # Step 2: Validate syntax
make ansible-deploy-dry-run # Step 3: Dry run
make deploy                 # Step 4: Deploy
```

**Deployment Process (takes 5-10 minutes):**

1. ✓ Installs Docker and Docker Compose
2. ✓ Creates deployment directory
3. ✓ Copies configuration files
4. ✓ Starts Docker Compose with chosen profile
5. ✓ Verifies services are running

### Post-Deployment Verification

After Ansible completes, verify your deployment is working correctly.

#### Step 1: SSH to Your EC2 Instance

```bash
# Replace with your actual values
ssh -i ~/.ssh/YOUR_KEY.pem ubuntu@YOUR_EC2_IP
```

#### Step 2: Verify Docker Services

Once logged in to EC2:

```bash
# Navigate to deployment directory
cd /opt/observability-pipeline/docker-compose

# Check service status
docker compose ps

# View all logs
docker compose logs -f

# View specific service logs
docker compose logs -f otel-collector
```

**Expected Output:**

```
NAME              STATUS    PORTS
otel-collector    Up        0.0.0.0:4317->4317/tcp, ...
prometheus        Up        0.0.0.0:9090->9090/tcp
victoriametrics   Up        0.0.0.0:8428->8428/tcp
```

#### Step 3: Test Health Endpoints

**From your local machine**, test each service endpoint:

| Service         | Command                                       | Expected Response               |
| --------------- | --------------------------------------------- | ------------------------------- |
| OTel Collector  | `curl http://YOUR_EC2_IP:13133/health/status` | `{"status":"Server available"}` |
| Prometheus      | `curl http://YOUR_EC2_IP:9090/-/healthy`      | `Prometheus is Healthy.`        |
| VictoriaMetrics | `curl http://YOUR_EC2_IP:8428/health`         | `OK`                            |

**Quick test script:**

```bash
# Replace with your EC2 IP
EC2_IP="YOUR_EC2_IP"

echo "Testing OpenTelemetry Collector..."
curl -s http://$EC2_IP:13133/health/status | jq

echo "Testing Prometheus..."
curl -s http://$EC2_IP:9090/-/healthy

echo "Testing VictoriaMetrics..."
curl -s http://$EC2_IP:8428/health
```

#### Step 4: Send Test Trace

From your local machine:

```bash
# Replace YOUR_EC2_IP with actual IP
otel-cli span \
  --service "test-app" \
  --name "test-operation" \
  --endpoint http://YOUR_EC2_IP:4318/v1/traces \
  --protocol http/protobuf \
  --attrs "env=production,region=us-east-1"
```

#### Step 5: Verify Metrics Appear

Wait 15-20 seconds, then query Prometheus:

```bash
# Check if metrics exist
curl -s "http://YOUR_EC2_IP:9090/api/v1/query?query=llm_traces_span_metrics_calls_total" | jq

# Or open in browser
open http://YOUR_EC2_IP:9090
```

---

### Advanced Ansible Customization

#### Deploying to Multiple Environments

Create separate inventory files:

**`playbooks/inventory-prod.ini`:**

```ini
[ec2_instances]
obs-prod ansible_host=PROD_IP ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/prod-key.pem
```

**`playbooks/inventory-dev.ini`:**

```ini
[ec2_instances]
obs-dev ansible_host=DEV_IP ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/dev-key.pem
```

**Deploy to specific environment:**

```bash
# Deploy to production
ansible-playbook -i inventory-prod.ini deploy.yml

# Deploy to development
ansible-playbook -i inventory-dev.ini deploy.yml
```

#### Custom Variables Per Environment

Create variable files for each environment:

**`playbooks/vars-prod.yml`:**

```yaml
deploy_path: "/opt/observability-pipeline"
compose_profile: "full"
environment: "production"
```

**`playbooks/vars-dev.yml`:**

```yaml
deploy_path: "/home/ubuntu/observability"
compose_profile: "no-vm" # Dev uses external VictoriaMetrics
environment: "development"
```

**Use in deployment:**

```bash
ansible-playbook -i inventory-prod.ini deploy.yml -e @vars-prod.yml
```

#### Adding Custom Environment Variables

Edit `playbooks/deploy.yml` to inject environment variables:

```yaml
- name: Start Docker Compose services
  shell: sg docker -c "cd {{ deploy_path }}/docker-compose && docker compose --profile {{ compose_profile }} up -d"
  environment:
    PATH: "/usr/local/bin:/usr/bin:/bin"
    OTEL_EXPORTER_OTLP_ENDPOINT: "http://localhost:4318"
    OTEL_SERVICE_NAME: "observability-pipeline"
    ENVIRONMENT: "{{ environment | default('production') }}"
```

#### Rollback Strategy

If deployment fails or you need to rollback:

```bash
# Stop services
cd playbooks
ansible-playbook deploy.yml --tags "stop"

# Or manually via SSH
ssh -i ~/.ssh/key.pem ubuntu@EC2_IP
cd /opt/observability-pipeline/docker-compose
docker compose down

# Remove deployment
sudo rm -rf /opt/observability-pipeline
```

---

## Complete Verification Checklist

Use this checklist after any deployment (local or EC2):

### Infrastructure Checks

- [ ] All expected services are running (`docker compose ps`)
- [ ] No containers in "Restarting" or "Exited" state
- [ ] Correct deployment profile is active

### Health Checks

- [ ] OTel Collector health: `curl http://<host>:13133/health/status`
- [ ] Prometheus health: `curl http://<host>:9090/-/healthy`
- [ ] VictoriaMetrics health: `curl http://<host>:8428/health`

### Data Flow Checks

- [ ] Prometheus targets show "UP": `http://<host>:9090/targets`
- [ ] Collector is receiving traces (check logs)
- [ ] Metrics appear in Prometheus: `llm_traces_span_metrics_calls_total`
- [ ] Metrics are stored in VictoriaMetrics: `curl http://<host>:8428/api/v1/query?query=up`

### Network Checks

- [ ] Can send traces from external source to port 4317/4318
- [ ] Prometheus can scrape collector on port 8889
- [ ] VictoriaMetrics receives remote_write from Prometheus

### Security Checks (Production Only)

- [ ] Only required ports are open in security group
- [ ] Debug ports (1888, 55679) are NOT exposed publicly
- [ ] SSH access is restricted to specific IPs
- [ ] Prometheus/VM UIs are not publicly accessible (or behind auth)

---

## Troubleshooting

### Ansible Deployment Fails

| Problem                           | Possible Cause            | Solution                                                   |
| --------------------------------- | ------------------------- | ---------------------------------------------------------- |
| "Permission denied"               | Wrong SSH key             | Verify `ansible_ssh_private_key_file` path and permissions |
| "Host unreachable"                | Security group blocks SSH | Add inbound rule for port 22 from your IP                  |
| "Docker not found"                | Playbook failed mid-way   | Re-run `ansible-playbook deploy.yml`                       |
| "Failed to connect to repository" | EC2 has no internet       | Check EC2 route table and NAT gateway                      |

### Services Not Starting

```bash
# SSH to instance
ssh -i key.pem ubuntu@EC2_IP

# Check Docker is running
sudo systemctl status docker

# Check what profile is active
cd /opt/observability-pipeline/docker-compose
cat docker-compose.yaml | grep profiles

# Try restarting services
docker compose --profile full down
docker compose --profile full up -d

# Check logs for errors
docker compose logs --tail=100 otel-collector
```

### Metrics Not Appearing

```bash
# Check if collector is receiving traces
docker compose logs otel-collector | grep "Span #"

# Check if Prometheus is scraping
curl http://localhost:9090/api/v1/targets | jq

# Check if spanmetrics are exported
curl http://localhost:8889/metrics | grep llm_traces

# Check network connectivity
docker exec prometheus wget -O- http://otel-collector:8889/metrics
```

---

## Next Steps

### For Development Environments

1. ✅ Deployment complete
2. **Next:** [Send traces from your application](integration-patterns.md)
3. **Then:** [Configure dashboards and alerts](../README.md)

### For Production Environments

1. ✅ Deployment complete
2. **Next:** [Configure security (TLS, auth)](security.md)
3. **Then:** [Set up high availability](production-guide.md)
4. **Finally:** [Configure monitoring and backups](production-guide.md#monitoring-and-backups)

### Additional Resources

- **Configuration tuning**: [Configuration Reference](configuration-reference.md)
- **Integration patterns**: [Integration Patterns](integration-patterns.md)
- **Production best practices**: [Production Guide](production-guide.md)
- **Security hardening**: [Security Guide](security.md)

---

[← Back to Advanced Setup](../ADVANCED_SETUP.md)
