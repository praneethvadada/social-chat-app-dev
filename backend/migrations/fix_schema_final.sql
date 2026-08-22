-- ============================================
-- FIX: Ensure all required columns exist in users table with proper defaults
-- ============================================
USE auth_db;

-- Add missing columns if they don't exist
-- First, add is_private if missing
SET @check_is_private = (
    SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_NAME = 'users' AND COLUMN_NAME = 'is_private'
);

SET @sql_is_private = IF(
    @check_is_private = 0,
    "ALTER TABLE users ADD COLUMN is_private BOOLEAN NOT NULL DEFAULT FALSE AFTER account_non_locked",
    "SELECT 1"
);

PREPARE stmt FROM @sql_is_private;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Add is_verified if missing
SET @check_is_verified = (
    SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_NAME = 'users' AND COLUMN_NAME = 'is_verified'
);

SET @sql_is_verified = IF(
    @check_is_verified = 0,
    "ALTER TABLE users ADD COLUMN is_verified BOOLEAN NOT NULL DEFAULT FALSE AFTER is_private",
    "SELECT 1"
);

PREPARE stmt FROM @sql_is_verified;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Add is_online if missing
SET @check_is_online = (
    SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_NAME = 'users' AND COLUMN_NAME = 'is_online'
);

SET @sql_is_online = IF(
    @check_is_online = 0,
    "ALTER TABLE users ADD COLUMN is_online BOOLEAN NOT NULL DEFAULT FALSE AFTER is_verified",
    "SELECT 1"
);

PREPARE stmt FROM @sql_is_online;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Add last_seen_at if missing
SET @check_last_seen = (
    SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_NAME = 'users' AND COLUMN_NAME = 'last_seen_at'
);

SET @sql_last_seen = IF(
    @check_last_seen = 0,
    "ALTER TABLE users ADD COLUMN last_seen_at DATETIME AFTER is_online",
    "SELECT 1"
);

PREPARE stmt FROM @sql_last_seen;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Drop any unwanted columns
-- Drop show_activity_status if it exists
SET @check_show_activity = (
    SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_NAME = 'users' AND COLUMN_NAME = 'show_activity_status'
);

SET @sql_drop_activity = IF(
    @check_show_activity > 0,
    "ALTER TABLE users DROP COLUMN show_activity_status",
    "SELECT 1"
);

PREPARE stmt FROM @sql_drop_activity;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Drop show_read_receipts if it exists
SET @check_show_read = (
    SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS 
    WHERE TABLE_NAME = 'users' AND COLUMN_NAME = 'show_read_receipts'
);

SET @sql_drop_read = IF(
    @check_show_read > 0,
    "ALTER TABLE users DROP COLUMN show_read_receipts",
    "SELECT 1"
);

PREPARE stmt FROM @sql_drop_read;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Verify final schema
SELECT COLUMN_NAME, IS_NULLABLE, COLUMN_DEFAULT, DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS 
WHERE TABLE_NAME = 'users' 
ORDER BY ORDINAL_POSITION;

-- Update schema version
INSERT INTO schema_version (version, description) 
VALUES ('2.0.2', 'Fixed schema - Ensured all required columns exist with proper defaults')
ON DUPLICATE KEY UPDATE version=version;

COMMIT;
