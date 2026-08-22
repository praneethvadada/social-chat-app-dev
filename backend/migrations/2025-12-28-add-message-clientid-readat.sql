-- Migration: add client_message_id and read_at to messages table (idempotent)
USE auth_db;

DELIMITER $$
CREATE PROCEDURE add_message_cols_proc()
BEGIN
  IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='auth_db' AND TABLE_NAME='messages' AND COLUMN_NAME='client_message_id') THEN
    ALTER TABLE messages ADD COLUMN client_message_id VARCHAR(255);
  END IF;

  IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='auth_db' AND TABLE_NAME='messages' AND COLUMN_NAME='read_at') THEN
    ALTER TABLE messages ADD COLUMN read_at DATETIME NULL;
  END IF;

  -- populate missing client_message_id for existing rows
  UPDATE messages SET client_message_id = CONCAT('m_', id) WHERE client_message_id IS NULL OR client_message_id = '';

  -- make client_message_id NOT NULL (if currently nullable)
  IF (SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA='auth_db' AND TABLE_NAME='messages' AND COLUMN_NAME='client_message_id' AND IS_NULLABLE='NO') = 0 THEN
    ALTER TABLE messages MODIFY client_message_id VARCHAR(255) NOT NULL;
  END IF;

  -- add unique key if missing
  IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS WHERE TABLE_SCHEMA='auth_db' AND TABLE_NAME='messages' AND CONSTRAINT_NAME='uq_client_message_id') THEN
    ALTER TABLE messages ADD UNIQUE KEY uq_client_message_id (client_message_id);
  END IF;

  -- add index for receiver/is_read/created_at if missing
  IF NOT EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.STATISTICS WHERE TABLE_SCHEMA='auth_db' AND TABLE_NAME='messages' AND INDEX_NAME='idx_receiver_isread_created') THEN
    ALTER TABLE messages ADD INDEX idx_receiver_isread_created (receiver_id, is_read, created_at);
  END IF;
END$$
DELIMITER ;

CALL add_message_cols_proc();
DROP PROCEDURE IF EXISTS add_message_cols_proc;

SELECT 'Migration 2025-12-28 applied' AS status;
