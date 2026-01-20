# Makefile for WordPress Farm Infrastructure
# Simplifies common deployment and management tasks

.PHONY: help init networks deploy-core deploy-observability deploy-security deploy-all status logs clean

# Default target
help:
	@echo "WordPress Farm Infrastructure - Makefile Commands"
	@echo ""
	@echo "Setup:"
	@echo "  make init              - Initialize Docker Swarm"
	@echo "  make networks          - Create Docker networks"
	@echo ""
	@echo "Deployment:"
	@echo "  make deploy-core       - Deploy core services"
	@echo "  make deploy-observability - Deploy observability stack"
	@echo "  make deploy-security   - Deploy security stack"
	@echo "  make deploy-all        - Deploy all stacks"
	@echo ""
	@echo "Management:"
	@echo "  make status            - Show service status"
	@echo "  make logs SERVICE=name - Show service logs"
	@echo "  make scale SERVICE=name REPLICAS=3 - Scale service"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean             - Remove all stacks (WARNING: destructive)"
	@echo ""

# Initialize Docker Swarm
init:
	@echo "Initializing Docker Swarm..."
	@docker swarm init --advertise-addr $$(hostname -I | awk '{print $$1}') || echo "Swarm already initialized"
	@echo "Swarm token for workers:"
	@docker swarm join-token worker -q

# Create networks
networks:
	@echo "Creating Docker networks..."
	@docker network create --driver overlay --attachable web 2>/dev/null || echo "Network 'web' already exists"
	@docker network create --driver overlay --attachable wordpress 2>/dev/null || echo "Network 'wordpress' already exists"
	@docker network create --driver overlay --attachable database 2>/dev/null || echo "Network 'database' already exists"
	@docker network create --driver overlay --attachable caching 2>/dev/null || echo "Network 'caching' already exists"
	@docker network create --driver overlay --attachable monitoring 2>/dev/null || echo "Network 'monitoring' already exists"
	@docker network create --driver overlay --attachable management 2>/dev/null || echo "Network 'management' already exists"
	@echo "Networks created successfully"

# Deploy core stack
deploy-core:
	@echo "Deploying core services..."
	@docker stack deploy -c docker-compose/swarm-stack.yml wordpress-farm
	@echo "Core services deployed. Check status with: make status"

# Deploy observability stack
deploy-observability:
	@echo "Deploying observability stack..."
	@docker stack deploy -c docker-compose/observability.yml observability
	@echo "Observability stack deployed"

# Deploy security stack
deploy-security:
	@echo "Deploying security stack..."
	@docker stack deploy -c docker-compose/security.yml security
	@echo "Security stack deployed"

# Deploy all stacks
deploy-all: networks deploy-core deploy-observability deploy-security
	@echo "All stacks deployed successfully!"

# Show service status
status:
	@echo "Service Status:"
	@docker service ls
	@echo ""
	@echo "Node Status:"
	@docker node ls

# Show service logs
logs:
	@if [ -z "$(SERVICE)" ]; then \
		echo "Usage: make logs SERVICE=service-name"; \
		docker service ls; \
	else \
		docker service logs -f $(SERVICE); \
	fi

# Scale service
scale:
	@if [ -z "$(SERVICE)" ] || [ -z "$(REPLICAS)" ]; then \
		echo "Usage: make scale SERVICE=service-name REPLICAS=3"; \
	else \
		docker service scale $(SERVICE)=$(REPLICAS); \
	fi

# Clean up all stacks (WARNING: destructive)
clean:
	@echo "WARNING: This will remove all stacks!"
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		docker stack rm wordpress-farm observability security || true; \
		echo "Stacks removed"; \
	fi

# Update service
update:
	@if [ -z "$(SERVICE)" ]; then \
		echo "Usage: make update SERVICE=service-name"; \
	else \
		docker service update --force $(SERVICE); \
	fi

# Show resource usage
resources:
	@echo "Container Resource Usage:"
	@docker stats --no-stream
	@echo ""
	@echo "Node Resource Usage:"
	@docker node ls --format "table {{.Hostname}}\t{{.Status}}\t{{.Availability}}"

# Backup databases
backup-db:
	@echo "Creating database backup..."
	@docker exec $$(docker ps -q -f name=mariadb-master-1) \
		mysqldump -u root -p$${DB_ROOT_PASSWORD} --all-databases | \
		gzip > backup-$$(date +%Y%m%d-%H%M%S).sql.gz
	@echo "Backup created"

# Show network information
networks-info:
	@echo "Docker Networks:"
	@docker network ls
	@echo ""
	@echo "Network Details:"
	@for net in web wordpress database caching monitoring management; do \
		echo "=== $$net ==="; \
		docker network inspect $$net --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null || echo "Network not found"; \
		echo ""; \
	done


