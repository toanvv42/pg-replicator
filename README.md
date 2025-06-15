# PostgreSQL Logical Replication Setup

This project demonstrates PostgreSQL logical replication for zero-downtime database migration from PostgreSQL 14 to PostgreSQL 16.

## Architecture

- **db_source**: PostgreSQL 14 (Publisher) - Port 5432
- **db_target**: PostgreSQL 16 (Subscriber) - Port 5433

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
