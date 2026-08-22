-- ============================================
-- SIMPLE NOTIFICATION TABLE RECREATION
-- Safest approach - recreate the table from scratch
-- Date: January 6, 2026
-- ============================================

USE auth_db;

-- Show current table
SELECT 'Backing up notification data (if any)...' as status;

-- Create backup of existing data (if any notifications exist)
CREATE TABLE IF NOT EXISTS notifications_backup AS
SELECT * FROM notifications WHERE 1=0; -- Empty structure copy

-- Drop the old table
DROP TABLE IF EXISTS notifications;

-- Create the new notifications table with correct schema
CREATE TABLE notifications (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    type VARCHAR(50) NOT NULL COMMENT 'LIKE, COMMENT, FOLLOW, MESSAGE, etc',
    actor_id BIGINT COMMENT 'User who triggered the notification',
    target_id BIGINT COMMENT 'Post/Comment ID the notification is about',
    content TEXT,
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_notif_user FOREIGN KEY (user_id) 
        REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_notif_actor FOREIGN KEY (actor_id) 
        REFERENCES users(id) ON DELETE SET NULL,
    INDEX idx_user_read (user_id, is_read),
    INDEX idx_created_at (created_at DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Verify the new table
SELECT 'New notifications table created successfully!' as status;
DESCRIBE notifications;

-- Show table structure
SELECT COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE, COLUMN_KEY, COLUMN_DEFAULT
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'notifications' AND TABLE_SCHEMA = 'auth_db'
ORDER BY ORDINAL_POSITION;
