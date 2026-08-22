-- Migration: chat schema fixes (ONLY modifies `messages` table)
-- Adds client_message_id NOT NULL UNIQUE and read_at DATETIME NULL (idempotent)
USE auth_db;

DELIMITER $$
CREATE PROCEDURE chat_schema_fix_proc()
BEGIN
  IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='auth_db' AND TABLE_NAME='messages' AND COLUMN_NAME='client_message_id') THEN
    ALTER TABLE messages ADD COLUMN client_message_id VARCHAR(64);
  END IF;

  -- populate for existing rows
  UPDATE messages SET client_message_id = CONCAT('m_', id) WHERE client_message_id IS NULL OR client_message_id = '';

  -- make NOT NULL if not already
  IF (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='auth_db' AND TABLE_NAME='messages' AND COLUMN_NAME='client_message_id' AND IS_NULLABLE='NO') = 0 THEN
    ALTER TABLE messages MODIFY COLUMN client_message_id VARCHAR(64) NOT NULL;
  END IF;

  -- add unique constraint if missing
  IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS WHERE TABLE_SCHEMA='auth_db' AND TABLE_NAME='messages' AND CONSTRAINT_NAME='uq_client_message_id') THEN
    ALTER TABLE messages ADD UNIQUE KEY uq_client_message_id (client_message_id);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='auth_db' AND TABLE_NAME='messages' AND COLUMN_NAME='read_at') THEN
    ALTER TABLE messages ADD COLUMN read_at DATETIME NULL;
  END IF;
END$$
DELIMITER ;

CALL chat_schema_fix_proc();
DROP PROCEDURE IF EXISTS chat_schema_fix_proc;

SELECT 'V2025__chat_schema_fix applied' AS status;
