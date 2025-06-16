# PostgreSQL Logical Replication Makefile
# For zero-downtime migration from PostgreSQL 14 to PostgreSQL 16

# Environment variables
DOCKER_HOST ?= unix:///var/folders/xl/hmxcybps24vf396tlslx2kvh0000gn/T/podman/podman-machine-default-api.sock
EXPORT_DOCKER_HOST = export DOCKER_HOST='$(DOCKER_HOST)'

# Default target
.PHONY: help
help:
	@echo "PostgreSQL Logical Replication Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "Docker/Podman commands:"
	@echo "  start         - Start PostgreSQL containers"
	@echo "  stop          - Stop PostgreSQL containers"
	@echo "  restart       - Restart PostgreSQL containers"
	@echo "  clean         - Stop and remove containers, volumes, networks"
	@echo "  logs          - Show logs from both containers"
	@echo "  status        - Show container status"
	@echo "  setup         - Set up replication (publication and subscription)"
	@echo "  test          - Run test operations on source database"
	@echo "  verify        - Verify replication on target database"
	@echo "  shell-source  - Open psql shell on source database"
	@echo "  shell-target  - Open psql shell on target database"
	@echo "  monitor       - Monitor replication status"
	@echo "  full-setup    - Complete setup: start containers, setup replication, test and verify"
	@echo ""
	@echo "Kubernetes commands:"
	@echo "  manifests     - Generate Kubernetes manifests using kustomize with alpha plugins"
	@echo "  apply-k8s     - Apply Kubernetes manifests to the cluster"
	@echo "  delete-k8s    - Delete Kubernetes resources from the cluster"
	@echo "  k8s-setup     - Create a job to set up replication in Kubernetes"
	@echo "  k8s-test      - Create a job to test replication in Kubernetes"
	@echo "  k8s-monitor   - Monitor replication status in Kubernetes"
	@echo "  encrypt-secrets - Encrypt Kubernetes secrets using sops"
	@echo ""
	@echo "Test commands:"
	@echo "  test-docker-setup   - Install Python test dependencies"
	@echo "  test-docker-shell   - Run shell-based tests for Docker Compose"
	@echo "  test-docker-python  - Run Python-based tests for Docker Compose"
	@echo "  test-docker         - Run all Docker Compose tests"
	@echo "  test-k8s-suite      - Run Kubernetes test suite job"
	@echo "  test-k8s-python     - Run Python-based tests for Kubernetes"
	@echo "  test-k8s            - Run all Kubernetes tests"
	@echo "  test-all            - Run all tests (Docker + Kubernetes)"
	@echo "  test-status-docker  - Show Docker Compose replication status"
	@echo "  test-status-k8s     - Show Kubernetes replication status"
	@echo "  test-clean          - Clean up test artifacts"
	@echo ""
	@echo "Note: This Makefile uses Podman. Set DOCKER_HOST environment variable if needed."
	@echo "For Kubernetes manifests, kustomize build --enable-alpha-plugins is used."

# Start PostgreSQL containers
.PHONY: start
start:
	@echo "Starting PostgreSQL containers..."
	@$(EXPORT_DOCKER_HOST) && docker compose -f docker/docker-compose.yml up -d
	@echo "Waiting for databases to initialize (30 seconds)..."
	@sleep 30
	@$(EXPORT_DOCKER_HOST) && docker compose -f docker/docker-compose.yml ps

# Stop PostgreSQL containers
.PHONY: stop
stop:
	@echo "Stopping PostgreSQL containers..."
	@$(EXPORT_DOCKER_HOST) && docker compose -f docker/docker-compose.yml stop

# Restart PostgreSQL containers
.PHONY: restart
restart: stop start

# Clean up containers, volumes, networks
.PHONY: clean
clean:
	@echo "Cleaning up containers, volumes, and networks..."
	@$(EXPORT_DOCKER_HOST) && docker compose -f docker/docker-compose.yml down -v

# Show logs from both containers
.PHONY: logs
logs:
	@echo "Showing logs from PostgreSQL containers..."
	@$(EXPORT_DOCKER_HOST) && docker compose -f docker/docker-compose.yml logs

# Show container status
.PHONY: status
status:
	@echo "Container status:"
	@$(EXPORT_DOCKER_HOST) && docker compose -f docker/docker-compose.yml ps

# Set up replication (publication and subscription)
.PHONY: setup
setup:
	@echo "Setting up replication..."
	@echo "Creating publication on source database..."
	@$(EXPORT_DOCKER_HOST) && docker exec -i postgres14_source psql -U postgres -d sourcedb < docker/setup-replication.sql
	@echo "Creating subscription on target database..."
	@$(EXPORT_DOCKER_HOST) && docker exec -i postgres16_target psql -U postgres -d targetdb < docker/setup-subscription.sql

# Run test operations on source database
.PHONY: test
test:
	@echo "Running test operations on source database..."
	@$(EXPORT_DOCKER_HOST) && docker exec -i postgres14_source psql -U postgres -d sourcedb < docker/test-replication.sql

# Verify replication on target database
.PHONY: verify
verify:
	@echo "Verifying replication on target database..."
	@$(EXPORT_DOCKER_HOST) && docker exec -i postgres16_target psql -U postgres -d targetdb < docker/verify-target.sql

# Open psql shell on source database
.PHONY: shell-source
shell-source:
	@echo "Opening psql shell on source database..."
	@$(EXPORT_DOCKER_HOST) && docker exec -it postgres14_source psql -U postgres -d sourcedb

# Open psql shell on target database
.PHONY: shell-target
shell-target:
	@echo "Opening psql shell on target database..."
	@$(EXPORT_DOCKER_HOST) && docker exec -it postgres16_target psql -U postgres -d targetdb

# Monitor replication status
.PHONY: monitor
monitor:
	@echo "Monitoring replication status..."
	@echo "Source replication slots:"
	@$(EXPORT_DOCKER_HOST) && docker exec -i postgres14_source psql -U postgres -d sourcedb -c "SELECT slot_name, plugin, slot_type, active, restart_lsn FROM pg_replication_slots;"
	@echo "Source replication stats:"
	@$(EXPORT_DOCKER_HOST) && docker exec -i postgres14_source psql -U postgres -d sourcedb -c "SELECT application_name, state, sent_lsn, write_lsn, flush_lsn, replay_lsn FROM pg_stat_replication;"
	@echo "Target subscription status:"
	@$(EXPORT_DOCKER_HOST) && docker exec -i postgres16_target psql -U postgres -d targetdb -c "SELECT subname, subenabled, subconninfo FROM pg_subscription;"
	@echo "Target subscription stats:"
	@$(EXPORT_DOCKER_HOST) && docker exec -i postgres16_target psql -U postgres -d targetdb -c "SELECT * FROM pg_stat_subscription;"

# Complete setup: start containers, setup replication, test and verify
.PHONY: full-setup
full-setup: start setup test verify
	@echo "Full setup completed successfully!"

# Kubernetes commands
.PHONY: manifests apply-k8s delete-k8s k8s-setup k8s-test k8s-monitor encrypt-secrets

manifests:
	@echo "Generating Kubernetes manifests using kustomize..."
	@kustomize build --enable-alpha-plugins k8s > manifests.yaml
	@echo "Manifests generated in manifests.yaml"

apply-k8s: manifests
	@echo "Creating namespace if it doesn't exist..."
	@kubectl create namespace database-replication --dry-run=client -o yaml | kubectl apply -f -
	@echo "Applying Kubernetes manifests..."
	@kubectl apply -f manifests.yaml

delete-k8s: manifests
	@echo "Deleting Kubernetes resources..."
	@kubectl delete -f manifests.yaml

k8s-setup:
	@echo "Setting up replication in Kubernetes..."
	@kubectl apply -f k8s/setup-replication-job.yaml -n database-replication

k8s-test:
	@echo "Testing replication in Kubernetes..."
	@kubectl apply -f k8s/test-replication.yaml -n database-replication

k8s-monitor:
	@echo "Monitoring replication in Kubernetes..."
	@kubectl exec -it statefulset/postgres-source -n database-replication -- psql -U postgres -d sourcedb -c "SELECT slot_name, plugin, slot_type, active, restart_lsn FROM pg_replication_slots;"
	@kubectl exec -it statefulset/postgres-source -n database-replication -- psql -U postgres -d sourcedb -c "SELECT application_name, state, sent_lsn, write_lsn, flush_lsn, replay_lsn FROM pg_stat_replication;"
	@kubectl exec -it statefulset/postgres-target -n database-replication -- psql -U postgres -d targetdb -c "SELECT subname, subenabled, subconninfo FROM pg_subscription;"

encrypt-secrets:
	@echo "Encrypting secrets with sops..."
	@sops -e -i k8s/postgres-secret.yaml
	@echo "Secrets encrypted successfully"

# Test targets
test-docker-setup:
	@echo "Setting up test environment for Docker Compose..."
	@pip3 install -r tests/requirements.txt || echo "Please install Python dependencies manually"

test-docker-shell:
	@echo "Running shell-based tests for Docker Compose..."
	@chmod +x tests/test_docker_compose.sh
	@./tests/test_docker_compose.sh

test-docker-python:
	@echo "Running Python-based tests for Docker Compose..."
	@python3 -m pytest tests/test_replication.py::TestDockerCompose -v

test-docker: test-docker-shell test-docker-python
	@echo "All Docker Compose tests completed"

test-k8s-suite:
	@echo "Running Kubernetes test suite..."
	@kubectl apply -f k8s/test-suite-job.yaml -n database-replication
	@kubectl wait --for=condition=complete job/replication-test-suite --timeout=600s -n database-replication || true
	@kubectl logs job/replication-test-suite -n database-replication

test-k8s-python:
	@echo "Running Python-based tests for Kubernetes..."
	@python3 -m pytest tests/test_replication.py::TestKubernetes -v

test-k8s: test-k8s-suite
	@echo "All Kubernetes tests completed"

test-all: test-docker test-k8s
	@echo "All tests completed"

test-status-docker:
	@echo "Showing Docker Compose replication status..."
	@./tests/test_docker_compose.sh --status

test-status-k8s:
	@echo "Showing Kubernetes replication status..."
	@make k8s-monitor

# Test cleanup
test-clean:
	@echo "Cleaning up test artifacts..."
	@rm -rf tests/reports/
	@kubectl delete job replication-test-suite -n database-replication --ignore-not-found=true
