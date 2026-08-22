-- Migration: Add profile extension columns to users table (idempotent)
-- Uses a stored procedure guard to work on MySQL versions without IF NOT EXISTS for ADD COLUMN
USE auth_db;

DELIMITER $$
CREATE PROCEDURE add_profile_columns_proc()
BEGIN
	IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'auth_db' AND TABLE_NAME = 'users' AND COLUMN_NAME = 'cover_photo') THEN
		ALTER TABLE users ADD COLUMN cover_photo VARCHAR(255);
	END IF;
	IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'auth_db' AND TABLE_NAME = 'users' AND COLUMN_NAME = 'location') THEN
		ALTER TABLE users ADD COLUMN location VARCHAR(100);
	END IF;
	IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'auth_db' AND TABLE_NAME = 'users' AND COLUMN_NAME = 'website') THEN
		ALTER TABLE users ADD COLUMN website VARCHAR(255);
	END IF;
	IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'auth_db' AND TABLE_NAME = 'users' AND COLUMN_NAME = 'date_of_birth') THEN
		ALTER TABLE users ADD COLUMN date_of_birth DATE;
	END IF;
	IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'auth_db' AND TABLE_NAME = 'users' AND COLUMN_NAME = 'is_private') THEN
		ALTER TABLE users ADD COLUMN is_private BOOLEAN NOT NULL DEFAULT FALSE;
	END IF;
	IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'auth_db' AND TABLE_NAME = 'users' AND COLUMN_NAME = 'is_verified') THEN
		ALTER TABLE users ADD COLUMN is_verified BOOLEAN NOT NULL DEFAULT FALSE;
	END IF;

	-- Ensure defaults for existing rows
	UPDATE users SET is_private = FALSE WHERE is_private IS NULL;
	UPDATE users SET is_verified = FALSE WHERE is_verified IS NULL;
END$$
DELIMITER ;

CALL add_profile_columns_proc();
DROP PROCEDURE IF EXISTS add_profile_columns_proc;

SELECT 'Migration completed successfully!' AS status;
