.PHONY: up down logs restart status clean deploy ansible-ping ansible-check ansible-deploy-dry-run

# Default profile - can be overridden via make PROFILE=no-vm
PROFILE ?= full

# Start the observability stack
up:
	cd docker-compose && docker compose --profile $(PROFILE) up

# Stop the observability stack
down:
	cd docker-compose && docker compose --profile $(PROFILE) down

# View logs from all services
logs:
	cd docker-compose && docker compose --profile $(PROFILE) logs -f

# View logs from a specific service
logs-otel:
	cd docker-compose && docker compose logs -f otel-collector

logs-prometheus:
	cd docker-compose && docker compose logs -f prometheus

logs-victoriametrics:
	cd docker-compose && docker compose logs -f victoriametrics

# Restart the stack
restart:
	cd docker-compose && docker compose --profile $(PROFILE) restart

# Check status of containers
status:
	cd docker-compose && docker compose ps -a

# Clean up containers and volumes
clean:
	cd docker-compose && docker compose --profile $(PROFILE) down -v --remove-orphans

# Build and start (if needed for custom images)
build:
	cd docker-compose && docker compose --profile $(PROFILE) build

# Ansible deployment commands
deploy:
	cd playbooks && ansible-playbook deploy.yml

ansible-ping:
	cd playbooks && ansible all -m ping

ansible-check:
	cd playbooks && ansible-playbook deploy.yml --syntax-check

ansible-deploy-dry-run:
	cd playbooks && ansible-playbook deploy.yml --check --diff

# Show help
help:
	@echo "Available commands:"
	@echo ""
	@echo "Local Docker Compose commands:"
	@echo "  up          - Start the observability stack"
	@echo "  down        - Stop the observability stack"
	@echo "  logs        - View logs from all services"
	@echo "  logs-otel   - View logs from OTel Collector"
	@echo "  logs-prometheus - View logs from Prometheus"
	@echo "  restart     - Restart the stack"
	@echo "  status      - Check status of containers"
	@echo "  clean       - Clean up containers and volumes"
	@echo "  build       - Build custom images"
	@echo ""
	@echo "Ansible deployment commands:"
	@echo "  deploy      - Deploy to EC2 using Ansible playbook"
	@echo "  ansible-ping - Test SSH connectivity to EC2 instances"
	@echo "  ansible-check - Check Ansible playbook syntax"
	@echo "  ansible-deploy-dry-run - Run deployment in dry-run mode (check only)"
	@echo ""
	@echo "  help        - Show this help message"
