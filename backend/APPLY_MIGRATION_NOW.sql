-- =================================================
-- COMPLETE MIGRATION: Add All Missing Profile Columns
-- =================================================
-- INSTRUCTIONS:
-- 1. Open DBeaver or your MySQL client
-- 2. Connect to auth_db database
-- 3. Copy and paste the SQL below
-- 4. Execute it
-- =================================================

USE auth_db;

-- Add the missing columns to users table if they don't exist
-- First check if columns exist, then add them

-- Add is_private column
SET @col_exists = 0;
SELECT COUNT(*) INTO @col_exists 
FROM information_schema.COLUMNS 
WHERE TABLE_SCHEMA = 'auth_db' 
AND TABLE_NAME = 'users' 
AND COLUMN_NAME = 'is_private';

SET @query = IF(@col_exists = 0, 
    'ALTER TABLE users ADD COLUMN is_private BOOLEAN NOT NULL DEFAULT FALSE', 
    'SELECT "Column is_private already exists" AS message');
PREPARE stmt FROM @query;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Add is_verified column
SET @col_exists = 0;
SELECT COUNT(*) INTO @col_exists 
FROM information_schema.COLUMNS 
WHERE TABLE_SCHEMA = 'auth_db' 
AND TABLE_NAME = 'users' 
AND COLUMN_NAME = 'is_verified';

SET @query = IF(@col_exists = 0, 
    'ALTER TABLE users ADD COLUMN is_verified BOOLEAN NOT NULL DEFAULT FALSE', 
    'SELECT "Column is_verified already exists" AS message');
PREPARE stmt FROM @query;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Add cover_photo column
SET @col_exists = 0;
SELECT COUNT(*) INTO @col_exists 
FROM information_schema.COLUMNS 
WHERE TABLE_SCHEMA = 'auth_db' 
AND TABLE_NAME = 'users' 
AND COLUMN_NAME = 'cover_photo';

SET @query = IF(@col_exists = 0, 
    'ALTER TABLE users ADD COLUMN cover_photo VARCHAR(255)', 
    'SELECT "Column cover_photo already exists" AS message');
PREPARE stmt FROM @query;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Add location column
SET @col_exists = 0;
SELECT COUNT(*) INTO @col_exists 
FROM information_schema.COLUMNS 
WHERE TABLE_SCHEMA = 'auth_db' 
AND TABLE_NAME = 'users' 
AND COLUMN_NAME = 'location';

SET @query = IF(@col_exists = 0, 
    'ALTER TABLE users ADD COLUMN location VARCHAR(100)', 
    'SELECT "Column location already exists" AS message');
PREPARE stmt FROM @query;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Add website column
SET @col_exists = 0;
SELECT COUNT(*) INTO @col_exists 
FROM information_schema.COLUMNS 
WHERE TABLE_SCHEMA = 'auth_db' 
AND TABLE_NAME = 'users' 
AND COLUMN_NAME = 'website';

SET @query = IF(@col_exists = 0, 
    'ALTER TABLE users ADD COLUMN website VARCHAR(255)', 
    'SELECT "Column website already exists" AS message');
PREPARE stmt FROM @query;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Add date_of_birth column
SET @col_exists = 0;
SELECT COUNT(*) INTO @col_exists 
FROM information_schema.COLUMNS 
WHERE TABLE_SCHEMA = 'auth_db' 
AND TABLE_NAME = 'users' 
AND COLUMN_NAME = 'date_of_birth';

SET @query = IF(@col_exists = 0, 
    'ALTER TABLE users ADD COLUMN date_of_birth DATE', 
    'SELECT "Column date_of_birth already exists" AS message');
PREPARE stmt FROM @query;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Add show_read_receipts column
SET @col_exists = 0;
SELECT COUNT(*) INTO @col_exists 
FROM information_schema.COLUMNS 
WHERE TABLE_SCHEMA = 'auth_db' 
AND TABLE_NAME = 'users' 
AND COLUMN_NAME = 'show_read_receipts';

SET @query = IF(@col_exists = 0, 
    'ALTER TABLE users ADD COLUMN show_read_receipts BOOLEAN NOT NULL DEFAULT TRUE', 
    'SELECT "Column show_read_receipts already exists" AS message');
PREPARE stmt FROM @query;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Add show_activity_status column
SET @col_exists = 0;
SELECT COUNT(*) INTO @col_exists 
FROM information_schema.COLUMNS 
WHERE TABLE_SCHEMA = 'auth_db' 
AND TABLE_NAME = 'users' 
AND COLUMN_NAME = 'show_activity_status';

SET @query = IF(@col_exists = 0, 
    'ALTER TABLE users ADD COLUMN show_activity_status BOOLEAN NOT NULL DEFAULT TRUE', 
    'SELECT "Column show_activity_status already exists" AS message');
PREPARE stmt FROM @query;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Create indexes for frequently queried columns
CREATE INDEX IF NOT EXISTS idx_is_private ON users(is_private);
CREATE INDEX IF NOT EXISTS idx_show_read_receipts ON users(show_read_receipts);
CREATE INDEX IF NOT EXISTS idx_show_activity_status ON users(show_activity_status);

-- Verify all columns were added
SELECT 'Migration completed successfully!' AS status;
SHOW COLUMNS FROM users;
