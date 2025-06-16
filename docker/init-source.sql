-- Initialize source database (PostgreSQL 14)

-- Create a sample table with test data
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    email VARCHAR(100) UNIQUE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    product_name VARCHAR(200) NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    order_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert sample data
INSERT INTO users (name, email) VALUES 
    ('John Doe', 'john.doe@example.com'),
    ('Jane Smith', 'jane.smith@example.com'),
    ('Bob Johnson', 'bob.johnson@example.com'),
    ('Alice Brown', 'alice.brown@example.com'),
    ('Charlie Wilson', 'charlie.wilson@example.com');

INSERT INTO orders (user_id, product_name, amount) VALUES 
    (1, 'Laptop', 999.99),
    (2, 'Mouse', 29.99),
    (1, 'Keyboard', 79.99),
    (3, 'Monitor', 299.99),
    (4, 'Headphones', 149.99),
    (5, 'Webcam', 89.99);

-- Create publication for logical replication
-- This will be created after the database is fully initialized
-- We'll do this in a separate script to ensure proper timing
