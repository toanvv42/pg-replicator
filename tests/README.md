# PostgreSQL Logical Replication Test Suite

This directory contains comprehensive automated test cases for PostgreSQL logical replication setups in both Docker Compose and Kubernetes environments.

## Overview

The test suite verifies:
- Database connectivity and health
- Replication slot and publication creation on source
- Active subscription on target
- Data replication correctness and timing
- Replication performance and lag monitoring

## Test Components

### 1. Python Test Suite (`test_replication.py`)

A comprehensive pytest-based test suite with:
- **TestDockerCompose**: Tests for Docker Compose environment (localhost:5432/5433)
- **TestKubernetes**: Tests for Kubernetes environment (service DNS names)
- Detailed logging and error reporting
- Configurable timeouts and thresholds
- CLI interface for flexible execution

#### Features:
- Database connectivity verification using `pg_isready` and direct connections
- Replication setup validation (publications, subscriptions, slots)
- Data replication testing with real INSERT/UPDATE/DELETE operations
- Performance monitoring with replication lag checks
- Comprehensive error handling and reporting

#### Usage:
```bash
# Install dependencies
pip install -r tests/requirements.txt

# Run Docker Compose tests
python tests/test_replication.py --mode docker --verbose

# Run Kubernetes tests
python tests/test_replication.py --mode kubernetes --timeout 120

# Run with pytest
pytest tests/test_replication.py::TestDockerCompose -v
pytest tests/test_replication.py::TestKubernetes -v
```

### 2. Shell Script (`test_docker_compose.sh`)

A lightweight Bash script for Docker Compose environments:
- Fast health checks using PostgreSQL client tools
- Colored output for easy status identification
- Command-line options for verbosity and timeout
- Suitable for CI/CD integration

#### Usage:
```bash
# Make executable and run
chmod +x tests/test_docker_compose.sh
./tests/test_docker_compose.sh

# With options
./tests/test_docker_compose.sh --verbose --timeout 60
./tests/test_docker_compose.sh --status  # Status only
```

### 3. Kubernetes Test Job (`k8s/test-suite-job.yaml`)

A Kubernetes Job that runs comprehensive tests within the cluster:
- Uses PostgreSQL 14 image with required tools
- Installs Python dependencies and runs embedded test script
- Accesses databases via service DNS names
- Configurable via ConfigMaps and Secrets

#### Usage:
```bash
# Apply the job
kubectl apply -f k8s/test-suite-job.yaml -n database-replication

# Monitor progress
kubectl logs job/replication-test-suite -f -n database-replication

# Check completion
kubectl get job replication-test-suite -n database-replication
```

## Configuration

### Environment Variables

#### Docker Compose Tests:
- `SOURCE_HOST`: Source database host (default: localhost)
- `SOURCE_PORT`: Source database port (default: 5432)
- `TARGET_HOST`: Target database host (default: localhost)
- `TARGET_PORT`: Target database port (default: 5433)
- `POSTGRES_USER`: Database user (default: postgres)
- `POSTGRES_PASSWORD`: Database password (default: postgres)
- `SOURCE_DB`: Source database name (default: sourcedb)
- `TARGET_DB`: Target database name (default: targetdb)

#### Kubernetes Tests:
- `SOURCE_HOST`: Source service name (default: postgres-source)
- `TARGET_HOST`: Target service name (default: postgres-target)
- Other variables same as Docker Compose

### Test Parameters:
- `TIMEOUT`: Database connection timeout (default: 60s)
- `REPLICATION_WAIT`: Time to wait for replication (default: 10s)
- `LAG_THRESHOLD`: Acceptable replication lag in bytes (default: 1024)

## Makefile Integration

The project Makefile includes convenient test targets:

```bash
# Setup test environment
make test-docker-setup

# Run Docker Compose tests
make test-docker-shell      # Shell script only
make test-docker-python     # Python tests only
make test-docker           # All Docker tests

# Run Kubernetes tests
make test-k8s-suite        # Kubernetes Job
make test-k8s-python       # Python tests
make test-k8s             # All Kubernetes tests

# Run all tests
make test-all

# Check status
make test-status-docker
make test-status-k8s

# Cleanup
make test-clean
```

## CI/CD Integration

### GitHub Actions

The `.github/workflows/test-replication.yml` workflow provides:
- Automated testing on push/PR to main branches
- Daily scheduled runs
- Separate jobs for Docker Compose and Kubernetes
- Test result artifacts and reports
- PostgreSQL service containers for Docker Compose tests
- Kind cluster setup for Kubernetes tests

### Test Reports

Tests generate HTML reports using pytest-html:
- `tests/reports/docker-compose-report.html`
- `tests/reports/kubernetes-report.html`
- Kubernetes logs collected in `tests/reports/k8s-logs/`

## Best Practices

### 1. Test Coverage
- **Connectivity**: Verify both databases are accessible
- **Setup**: Confirm replication components exist and are active
- **Data Flow**: Test actual data replication with real operations
- **Performance**: Monitor replication lag and streaming status

### 2. Test Isolation
- Use unique test data with timestamps to avoid conflicts
- Clean up test data after each run
- Use separate test databases when possible

### 3. Error Handling
- Implement proper timeouts for all operations
- Provide detailed error messages with context
- Log intermediate steps for debugging
- Fail fast on critical errors

### 4. Monitoring Integration
- Include replication status checks in regular monitoring
- Set up alerts for replication failures or high lag
- Monitor test results in CI/CD pipelines
- Track test execution time and success rates

## Troubleshooting

### Common Issues

1. **Connection Timeouts**
   - Increase timeout values
   - Check network connectivity
   - Verify service/container status

2. **Replication Not Working**
   - Check PostgreSQL configuration (wal_level, max_replication_slots)
   - Verify publication and subscription setup
   - Check replication slot status

3. **Test Data Not Replicating**
   - Ensure tables are included in publication
   - Check subscription is enabled and active
   - Verify no replication conflicts

4. **Kubernetes Tests Failing**
   - Check pod status and logs
   - Verify service DNS resolution
   - Confirm ConfigMap and Secret values

### Debug Commands

```bash
# Check replication status manually
make monitor                    # Docker Compose
make k8s-monitor               # Kubernetes

# View detailed logs
docker logs postgres14_source  # Docker Compose
kubectl logs -l app=postgres-source -n database-replication  # Kubernetes

# Run tests with maximum verbosity
./tests/test_docker_compose.sh --verbose
python tests/test_replication.py --mode docker --verbose --timeout 120
```

## Dependencies

### Python Requirements
- `psycopg2-binary>=2.9.0`: PostgreSQL adapter
- `pytest>=7.0.0`: Testing framework
- `pytest-html>=3.1.0`: HTML report generation
- `pytest-xdist>=2.5.0`: Parallel test execution

### System Requirements
- PostgreSQL client tools (`psql`, `pg_isready`)
- Python 3.7+
- Docker/Podman (for Docker Compose tests)
- kubectl and cluster access (for Kubernetes tests)

## Security Considerations

- Test credentials are hardcoded for simplicity
- Use proper secret management in production
- Encrypt sensitive configuration with tools like sops
- Limit test database access and permissions
- Regularly rotate test credentials

## Future Enhancements

- Add schema change replication tests
- Implement performance benchmarking
- Add multi-table replication scenarios
- Include conflict resolution testing
- Add automated rollback testing
- Implement continuous monitoring dashboards
