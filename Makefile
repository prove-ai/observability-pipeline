.PHONY: up down logs restart status clean

# Start the observability stack
up:
	cd docker-compose && docker compose up -d

# Stop the observability stack
down:
	cd docker-compose && docker compose down

# View logs from all services
logs:
	cd docker-compose && docker compose logs -f

# View logs from a specific service
logs-otel:
	cd docker-compose && docker compose logs -f otel-collector

logs-prometheus:
	cd docker-compose && docker compose logs -f prometheus

logs-grafana:
	cd docker-compose && docker compose logs -f grafana

logs-postgres:
	cd docker-compose && docker compose logs -f postgres

# Restart the stack
restart:
	cd docker-compose && docker compose restart

# Check status of containers
status:
	cd docker-compose && docker compose ps

# Clean up containers and volumes
clean:
	cd docker-compose && docker compose down -v --remove-orphans

# Build and start (if needed for custom images)
build:
	cd docker-compose && docker compose build

# Show help
help:
	@echo "Available commands:"
	@echo "  up          - Start the observability stack"
	@echo "  down        - Stop the observability stack"
	@echo "  logs        - View logs from all services"
	@echo "  logs-otel   - View logs from OTel Collector"
	@echo "  logs-prometheus - View logs from Prometheus"
	@echo "  logs-grafana - View logs from Grafana"
	@echo "  logs-postgres - View logs from PostgreSQL"
	@echo "  restart     - Restart the stack"
	@echo "  status      - Check status of containers"
	@echo "  clean       - Clean up containers and volumes"
	@echo "  build       - Build custom images"
	@echo "  help        - Show this help message"
