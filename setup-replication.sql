-- Setup script for logical replication
-- Run this on the SOURCE database (PostgreSQL 14)

-- Create publication for all tables
CREATE PUBLICATION my_publication FOR ALL TABLES;

-- Verify publication was created
SELECT * FROM pg_publication;

-- Show current replication slots (should be empty initially)
SELECT * FROM pg_replication_slots;
