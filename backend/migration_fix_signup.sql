USE auth_db;

-- MySQL-compatible migration without IF NOT EXISTS (works on MySQL 5.7/8.0)
DELIMITER $$

DROP PROCEDURE IF EXISTS apply_fix_signup $$
CREATE PROCEDURE apply_fix_signup()
BEGIN
	DECLARE col_exists INT DEFAULT 0;
	DECLARE idx_exists INT DEFAULT 0;
	DECLARE col_needs_default INT DEFAULT 0;

	-- is_private
	SELECT COUNT(*) INTO col_exists FROM information_schema.COLUMNS
		WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND COLUMN_NAME = 'is_private';
	IF col_exists = 0 THEN
		ALTER TABLE users ADD COLUMN is_private TINYINT(1) NOT NULL DEFAULT 0;
	END IF;

	-- ensure default for is_private if it exists but missing default
	SELECT COUNT(*) INTO col_needs_default FROM information_schema.COLUMNS
		WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND COLUMN_NAME = 'is_private'
		  AND IS_NULLABLE = 'NO' AND COLUMN_DEFAULT IS NULL;
	IF col_needs_default > 0 THEN
		ALTER TABLE users MODIFY COLUMN is_private TINYINT(1) NOT NULL DEFAULT 0;
	END IF;

	-- is_verified
	SELECT COUNT(*) INTO col_exists FROM information_schema.COLUMNS
		WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND COLUMN_NAME = 'is_verified';
	IF col_exists = 0 THEN
		ALTER TABLE users ADD COLUMN is_verified TINYINT(1) NOT NULL DEFAULT 0;
	END IF;

	-- ensure default for is_verified if it exists but missing default
	SELECT COUNT(*) INTO col_needs_default FROM information_schema.COLUMNS
		WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND COLUMN_NAME = 'is_verified'
		  AND IS_NULLABLE = 'NO' AND COLUMN_DEFAULT IS NULL;
	IF col_needs_default > 0 THEN
		ALTER TABLE users MODIFY COLUMN is_verified TINYINT(1) NOT NULL DEFAULT 0;
	END IF;

	-- show_read_receipts
	SELECT COUNT(*) INTO col_exists FROM information_schema.COLUMNS
		WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND COLUMN_NAME = 'show_read_receipts';
	IF col_exists = 0 THEN
		ALTER TABLE users ADD COLUMN show_read_receipts TINYINT(1) NOT NULL DEFAULT 1;
	END IF;

	-- ensure default for show_read_receipts if it exists but missing default
	SELECT COUNT(*) INTO col_needs_default FROM information_schema.COLUMNS
		WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND COLUMN_NAME = 'show_read_receipts'
		  AND IS_NULLABLE = 'NO' AND COLUMN_DEFAULT IS NULL;
	IF col_needs_default > 0 THEN
		ALTER TABLE users MODIFY COLUMN show_read_receipts TINYINT(1) NOT NULL DEFAULT 1;
	END IF;

	-- show_activity_status
	SELECT COUNT(*) INTO col_exists FROM information_schema.COLUMNS
		WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND COLUMN_NAME = 'show_activity_status';
	IF col_exists = 0 THEN
		ALTER TABLE users ADD COLUMN show_activity_status TINYINT(1) NOT NULL DEFAULT 1;
	END IF;

	-- ensure default for show_activity_status if it exists but missing default
	SELECT COUNT(*) INTO col_needs_default FROM information_schema.COLUMNS
		WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND COLUMN_NAME = 'show_activity_status'
		  AND IS_NULLABLE = 'NO' AND COLUMN_DEFAULT IS NULL;
	IF col_needs_default > 0 THEN
		ALTER TABLE users MODIFY COLUMN show_activity_status TINYINT(1) NOT NULL DEFAULT 1;
	END IF;

	-- cover_photo
	SELECT COUNT(*) INTO col_exists FROM information_schema.COLUMNS
		WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND COLUMN_NAME = 'cover_photo';
	IF col_exists = 0 THEN
		ALTER TABLE users ADD COLUMN cover_photo VARCHAR(255) NULL;
	END IF;

	-- location
	SELECT COUNT(*) INTO col_exists FROM information_schema.COLUMNS
		WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND COLUMN_NAME = 'location';
	IF col_exists = 0 THEN
		ALTER TABLE users ADD COLUMN location VARCHAR(100) NULL;
	END IF;

	-- website
	SELECT COUNT(*) INTO col_exists FROM information_schema.COLUMNS
		WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND COLUMN_NAME = 'website';
	IF col_exists = 0 THEN
		ALTER TABLE users ADD COLUMN website VARCHAR(255) NULL;
	END IF;

	-- date_of_birth
	SELECT COUNT(*) INTO col_exists FROM information_schema.COLUMNS
		WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND COLUMN_NAME = 'date_of_birth';
	IF col_exists = 0 THEN
		ALTER TABLE users ADD COLUMN date_of_birth DATE NULL;
	END IF;

	-- indexes (create only if missing)
	SELECT COUNT(*) INTO idx_exists FROM information_schema.statistics
		WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND INDEX_NAME = 'idx_is_private';
	IF idx_exists = 0 THEN
		CREATE INDEX idx_is_private ON users(is_private);
	END IF;

	SELECT COUNT(*) INTO idx_exists FROM information_schema.statistics
		WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND INDEX_NAME = 'idx_show_read_receipts';
	IF idx_exists = 0 THEN
		CREATE INDEX idx_show_read_receipts ON users(show_read_receipts);
	END IF;

	SELECT COUNT(*) INTO idx_exists FROM information_schema.statistics
		WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND INDEX_NAME = 'idx_show_activity_status';
	IF idx_exists = 0 THEN
		CREATE INDEX idx_show_activity_status ON users(show_activity_status);
	END IF;

	-- verify output
	SELECT 'Migration completed successfully!' AS status;
	SHOW COLUMNS FROM users;
END $$
DELIMITER ;

CALL apply_fix_signup;
DROP PROCEDURE apply_fix_signup;