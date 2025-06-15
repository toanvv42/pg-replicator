-- Test script to verify replication is working
-- Run these commands on the SOURCE database to test replication

-- Insert new data
INSERT INTO users (name, email) VALUES 
    ('Test User 1', 'test1@example.com'),
    ('Test User 2', 'test2@example.com');

-- Update existing data
UPDATE users SET name = 'John Doe (Updated)' WHERE id = 1;

-- Insert new orders
INSERT INTO orders (user_id, product_name, amount) VALUES 
    (1, 'Test Product', 199.99),
    (2, 'Another Test Product', 299.99);

-- Delete a record
DELETE FROM orders WHERE id = 6;

-- Check current data in source
SELECT 'SOURCE - Users:' as info;
SELECT * FROM users ORDER BY id;

SELECT 'SOURCE - Orders:' as info;
SELECT * FROM orders ORDER BY id;
