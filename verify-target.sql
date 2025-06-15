-- Verification script for target database
-- Run this on the TARGET database to verify replication

-- Check replicated data in target
SELECT 'TARGET - Users:' as info;
SELECT * FROM users ORDER BY id;

SELECT 'TARGET - Orders:' as info;
SELECT * FROM orders ORDER BY id;

-- Check subscription status
SELECT 'Subscription Status:' as info;
SELECT subname, subenabled, subconninfo FROM pg_subscription;

-- Check replication lag
SELECT 'Replication Status:' as info;
SELECT 
    application_name,
    state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    write_lag,
    flush_lag,
    replay_lag
FROM pg_stat_replication;
