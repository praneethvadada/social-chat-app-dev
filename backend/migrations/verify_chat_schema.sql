-- Verification queries for chat schema
-- Run against auth_db

-- 1) Check columns
SELECT COLUMN_NAME, IS_NULLABLE, COLUMN_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'auth_db' AND TABLE_NAME = 'messages' AND COLUMN_NAME IN ('client_message_id','read_at');

-- 2) Check unique constraints
SELECT tc.CONSTRAINT_NAME, tc.CONSTRAINT_TYPE
FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
WHERE tc.TABLE_SCHEMA = 'auth_db' AND tc.TABLE_NAME = 'messages' AND tc.CONSTRAINT_TYPE = 'UNIQUE';

-- 3) Check indexes on client_message_id
SHOW INDEX FROM auth_db.messages WHERE Column_name = 'client_message_id';

-- 4) Sample a row to inspect values
SELECT id, sender_id, receiver_id, client_message_id, is_read, read_at, created_at
FROM messages
LIMIT 10;
