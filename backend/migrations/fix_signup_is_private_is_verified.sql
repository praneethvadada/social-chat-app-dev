-- ============================================
-- FIX SIGNUP ISSUE - Add DEFAULT values for is_private and is_verified
-- ============================================
-- Date: January 6, 2026
-- Issue: Signup fails because is_private and is_verified fields don't have default values
-- Solution: Add DEFAULT FALSE to both columns

USE auth_db;

-- Procedure to safely drop columns if they exist
DELIMITER //

DROP PROCEDURE IF EXISTS DropColumnIfExists //

CREATE PROCEDURE DropColumnIfExists(
    IN tableName VARCHAR(255),
    IN columnName VARCHAR(255)
)
BEGIN
    DECLARE CONTINUE HANDLER FOR 1091 BEGIN END;
    SET @sql = CONCAT('ALTER TABLE ', tableName, ' DROP COLUMN ', columnName);
    PREPARE stmt FROM @sql;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
END //

DELIMITER ;

-- Drop duplicate is_verified column if it exists
CALL DropColumnIfExists('users', 'is_verified');

-- Drop is_private if exists to recreate properly  
CALL DropColumnIfExists('users', 'is_private');

-- Drop the procedure
DROP PROCEDURE DropColumnIfExists;

-- Now add both columns fresh with correct properties
ALTER TABLE users 
ADD COLUMN is_private BOOLEAN NOT NULL DEFAULT FALSE AFTER account_non_locked;

ALTER TABLE users 
ADD COLUMN is_verified BOOLEAN NOT NULL DEFAULT FALSE AFTER is_private;

-- Add indexes for performance
ALTER TABLE users 
ADD INDEX idx_is_private (is_private);

ALTER TABLE users 
ADD INDEX idx_is_verified (is_verified);

-- Verify the changes
SELECT COLUMN_NAME, IS_NULLABLE, COLUMN_DEFAULT 
FROM INFORMATION_SCHEMA.COLUMNS 
WHERE TABLE_NAME = 'users' AND (COLUMN_NAME = 'is_private' OR COLUMN_NAME = 'is_verified');

-- Update schema version
INSERT INTO schema_version (version, description) 
VALUES ('2.0.1', 'Fixed signup - Added is_private and is_verified columns with defaults')
ON DUPLICATE KEY UPDATE version=version;

COMMIT;
