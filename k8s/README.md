# PostgreSQL Logical Replication on Kubernetes

This directory contains Kubernetes manifests for deploying a PostgreSQL logical replication setup to demonstrate zero-downtime database migration from PostgreSQL 14 to PostgreSQL 16.

## Architecture

- **postgres-source**: PostgreSQL 14 (Publisher) StatefulSet
- **postgres-target**: PostgreSQL 16 (Subscriber) StatefulSet
- **setup-replication-job**: Job to set up publication and subscription
- **test-replication-job**: Job to test the replication
- **verify-replication-job**: Job to verify replication is working correctly

## Prerequisites

- Kubernetes cluster (tested with kind)
- kubectl CLI tool
- kustomize with alpha plugins support

## Quick Start

### 1. Deploy the PostgreSQL Replication Setup

```bash
# Create the namespace and apply all resources
make apply-k8s

# Or manually:
kubectl create namespace database-replication
kustomize build --enable-alpha-plugins k8s | kubectl apply -f -
```

### 2. Verify Deployment

```bash
# Check that all pods are running
kubectl get pods -n database-replication

# Check StatefulSets
kubectl get statefulsets -n database-replication
```

### 3. Monitor Replication Status

```bash
# Use the Makefile target
make k8s-monitor

# Or manually:
kubectl exec -it statefulset/postgres-source -n database-replication -- \
  psql -U postgres -d sourcedb -c "SELECT slot_name, plugin, slot_type, active, restart_lsn FROM pg_replication_slots;"

kubectl exec -it statefulset/postgres-source -n database-replication -- \
  psql -U postgres -d sourcedb -c "SELECT application_name, state, sent_lsn, write_lsn, flush_lsn, replay_lsn FROM pg_stat_replication;"

kubectl exec -it statefulset/postgres-target -n database-replication -- \
  psql -U postgres -d targetdb -c "SELECT subname, subenabled, subconninfo FROM pg_subscription;"
```

### 4. Test Replication

```bash
# Create a verification job
kubectl apply -f k8s/verify-replication-job.yaml -n database-replication

# Check the job logs
kubectl logs job/verify-replication -n database-replication
```

## Manifest Details

### 1. StatefulSets

- **postgres-source.yaml**: PostgreSQL 14 with logical replication enabled
- **postgres-target.yaml**: PostgreSQL 16 with logical replication enabled

Both StatefulSets are configured with:
- Persistent storage using PVCs
- Proper replication settings (wal_level=logical, etc.)
- Init scripts mounted from ConfigMap

### 2. ConfigMap

- **postgres-configmap.yaml**: Contains:
  - Database initialization scripts
  - Replication setup scripts
  - Schema definitions

### 3. Secret

- **postgres-secret.yaml**: Contains database credentials
  - Can be encrypted using sops with `make encrypt-secrets`

### 4. Jobs

- **setup-replication-job.yaml**: Creates publication and subscription
- **test-replication-job.yaml**: Tests replication with sample data
- **verify-replication-job.yaml**: Comprehensive verification of replication

## Security

For production use, consider:

1. Encrypting secrets using sops:
   ```bash
   make encrypt-secrets
   ```

2. Using a proper secret management solution like Vault

3. Setting up network policies to restrict access

## Monitoring

For production deployments, consider adding:

1. Prometheus metrics for PostgreSQL
2. Custom alerts for replication lag
3. Grafana dashboards for visualization

## Troubleshooting

### Replication Not Working

1. Check if both databases are running:
   ```bash
   kubectl get pods -n database-replication
   ```

2. Verify publication was created:
   ```bash
   kubectl exec -it statefulset/postgres-source -n database-replication -- \
     psql -U postgres -d sourcedb -c "SELECT * FROM pg_publication;"
   ```

3. Verify subscription was created:
   ```bash
   kubectl exec -it statefulset/postgres-target -n database-replication -- \
     psql -U postgres -d targetdb -c "SELECT * FROM pg_subscription;"
   ```

4. Check for errors in logs:
   ```bash
   kubectl logs statefulset/postgres-source -n database-replication
   kubectl logs statefulset/postgres-target -n database-replication
   ```

### Replication Lag

If replication is lagging:

1. Check replication status:
   ```bash
   kubectl exec -it statefulset/postgres-source -n database-replication -- \
     psql -U postgres -d sourcedb -c "SELECT * FROM pg_stat_replication;"
   ```

2. Check target subscription status:
   ```bash
   kubectl exec -it statefulset/postgres-target -n database-replication -- \
     psql -U postgres -d targetdb -c "SELECT * FROM pg_stat_subscription;"
   ```

## Cleanup

To remove all resources:

```bash
# Using Makefile
make delete-k8s

# Or manually
kubectl delete namespace database-replication
```

## Generating Manifests

The manifests are managed using kustomize with alpha plugins enabled:

```bash
# Generate manifests
kustomize build --enable-alpha-plugins k8s > manifests.yaml
```

## Production Considerations

For a production deployment:

1. **Resource Limits**: Add appropriate CPU and memory limits
2. **High Availability**: Configure proper HA setup with replicas
3. **Backup Strategy**: Implement regular backups
4. **Network Security**: Add network policies
5. **Secret Management**: Use a proper secret management solution
6. **Monitoring**: Add comprehensive monitoring and alerting
