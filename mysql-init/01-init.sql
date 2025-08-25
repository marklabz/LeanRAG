-- MySQL initialization script for LeanRAG
-- This script sets up the default database and user permissions

-- Ensure the default database exists
CREATE DATABASE IF NOT EXISTS leanrag_default CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Use the default database
USE leanrag_default;

-- Grant all privileges to root user for any database (for dynamic database creation)
-- This allows database_utils.py to create databases based on working directory names
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;

-- Create a sample table structure (will be recreated by database_utils.py)
-- This is just for reference and testing connectivity
CREATE TABLE IF NOT EXISTS sample_test (
    id INT AUTO_INCREMENT PRIMARY KEY,
    test_field VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Insert a test record to verify the database is working
INSERT INTO sample_test (test_field) VALUES ('MySQL initialization successful');

-- Display initialization completion message
SELECT 'LeanRAG MySQL database initialized successfully' AS status;