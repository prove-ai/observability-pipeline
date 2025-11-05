# Ansible Playbooks for Observability Pipeline Deployment

This directory contains Ansible playbooks to deploy the observability pipeline to AWS EC2 instances.

## Prerequisites

1. **Ansible installed locally** (version 2.9+)
   ```bash
   # macOS
   brew install ansible
   
   # Ubuntu/Debian
   sudo apt-get install ansible
   
   # Or via pip
   pip install ansible
   ```

2. **SSH access to EC2 instance**
   - Your EC2 instance should be running
   - You should have SSH key pair access
   - SSH should be allowed in your EC2 security group

3. **EC2 Security Group Configuration**
   Make sure your EC2 security group allows inbound traffic on:
   - Port 22 (SSH)
   - Port 3100 (Grafana)
   - Port 9090 (Prometheus)
   - Port 4317 (OTLP gRPC)
   - Port 4318 (OTLP HTTP)
   - Port 8888 (OTel Collector metrics)
   - Port 8889 (OTel Collector exporter metrics)

## Setup

1. **Configure inventory file**
   
   Edit `inventory.ini` and replace the placeholder with your EC2 instance details:
   
   ```ini
   [ec2_instances]
   observability-pipeline ansible_host=YOUR_EC2_IP_OR_DNS ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/your-key.pem
   ```
   
   - Replace `YOUR_EC2_IP_OR_DNS` with your EC2 instance's public IP or DNS name
   - Replace `ubuntu` with your EC2 instance's default user (usually `ubuntu` for Ubuntu, `ec2-user` for Amazon Linux)
   - Replace `~/.ssh/your-key.pem` with the path to your SSH private key

2. **Test SSH connectivity**
   
   ```bash
   ssh -i ~/.ssh/your-key.pem ubuntu@YOUR_EC2_IP_OR_DNS
   ```

## Deployment

### Basic Deployment

Run the playbook from the playbooks directory:

```bash
cd playbooks
ansible-playbook deploy.yml
```

### Deploy to Specific Host

If you have multiple hosts in your inventory:

```bash
ansible-playbook deploy.yml -l observability-pipeline
```

### Check Deployment Status

After deployment, you can check the status of services:

```bash
ansible-playbook deploy.yml --tags status
```

Or SSH into your instance and run:

```bash
cd /opt/observability-pipeline/docker-compose
docker compose ps
docker compose logs
```

## Post-Deployment

### Access Services

Once deployed, access the services:

- **Grafana**: http://YOUR_EC2_IP:3100
  - Username: `admin`
  - Password: `admin`
  
- **Prometheus**: http://YOUR_EC2_IP:9090

- **OTLP Endpoints**:
  - gRPC: `YOUR_EC2_IP:4317`
  - HTTP: `YOUR_EC2_IP:4318`

### Test OTLP Endpoint

Send a test span to verify the setup:

```bash
otel-cli span \
  --service "otel-test" \
  --name "demo-span" \
  --endpoint http://YOUR_EC2_IP:4318/v1/traces \
  --protocol http/protobuf
```

### View Logs

SSH into your instance and run:

```bash
cd /opt/observability-pipeline/docker-compose
docker compose logs -f
```

Or view logs for a specific service:

```bash
docker compose logs -f otel-collector
docker compose logs -f prometheus
docker compose logs -f grafana
```

## Management Commands

SSH into your EC2 instance and navigate to the deployment directory:

```bash
cd /opt/observability-pipeline/docker-compose
```

### Stop Services

```bash
docker compose down
```

### Start Services

```bash
docker compose up -d
```

### Restart Services

```bash
docker compose restart
```

### Update Configuration

1. Update configuration files locally
2. Re-run the playbook:
   ```bash
   ansible-playbook deploy.yml
   ```

### Clean Up

To remove all containers and volumes:

```bash
docker compose down -v --remove-orphans
```

## Troubleshooting

### Connection Issues

If you encounter connection issues:

1. Verify SSH access:
   ```bash
   ssh -i ~/.ssh/your-key.pem ubuntu@YOUR_EC2_IP
   ```

2. Check security group rules allow SSH (port 22)

3. Verify the user has sudo privileges

### Docker Installation Issues

If Docker installation fails:

1. Check if the instance OS is supported (Ubuntu 20.04+, Amazon Linux 2+)
2. Verify the instance has internet access
3. Check the playbook output for specific errors

### Service Not Starting

If services fail to start:

1. Check logs:
   ```bash
   docker compose logs
   ```

2. Verify port availability:
   ```bash
   sudo netstat -tulpn | grep -E '3100|9090|4317|4318'
   ```

3. Check Docker daemon status:
   ```bash
   sudo systemctl status docker
   ```

## Customization

### Change Deployment Path

Edit `deploy.yml` and modify the `deploy_path` variable:

```yaml
vars:
  deploy_path: "/opt/observability-pipeline"
```

### Change Docker Compose Version

Edit `deploy.yml` and modify the `docker_compose_version` variable:

```yaml
vars:
  docker_compose_version: "2.24.0"
```

## Security Notes

- Change default Grafana credentials after first login
- Consider using environment variables or secrets management for sensitive data
- Use security groups to restrict access to only necessary IPs
- Regularly update Docker images and packages
- Consider using AWS Secrets Manager or Parameter Store for credentials

