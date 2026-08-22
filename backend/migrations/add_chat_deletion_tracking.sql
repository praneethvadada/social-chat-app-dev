-- Migration: Add per-user chat deletion tracking
-- This allows users to delete conversations independently
-- without affecting the other user's chat history

USE auth_db;

-- Create table to track which users have deleted which conversations
CREATE TABLE IF NOT EXISTS chat_deletions (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    other_user_id BIGINT NOT NULL,
    deleted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_user_conversation (user_id, other_user_id),
    CONSTRAINT fk_chat_deletion_user FOREIGN KEY (user_id) 
        REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_chat_deletion_other_user FOREIGN KEY (other_user_id) 
        REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_user_id (user_id),
    INDEX idx_deleted_at (deleted_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Add media_url and client_message_id columns if they don't exist
ALTER TABLE messages ADD COLUMN IF NOT EXISTS media_url VARCHAR(500);
ALTER TABLE messages ADD COLUMN IF NOT EXISTS client_message_id VARCHAR(255) UNIQUE;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS read_at DATETIME;

-- Add indexes for read receipt optimization
CREATE INDEX IF NOT EXISTS idx_client_message_id ON messages(client_message_id);

-- Add view for getting undeleted conversations
CREATE OR REPLACE VIEW v_active_conversations AS
SELECT 
    CASE 
        WHEN m.sender_id = ? THEN m.receiver_id 
        ELSE m.sender_id 
    END as other_user_id,
    MAX(m.id) as last_message_id
FROM messages m
LEFT JOIN chat_deletions cd ON 
    cd.user_id = ? AND 
    cd.other_user_id = CASE 
        WHEN m.sender_id = ? THEN m.receiver_id 
        ELSE m.sender_id 
    END
WHERE cd.id IS NULL
GROUP BY other_user_id;

COMMIT;
