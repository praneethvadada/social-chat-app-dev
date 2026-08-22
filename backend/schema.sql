-- ============================================
-- Social Media Application Database Schema
-- Database: auth_db (single unified database)
-- ============================================

-- Drop database if exists (for clean install)
-- DROP DATABASE IF EXISTS auth_db;
CREATE DATABASE IF NOT EXISTS auth_db;
USE auth_db;

-- ============================================
-- USERS & AUTHENTICATION
-- ============================================

-- Main users table (source of truth for all user data)
CREATE TABLE IF NOT EXISTS users (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(100) NOT NULL UNIQUE,
    password VARCHAR(255) NOT NULL COMMENT 'BCrypt hashed password',
    full_name VARCHAR(100),
    bio VARCHAR(500),
    profile_picture VARCHAR(255),
    
    -- Account security
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    account_non_locked BOOLEAN NOT NULL DEFAULT TRUE,
    failed_login_attempts INT NOT NULL DEFAULT 0,
    last_login DATETIME,
    
    -- Audit timestamps
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_username (username),
    INDEX idx_email (email),
    INDEX idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- User roles (many-to-many via junction table)
CREATE TABLE IF NOT EXISTS user_roles (
    user_id BIGINT NOT NULL,
    role VARCHAR(50) NOT NULL COMMENT 'USER, ADMIN, MODERATOR',
    
    PRIMARY KEY (user_id, role),
    CONSTRAINT fk_user_roles_user FOREIGN KEY (user_id) 
        REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Password reset tokens
CREATE TABLE IF NOT EXISTS password_reset_token (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    token VARCHAR(255) NOT NULL UNIQUE,
    expiry_date DATETIME NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_reset_token_user FOREIGN KEY (user_id) 
        REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_token (token),
    INDEX idx_expiry (expiry_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================
-- SOCIAL PROFILE EXTENSIONS
-- ============================================

-- Extended profile information (social-specific fields only)
CREATE TABLE IF NOT EXISTS user_profile_extensions (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    user_id BIGINT NOT NULL UNIQUE,
    
    -- Social-specific fields (not in users table)
    cover_photo_url VARCHAR(500),
    location VARCHAR(100),
    website VARCHAR(200),
    date_of_birth DATE,
    is_private BOOLEAN DEFAULT FALSE,
    is_verified BOOLEAN DEFAULT FALSE,
    
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_profile_ext_user FOREIGN KEY (user_id) 
        REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================
-- POSTS & CONTENT
-- ============================================

-- Posts table
CREATE TABLE IF NOT EXISTS posts (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    content TEXT,
    is_public BOOLEAN NOT NULL DEFAULT TRUE,
    
    -- Denormalized counters (updated by triggers/application)
    likes_count INT NOT NULL DEFAULT 0,
    comments_count INT NOT NULL DEFAULT 0,
    shares_count INT NOT NULL DEFAULT 0,
    saves_count INT NOT NULL DEFAULT 0,
    
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_posts_user FOREIGN KEY (user_id) 
        REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_user_posts (user_id, created_at DESC),
    INDEX idx_created_at (created_at DESC),
    INDEX idx_is_public (is_public)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Post media (images/videos)
CREATE TABLE IF NOT EXISTS post_images (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    post_id BIGINT NOT NULL,
    image_url VARCHAR(500) NOT NULL COMMENT 'Relative path or full URL to image/video',
    display_order INT NOT NULL DEFAULT 0,
    
    CONSTRAINT fk_post_images_post FOREIGN KEY (post_id) 
        REFERENCES posts(id) ON DELETE CASCADE,
    INDEX idx_post_media (post_id, display_order)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================
-- INTERACTIONS
-- ============================================

-- Likes
CREATE TABLE IF NOT EXISTS likes (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    post_id BIGINT NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_user_post_like (user_id, post_id),
    CONSTRAINT fk_likes_user FOREIGN KEY (user_id) 
        REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_likes_post FOREIGN KEY (post_id) 
        REFERENCES posts(id) ON DELETE CASCADE,
    INDEX idx_post_likes (post_id),
    INDEX idx_user_likes (user_id, created_at DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Comments
CREATE TABLE IF NOT EXISTS comments (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    post_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL,
    parent_comment_id BIGINT COMMENT 'For nested/threaded comments',
    content TEXT NOT NULL,
    
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_comments_post FOREIGN KEY (post_id) 
        REFERENCES posts(id) ON DELETE CASCADE,
    CONSTRAINT fk_comments_user FOREIGN KEY (user_id) 
        REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_comments_parent FOREIGN KEY (parent_comment_id) 
        REFERENCES comments(id) ON DELETE CASCADE,
    INDEX idx_post_comments (post_id, created_at),
    INDEX idx_parent_comments (parent_comment_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Shares
CREATE TABLE IF NOT EXISTS shares (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    post_id BIGINT NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_user_post_share (user_id, post_id),
    CONSTRAINT fk_shares_user FOREIGN KEY (user_id) 
        REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_shares_post FOREIGN KEY (post_id) 
        REFERENCES posts(id) ON DELETE CASCADE,
    INDEX idx_post_shares (post_id),
    INDEX idx_user_shares (user_id, created_at DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Saves (bookmarks)
CREATE TABLE IF NOT EXISTS saves (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    post_id BIGINT NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_user_post_save (user_id, post_id),
    CONSTRAINT fk_saves_user FOREIGN KEY (user_id) 
        REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_saves_post FOREIGN KEY (post_id) 
        REFERENCES posts(id) ON DELETE CASCADE,
    INDEX idx_user_saves (user_id, created_at DESC)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================
-- SOCIAL GRAPH
-- ============================================

-- Followers/Following relationships
CREATE TABLE IF NOT EXISTS followers (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    follower_id BIGINT NOT NULL COMMENT 'User who follows',
    following_id BIGINT NOT NULL COMMENT 'User being followed',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_follower_following (follower_id, following_id),
    CONSTRAINT fk_followers_follower FOREIGN KEY (follower_id) 
        REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_followers_following FOREIGN KEY (following_id) 
        REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_follower (follower_id),
    INDEX idx_following (following_id),
    INDEX idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Blocked users
CREATE TABLE IF NOT EXISTS blocked_users (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    blocker_id BIGINT NOT NULL COMMENT 'User who blocks',
    blocked_id BIGINT NOT NULL COMMENT 'User being blocked',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_blocker_blocked (blocker_id, blocked_id),
    CONSTRAINT fk_blocked_blocker FOREIGN KEY (blocker_id) 
        REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_blocked_blocked FOREIGN KEY (blocked_id) 
        REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_blocker (blocker_id),
    INDEX idx_blocked (blocked_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================
-- MESSAGING
-- ============================================

-- Direct messages
CREATE TABLE IF NOT EXISTS messages (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    sender_id BIGINT NOT NULL,
    receiver_id BIGINT NOT NULL,
    content TEXT NOT NULL,
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_messages_sender FOREIGN KEY (sender_id) 
        REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_messages_receiver FOREIGN KEY (receiver_id) 
        REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_conversation (sender_id, receiver_id, created_at),
    INDEX idx_receiver_unread (receiver_id, is_read, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================
-- SAMPLE DATA (Optional - for testing)
-- ============================================

-- Insert sample user (password: password123)
-- BCrypt hash for "password123"
INSERT INTO users (username, email, password, full_name, bio, enabled) VALUES
('john_doe', 'john@example.com', '$2a$10$N9qo8uLOickgx2ZMRZoMyeIjZAgcfl7p92ldGxad68LJZdL17lhWy', 'John Doe', 'Software Developer', TRUE)
ON DUPLICATE KEY UPDATE username=username;

INSERT INTO user_roles (user_id, role) VALUES
(1, 'USER')
ON DUPLICATE KEY UPDATE role=role;

-- ============================================
-- VIEWS FOR COMMON QUERIES
-- ============================================

-- Complete user profile view
CREATE OR REPLACE VIEW v_user_profiles AS
SELECT 
    u.id,
    u.username,
    u.email,
    u.full_name,
    u.bio,
    u.profile_picture,
    upe.cover_photo_url,
    upe.location,
    upe.website,
    upe.date_of_birth,
    upe.is_private,
    upe.is_verified,
    u.created_at,
    u.updated_at,
    (SELECT COUNT(*) FROM posts WHERE user_id = u.id) AS posts_count,
    (SELECT COUNT(*) FROM followers WHERE following_id = u.id) AS followers_count,
    (SELECT COUNT(*) FROM followers WHERE follower_id = u.id) AS following_count
FROM users u
LEFT JOIN user_profile_extensions upe ON u.id = upe.user_id;

-- Post feed view with author info
CREATE OR REPLACE VIEW v_post_feed AS
SELECT 
    p.id AS post_id,
    p.user_id,
    u.username AS author_username,
    u.full_name AS author_name,
    u.profile_picture AS author_avatar,
    p.content,
    p.is_public,
    p.likes_count,
    p.comments_count,
    p.shares_count,
    p.saves_count,
    p.created_at,
    p.updated_at
FROM posts p
INNER JOIN users u ON p.user_id = u.id
WHERE p.is_public = TRUE
ORDER BY p.created_at DESC;

-- ============================================
-- TRIGGERS FOR COUNTER UPDATES
-- ============================================

-- Update posts likes_count when like is added
DELIMITER //
CREATE TRIGGER trg_after_like_insert
AFTER INSERT ON likes
FOR EACH ROW
BEGIN
    UPDATE posts SET likes_count = likes_count + 1 WHERE id = NEW.post_id;
END//

-- Update posts likes_count when like is removed
CREATE TRIGGER trg_after_like_delete
AFTER DELETE ON likes
FOR EACH ROW
BEGIN
    UPDATE posts SET likes_count = likes_count - 1 WHERE id = OLD.post_id;
END//

-- Update posts comments_count when comment is added
CREATE TRIGGER trg_after_comment_insert
AFTER INSERT ON comments
FOR EACH ROW
BEGIN
    UPDATE posts SET comments_count = comments_count + 1 WHERE id = NEW.post_id;
END//

-- Update posts comments_count when comment is removed
CREATE TRIGGER trg_after_comment_delete
AFTER DELETE ON comments
FOR EACH ROW
BEGIN
    UPDATE posts SET comments_count = comments_count - 1 WHERE id = OLD.post_id;
END//

-- Update posts shares_count when share is added
CREATE TRIGGER trg_after_share_insert
AFTER INSERT ON shares
FOR EACH ROW
BEGIN
    UPDATE posts SET shares_count = shares_count + 1 WHERE id = NEW.post_id;
END//

-- Update posts shares_count when share is removed
CREATE TRIGGER trg_after_share_delete
AFTER DELETE ON shares
FOR EACH ROW
BEGIN
    UPDATE posts SET shares_count = shares_count - 1 WHERE id = OLD.post_id;
END//

-- Update posts saves_count when save is added
CREATE TRIGGER trg_after_save_insert
AFTER INSERT ON saves
FOR EACH ROW
BEGIN
    UPDATE posts SET saves_count = saves_count + 1 WHERE id = NEW.post_id;
END//

-- Update posts saves_count when save is removed
CREATE TRIGGER trg_after_save_delete
AFTER DELETE ON saves
FOR EACH ROW
BEGIN
    UPDATE posts SET saves_count = saves_count - 1 WHERE id = OLD.post_id;
END//

DELIMITER ;

-- ============================================
-- STORED PROCEDURES (Optional)
-- ============================================

DELIMITER //

-- Get user feed (posts from followed users)
CREATE PROCEDURE sp_get_user_feed(IN p_user_id BIGINT, IN p_limit INT, IN p_offset INT)
BEGIN
    SELECT 
        p.id,
        p.user_id,
        u.username,
        u.full_name,
        u.profile_picture,
        p.content,
        p.likes_count,
        p.comments_count,
        p.shares_count,
        p.created_at,
        (SELECT COUNT(*) FROM likes WHERE post_id = p.id AND user_id = p_user_id) AS is_liked
    FROM posts p
    INNER JOIN users u ON p.user_id = u.id
    WHERE p.user_id IN (
        SELECT following_id FROM followers WHERE follower_id = p_user_id
        UNION
        SELECT p_user_id
    )
    AND p.is_public = TRUE
    ORDER BY p.created_at DESC
    LIMIT p_limit OFFSET p_offset;
END//

DELIMITER ;

-- ============================================
-- INDEXES FOR PERFORMANCE
-- ============================================

-- Already defined inline with tables above
-- Additional composite indexes can be added here if needed

-- ============================================
-- GRANTS (Production)
-- ============================================

-- Create application user (uncomment for production)
-- CREATE USER IF NOT EXISTS 'social_app'@'localhost' IDENTIFIED BY 'secure_password_here';
-- GRANT SELECT, INSERT, UPDATE, DELETE ON auth_db.* TO 'social_app'@'localhost';
-- FLUSH PRIVILEGES;

-- ============================================
-- SCHEMA VERSION
-- ============================================

CREATE TABLE IF NOT EXISTS schema_version (
    version VARCHAR(20) PRIMARY KEY,
    applied_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    description TEXT
) ENGINE=InnoDB;

INSERT INTO schema_version (version, description) VALUES 
('1.0.0', 'Initial unified schema with auth and social features')
ON DUPLICATE KEY UPDATE version=version;
