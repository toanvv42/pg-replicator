-- Setup script for subscription
-- Run this on the TARGET database (PostgreSQL 16)

-- Create subscription to replicate from source
CREATE SUBSCRIPTION my_subscription
    CONNECTION 'host=db_source port=5432 dbname=sourcedb user=postgres password=postgres'
    PUBLICATION my_publication
    WITH (copy_data = true, create_slot = true);

-- Verify subscription was created
SELECT * FROM pg_subscription;

-- Check subscription status
SELECT * FROM pg_stat_subscription;

-- Show replication origin status
SELECT * FROM pg_replication_origin_status;
