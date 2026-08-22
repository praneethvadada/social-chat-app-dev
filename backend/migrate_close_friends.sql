-- Migration: Create close_friends table
-- Date: 2026-01-08
-- Description: Stores close friends relationships for users

CREATE TABLE IF NOT EXISTS close_friends (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    close_friend_user_id BIGINT NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    -- Foreign key constraint
    CONSTRAINT fk_close_friends_user 
        FOREIGN KEY (user_id) 
        REFERENCES users(id) 
        ON DELETE CASCADE,
    
    CONSTRAINT fk_close_friends_close_friend 
        FOREIGN KEY (close_friend_user_id) 
        REFERENCES users(id) 
        ON DELETE CASCADE,
    
    -- Unique constraint to prevent duplicates
    CONSTRAINT uk_close_friends_pair 
        UNIQUE KEY (user_id, close_friend_user_id),
    
    -- Indexes for performance
    INDEX idx_user_id (user_id),
    INDEX idx_close_friend_user_id (close_friend_user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
