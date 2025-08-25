-- MySQL initialization script for LeanRAG
-- This script is automatically executed when the MySQL container starts for the first time

-- Create the default database if it doesn't exist
CREATE DATABASE IF NOT EXISTS leanrag_default CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Switch to the leanrag_default database
USE leanrag_default;

-- Note: The actual table creation is handled by database_utils.py
-- This script just ensures the database exists and is properly configured

-- Set proper character set and collation for the session
SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Set SQL mode for compatibility
SET sql_mode = 'STRICT_TRANS_TABLES,NO_ZERO_DATE,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO';

-- Create a test table to verify the setup works
CREATE TABLE IF NOT EXISTS setup_test (
    id INT AUTO_INCREMENT PRIMARY KEY,
    test_message VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Insert a test message
INSERT INTO setup_test (test_message) VALUES ('MySQL setup completed successfully for LeanRAG');

-- Display setup completion message
SELECT 'LeanRAG MySQL initialization completed' as status;