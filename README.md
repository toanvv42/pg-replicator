# PostgreSQL Logical Replication Setup

This project demonstrates PostgreSQL logical replication for zero-downtime database migration from PostgreSQL 14 to PostgreSQL 16.

## Architecture

- **db_source**: PostgreSQL 14 (Publisher) - Port 5432
- **db_target**: PostgreSQL 16 (Subscriber) - Port 5433

## How This POC Works

This Proof of Concept (POC) demonstrates a zero-downtime database migration strategy using PostgreSQL's built-in logical replication feature. Here's a breakdown of its components and processes:

**Overall Architecture:**

The setup consists of two distinct PostgreSQL instances:
- **Source Database**: A PostgreSQL 14 instance (`db_source`) acting as the publisher. This is the database from which data originates.
- **Target Database**: A PostgreSQL 16 instance (`db_target`) acting as the subscriber. This is the database that receives data from the source.

**Logical Replication Process:**

Logical replication allows for the replication of data objects and their changes based on their replication identity (usually a primary key). Unlike physical replication, which deals with block-level changes, logical replication provides more flexibility, such as replicating between different PostgreSQL versions or replicating a subset of tables.

1.  **`PUBLICATION` on Source**:
    *   A `PUBLICATION` named `my_publication` is created on the source PostgreSQL 14 instance.
    *   This publication is defined for `ALL TABLES`, meaning any table created in the `sourcedb` database (or any table created in the future) will be included in the replication stream.

2.  **`SUBSCRIPTION` on Target**:
    *   A `SUBSCRIPTION` named `my_subscription` is created on the target PostgreSQL 16 instance.
    *   This subscription is configured to connect to the source database's `dsn` (Data Source Name), which includes the host (`db_source`), port (`5432`), user (`postgres`), password (`postgres`), and database name (`sourcedb`).
    *   It subscribes to the `my_publication` created on the source.

3.  **Data Synchronization**:
    *   Upon creation, the subscription initiates an initial data copy. All existing data from the tables included in the `my_publication` on the source is copied to the corresponding tables on the target.
    *   After the initial copy, any subsequent changes (INSERTs, UPDATEs, DELETEs) made to the published tables on the source are replicated to the target in real-time.

**Role of Main Components/Files:**

*   **`docker-compose.yml`**:
    *   This file is crucial for orchestrating the local development environment using Docker.
    *   It defines and configures two PostgreSQL services: `db_source` (PostgreSQL 14) and `db_target` (PostgreSQL 16).
    *   It manages container networking, allowing `db_target` to connect to `db_source`.
    *   It mounts initial SQL scripts (`init-source.sql`, `init-target.sql`) into the containers, which are executed when the containers start, setting up the initial database schemas and sample data.

*   **`Makefile`**:
    *   Provides a set of convenient `make` commands to simplify the management of the Docker environment and Kubernetes deployment.
    *   Includes targets for starting (`up`), stopping (`down`), setting up replication (`setup-replication`), and testing (`test-replication`).
    *   Also contains commands for deploying (`k8s-apply`), managing (`k8s-delete`, `k8s-logs`), and interacting with the setup on a Kubernetes cluster.

*   **SQL Scripts**:
    *   `init-source.sql`: Executed on `db_source` at startup. Defines the schema (e.g., `users`, `orders` tables) and inserts initial sample data into the source database.
    *   `init-target.sql`: Executed on `db_target` at startup. Defines the schema for the target database. It's important that the table structures match those on the source for replication to work correctly.
    *   `setup-replication.sql`: Contains the SQL command `CREATE PUBLICATION my_publication FOR ALL TABLES;`. This is run on the source database to create the publication.
    *   `setup-subscription.sql`: Contains the SQL command to create the subscription on the target database, connecting it to the source's publication.
    *   `test-replication.sql`: Includes DML statements (INSERTs, UPDATEs, DELETEs) that are run against the source database to generate changes after replication is set up.
    *   `verify-target.sql`: Contains SELECT queries to be run on the target database to check if the changes made by `test-replication.sql` on the source have been successfully replicated.

*   **`k8s/` Directory**:
    *   This directory houses Kubernetes manifest files (YAML) required to deploy the entire logical replication setup in a Kubernetes cluster. These resources are managed via Kustomize.
    *   `kustomization.yaml`: The Kustomize entry point. It defines the namespace and lists all resources that are part of the deployment.
    *   `postgres-configmap.yaml`: Stores configuration data, including the SQL initialization scripts (`init-source.sql`, `init-target.sql`), schema definitions, and replication setup scripts.
    *   `postgres-source.yaml` & `postgres-target.yaml`: Define `StatefulSets` for deploying the PostgreSQL 14 (source) and PostgreSQL 16 (target) instances, ensuring stable network identifiers and persistent storage.
    *   `postgres-secret.yaml`: Manages database credentials.
    *   `setup-replication-job.yaml`: Defines a Kubernetes `Job` that handles setting up the replication. This job executes scripts to create the `PUBLICATION` on the source database and the `SUBSCRIPTION` on the target database.
    *   `test-replication.yaml`: Defines a Kubernetes `Job` to apply DML changes (INSERTs, UPDATEs, DELETEs) to the source database for testing the replication setup. This is similar to the `test-replication.sql` script used in the Docker setup.
    *   (Optionally, `verify-replication-job.yaml` can be run manually to check if changes are replicated to the target, similar to `verify-target.sql`.)
    *   The Kubernetes deployment mirrors the functionality of the Docker Compose setup, providing a more production-like environment for demonstrating the migration.

**Goal of the POC:**

The primary goal of this POC is to demonstrate a practical approach to achieving a zero-downtime (or minimal downtime) database migration. By setting up logical replication from an older PostgreSQL version (14) to a newer version (16), data can be synchronized continuously. Once the target database is fully synchronized and ongoing changes are being replicated, applications can be switched over to the new database with a very short interruption, if any. This technique is invaluable for database upgrades or migrations to different infrastructure.

## Quick Start

1. **Start the containers:**
   ```bash
   docker-compose up -d
   ```

2. **Wait for both databases to be ready (about 30 seconds):**
   ```bash
   docker-compose logs -f
   ```

3. **Set up replication on source database:**
   ```bash
   docker exec -i postgres14_source psql -U postgres -d sourcedb < setup-replication.sql
   ```

4. **Set up subscription on target database:**
   ```bash
   docker exec -i postgres16_target psql -U postgres -d targetdb < setup-subscription.sql
   ```

5. **Test replication:**
   ```bash
   # Run test operations on source
   docker exec -i postgres14_source psql -U postgres -d sourcedb < test-replication.sql
   
   # Verify data on target
   docker exec -i postgres16_target psql -U postgres -d targetdb < verify-target.sql
   ```

## Manual Testing

### Connect to Source Database (PostgreSQL 14):
```bash
docker exec -it postgres14_source psql -U postgres -d sourcedb
```

### Connect to Target Database (PostgreSQL 16):
```bash
docker exec -it postgres16_target psql -U postgres -d targetdb
```

## Configuration Details

### Logical Replication Settings:
- `wal_level=logical`: Enables logical replication
- `max_replication_slots=4`: Maximum replication slots
- `max_wal_senders=4`: Maximum WAL sender processes
- `max_logical_replication_workers=4`: Maximum logical replication workers

### Network Configuration:
- Both containers are on the same Docker network
- Source accessible at `db_source:5432` from target
- External access: Source on `localhost:5432`, Target on `localhost:5433`

## Sample Data

The setup includes:
- `users` table with 5 sample users
- `orders` table with 6 sample orders
- Foreign key relationship between users and orders

## Monitoring Replication

### On Source (Publisher):
```sql
-- Check publications
SELECT * FROM pg_publication;

-- Check replication slots
SELECT * FROM pg_replication_slots;

-- Check replication statistics
SELECT * FROM pg_stat_replication;
```

### On Target (Subscriber):
```sql
-- Check subscriptions
SELECT * FROM pg_subscription;

-- Check subscription statistics
SELECT * FROM pg_stat_subscription;

-- Check replication origin status
SELECT * FROM pg_replication_origin_status;
```

## Troubleshooting

1. **Check container logs:**
   ```bash
   docker-compose logs db_source
   docker-compose logs db_target
   ```

2. **Verify network connectivity:**
   ```bash
   docker exec postgres16_target pg_isready -h db_source -p 5432
   ```

3. **Check replication lag:**
   ```sql
   -- On source
   SELECT * FROM pg_stat_replication;
   
   -- On target
   SELECT * FROM pg_stat_subscription;
   ```

## Cleanup

```bash
docker-compose down -v
```

This will stop and remove containers and volumes.

## Migration Workflow

1. **Initial Setup**: Both databases running with replication configured
2. **Sync Phase**: All existing data replicated to target
3. **Ongoing Replication**: New changes replicated in real-time
4. **Cutover**: Switch application to target database
5. **Cleanup**: Remove source database after verification

This setup simulates a zero-downtime migration where the application can be switched from the source to target database with minimal downtime.
