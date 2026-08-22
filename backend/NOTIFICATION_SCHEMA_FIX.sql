-- ============================================
-- NOTIFICATION TABLE SCHEMA FIX
-- Update from old schema to finalized schema
-- Date: January 6, 2026
-- ============================================

USE auth_db;

-- Check current schema
SELECT 'Current notifications table schema:' as status;
DESCRIBE notifications;

-- First, drop the old foreign keys (without IF EXISTS for compatibility)
SET @sql = '';
SELECT CONCAT('ALTER TABLE notifications DROP FOREIGN KEY ', CONSTRAINT_NAME) INTO @sql 
FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE 
WHERE TABLE_NAME = 'notifications' AND COLUMN_NAME = 'recipient_id' AND REFERENCED_TABLE_NAME IS NOT NULL LIMIT 1;
IF @sql != '' THEN PREPARE stmt FROM @sql; EXECUTE stmt; DEALLOCATE PREPARE stmt; END IF;

-- Drop old indexes
ALTER TABLE notifications DROP INDEX IF EXISTS idx_notifications_recipient;

-- Handle old columns - drop them if they exist
ALTER TABLE notifications DROP COLUMN IF EXISTS recipient_id;

-- Rename body to content if body exists
ALTER TABLE notifications CHANGE COLUMN IF EXISTS body content TEXT;

-- Ensure all new columns exist with correct definitions
ALTER TABLE notifications 
ADD COLUMN IF NOT EXISTS user_id BIGINT NOT NULL AFTER id;

ALTER TABLE notifications 
ADD COLUMN IF NOT EXISTS type VARCHAR(50) NOT NULL AFTER user_id;

ALTER TABLE notifications 
ADD COLUMN IF NOT EXISTS actor_id BIGINT AFTER type;

ALTER TABLE notifications 
ADD COLUMN IF NOT EXISTS target_id BIGINT AFTER actor_id;

ALTER TABLE notifications 
ADD COLUMN IF NOT EXISTS content TEXT AFTER target_id;

ALTER TABLE notifications 
ADD COLUMN IF NOT EXISTS is_read BOOLEAN NOT NULL DEFAULT FALSE AFTER content;

ALTER TABLE notifications 
ADD COLUMN IF NOT EXISTS created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER is_read;

-- Drop old constraints if they exist (by checking first)
ALTER TABLE notifications DROP FOREIGN KEY IF EXISTS fk_notif_user;
ALTER TABLE notifications DROP FOREIGN KEY IF EXISTS fk_notif_actor;

-- Drop old index if exists
ALTER TABLE notifications DROP INDEX IF EXISTS idx_user_read;
ALTER TABLE notifications DROP INDEX IF EXISTS idx_created_at;

-- Add new constraints
ALTER TABLE notifications
ADD CONSTRAINT fk_notif_user FOREIGN KEY (user_id) 
    REFERENCES users(id) ON DELETE CASCADE;

ALTER TABLE notifications
ADD CONSTRAINT fk_notif_actor FOREIGN KEY (actor_id) 
    REFERENCES users(id) ON DELETE SET NULL;

-- Add new indexes
ALTER TABLE notifications
ADD INDEX idx_user_read (user_id, is_read);

ALTER TABLE notifications
ADD INDEX idx_created_at (created_at DESC);

-- Verify the fix
SELECT 'Fixed notifications table schema:' as status;
DESCRIBE notifications;

SELECT 'Notification table schema migration completed!' as status;
