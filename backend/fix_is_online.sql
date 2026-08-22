USE auth_db;

DELIMITER $$
DROP PROCEDURE IF EXISTS fix_is_online_proc $$
CREATE PROCEDURE fix_is_online_proc()
BEGIN
  DECLARE col_exists INT DEFAULT 0;
  DECLARE col_needs_default INT DEFAULT 0;

  SELECT COUNT(*) INTO col_exists FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND COLUMN_NAME = 'is_online';

  IF col_exists = 0 THEN
    ALTER TABLE users ADD COLUMN is_online TINYINT(1) NOT NULL DEFAULT 0;
  ELSE
    SELECT COUNT(*) INTO col_needs_default FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'users' AND COLUMN_NAME = 'is_online'
      AND IS_NULLABLE = 'NO' AND COLUMN_DEFAULT IS NULL;
    IF col_needs_default > 0 THEN
      ALTER TABLE users MODIFY COLUMN is_online TINYINT(1) NOT NULL DEFAULT 0;
    END IF;
  END IF;

  SELECT 'ok' AS status;
END $$
DELIMITER ;

CALL fix_is_online_proc();
DROP PROCEDURE IF EXISTS fix_is_online_proc();
