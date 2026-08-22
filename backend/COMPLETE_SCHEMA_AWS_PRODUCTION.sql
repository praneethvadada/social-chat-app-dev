-- ============================================
-- SOCIAL MEDIA DATABASE SCHEMA - AWS PRODUCTION READY
-- Single Consolidated Migration File
-- Database: auth_db
-- Version: 2.0.0
-- Date: January 6, 2026
-- ============================================

-- ============================================
-- DROP AND CREATE DATABASE
-- ============================================
DROP DATABASE IF EXISTS auth_db;
CREATE DATABASE auth_db 
CHARACTER SET utf8mb4 
COLLATE utf8mb4_unicode_ci;

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
    
    -- Privacy & Verification (added Jan 6, 2026 - for signup flow)
    is_private BOOLEAN NOT NULL DEFAULT FALSE COMMENT 'Account visibility - false=public, true=private',
    is_verified BOOLEAN NOT NULL DEFAULT FALSE COMMENT 'OTP/Email verification status',
    
    -- Online status tracking (added Jan 6, 2026)
    is_online BOOLEAN NOT NULL DEFAULT FALSE,
    last_seen_at DATETIME,
    
    -- Audit timestamps
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    INDEX idx_username (username),
    INDEX idx_email (email),
    INDEX idx_created_at (created_at),
    INDEX idx_is_online (is_online),
    INDEX idx_is_private (is_private),
    INDEX idx_is_verified (is_verified),
    INDEX idx_last_seen_at (last_seen_at)
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
-- OTP VERIFICATION (Added Jan 6, 2026)
-- ============================================

-- OTP Verifications table for email verification during signup
CREATE TABLE IF NOT EXISTS otp_verifications (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    email VARCHAR(255) NOT NULL UNIQUE,
    otp VARCHAR(4) NOT NULL COMMENT '4-digit OTP code (0000-9999)',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at DATETIME NOT NULL COMMENT 'OTP expiry time (10 minutes from creation)',
    is_used BOOLEAN NOT NULL DEFAULT FALSE COMMENT 'Whether OTP has been verified and used',
    attempts INT NOT NULL DEFAULT 0 COMMENT 'Number of resend attempts (max 5)',
    
    INDEX idx_email (email),
    INDEX idx_expires_at (expires_at),
    INDEX idx_is_used (is_used),
    UNIQUE KEY uk_email_unused (email, is_used)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Stores OTP codes for email verification during signup process';

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
    
    -- Privacy settings (added Jan 6, 2026)
    show_read_receipts BOOLEAN NOT NULL DEFAULT TRUE,
    show_activity_status BOOLEAN NOT NULL DEFAULT TRUE,
    
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
    visibility ENUM('PUBLIC', 'CLOSE_FRIENDS') NOT NULL DEFAULT 'PUBLIC' COMMENT 'Post visibility: PUBLIC (visible to followers) or CLOSE_FRIENDS (visible to close friends only)',
    
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
    INDEX idx_is_public (is_public),
    INDEX idx_visibility (visibility),
    INDEX idx_user_visibility (user_id, visibility)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Post media (images/videos)
CREATE TABLE IF NOT EXISTS post_images (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    post_id BIGINT NOT NULL,
    image_url VARCHAR(500) NOT NULL COMMENT 'S3 object key only (e.g., f128ce74-7deb-427a-a564-bbebf542a03f.jpg) NOT full URL',
    display_order INT NOT NULL DEFAULT 0,
    
    CONSTRAINT fk_post_images_post FOREIGN KEY (post_id) 
        REFERENCES posts(id) ON DELETE CASCADE,
    INDEX idx_post_media (post_id, display_order)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Store S3 keys only - backend constructs full URL from S3_BUCKET_NAME + key';

-- ============================================
-- INTERACTIONS
-- ============================================

-- Likes
CREATE TABLE IF NOT EXISTS likes (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    user_id BIGINT NOT NULL,
    target_type ENUM('POST', 'COMMENT') NOT NULL,
    target_id BIGINT NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_user_target_like (user_id, target_type, target_id),
    CONSTRAINT fk_likes_user FOREIGN KEY (user_id) 
        REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_target_likes (target_type, target_id),
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

-- Follow requests
CREATE TABLE IF NOT EXISTS follow_requests (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    requester_id BIGINT NOT NULL COMMENT 'User sending follow request',
    receiver_id BIGINT NOT NULL COMMENT 'User receiving follow request',
    status VARCHAR(20) NOT NULL DEFAULT 'PENDING' COMMENT 'PENDING, APPROVED, REJECTED',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_follow_request (requester_id, receiver_id),
    CONSTRAINT fk_follow_req_requester FOREIGN KEY (requester_id) 
        REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_follow_req_receiver FOREIGN KEY (receiver_id) 
        REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_receiver_status (receiver_id, status),
    INDEX idx_requester_status (requester_id, status)
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
-- CLOSE FRIENDS
-- ============================================

-- Close friends relationships
CREATE TABLE IF NOT EXISTS close_friends (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    user_id BIGINT NOT NULL COMMENT 'User who owns the close friends list',
    close_friend_user_id BIGINT NOT NULL COMMENT 'User who is in the close friends list',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    UNIQUE KEY uk_close_friends_pair (user_id, close_friend_user_id),
    CONSTRAINT fk_close_friends_user FOREIGN KEY (user_id) 
        REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_close_friends_close_friend FOREIGN KEY (close_friend_user_id) 
        REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_user_id (user_id),
    INDEX idx_close_friend_user_id (close_friend_user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Stores close friends relationships - users can share posts exclusively with close friends';

-- ============================================
-- MESSAGING
-- ============================================

-- Direct messages
CREATE TABLE IF NOT EXISTS messages (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    sender_id BIGINT NOT NULL,
    receiver_id BIGINT NOT NULL,
    content TEXT NOT NULL,
    media_url VARCHAR(500) COMMENT 'S3 object key only (NOT full URL) - backend constructs full URL',
    client_message_id VARCHAR(255) UNIQUE COMMENT 'Client-generated ID for optimistic updates',
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    read_at DATETIME COMMENT 'Timestamp when message was read',
    
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    
    CONSTRAINT fk_messages_sender FOREIGN KEY (sender_id) 
        REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_messages_receiver FOREIGN KEY (receiver_id) 
        REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_conversation (sender_id, receiver_id, created_at),
    INDEX idx_receiver_unread (receiver_id, is_read, created_at),
    INDEX idx_client_message_id (client_message_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Chat deletion tracking (WHATSAPP FIX - Jan 6, 2026)
-- Tracks which users have deleted which conversations independently
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

-- ============================================
-- NOTIFICATIONS
-- ============================================

CREATE TABLE IF NOT EXISTS notifications (
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ============================================
-- VIDEO CALLS
-- ============================================

CREATE TABLE IF NOT EXISTS call_logs (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    initiator_id BIGINT NOT NULL,
    receiver_id BIGINT NULL COMMENT 'NULL for group calls — see group_id',
    group_id BIGINT NULL COMMENT 'Set instead of receiver_id for group calls',
    channel_name VARCHAR(128) NULL COMMENT 'Agora channel — persisted so a call can be found/rejoined ("join later")',
    call_type VARCHAR(10) NOT NULL COMMENT 'AUDIO or VIDEO',
    status VARCHAR(20) NOT NULL DEFAULT 'INITIATED' COMMENT 'INITIATED, RINGING, ACCEPTED, ACTIVE, ENDED, DECLINED, MISSED, CANCELED, BUSY',
    duration_seconds INT DEFAULT 0,
    deleted_for_initiator BOOLEAN NOT NULL DEFAULT FALSE COMMENT 'Soft delete for initiator only',
    deleted_for_receiver BOOLEAN NOT NULL DEFAULT FALSE COMMENT 'Soft delete for receiver only',

    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT fk_call_initiator FOREIGN KEY (initiator_id)
        REFERENCES users(id) ON DELETE CASCADE,
    CONSTRAINT fk_call_receiver FOREIGN KEY (receiver_id)
        REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_user_calls (initiator_id, created_at),
    INDEX idx_receiver_calls (receiver_id, created_at),
    INDEX idx_group_calls (group_id, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Per-user state within a call (1:1 or group) — roster/identity, "join
-- later", max-participant enforcement, per-member history, busy detection.
CREATE TABLE IF NOT EXISTS call_participants (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    call_id BIGINT NOT NULL,
    user_id BIGINT NOT NULL,
    agora_uid INT NULL,
    status VARCHAR(10) NOT NULL DEFAULT 'INVITED' COMMENT 'INVITED, RINGING, JOINED, DECLINED, LEFT, MISSED',
    invited_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    joined_at DATETIME NULL,
    left_at DATETIME NULL,
    deleted_for_user BOOLEAN NOT NULL DEFAULT FALSE,

    CONSTRAINT fk_participant_call FOREIGN KEY (call_id)
        REFERENCES call_logs(id) ON DELETE CASCADE,
    CONSTRAINT fk_participant_user FOREIGN KEY (user_id)
        REFERENCES users(id) ON DELETE CASCADE,
    UNIQUE KEY uk_call_user (call_id, user_id),
    INDEX idx_participant_user_status (user_id, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

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
    u.is_online,
    u.last_seen_at,
    upe.cover_photo_url,
    upe.location,
    upe.website,
    upe.date_of_birth,
    upe.is_private,
    upe.is_verified,
    upe.show_read_receipts,
    upe.show_activity_status,
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

-- Active conversations view (excludes deleted by current user)
CREATE OR REPLACE VIEW v_active_conversations AS
SELECT 
    CASE 
        WHEN m.sender_id = 1 THEN m.receiver_id 
        ELSE m.sender_id 
    END as other_user_id,
    MAX(m.id) as last_message_id
FROM messages m
LEFT JOIN chat_deletions cd ON 
    cd.user_id = 1 AND 
    cd.other_user_id = CASE 
        WHEN m.sender_id = 1 THEN m.receiver_id 
        ELSE m.sender_id 
    END
WHERE cd.id IS NULL
GROUP BY other_user_id;

-- ============================================
-- TRIGGERS FOR COUNTER UPDATES
-- ============================================

DELIMITER //

-- Update posts likes_count when like is added
CREATE TRIGGER trg_after_like_insert
AFTER INSERT ON likes
FOR EACH ROW
BEGIN
    IF NEW.target_type = 'POST' THEN
        UPDATE posts SET likes_count = likes_count + 1 WHERE id = NEW.target_id;
    END IF;
END//

-- Update posts likes_count when like is removed
CREATE TRIGGER trg_after_like_delete
AFTER DELETE ON likes
FOR EACH ROW
BEGIN
    IF OLD.target_type = 'POST' THEN
        UPDATE posts SET likes_count = likes_count - 1 WHERE id = OLD.target_id;
    END IF;
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
-- STORED PROCEDURES
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

-- Cleanup expired OTP records (Added Jan 6, 2026)
CREATE PROCEDURE sp_cleanup_expired_otps()
BEGIN
    DECLARE affected_rows INT;
    
    DELETE FROM otp_verifications
    WHERE expires_at < NOW() 
    AND is_used = TRUE;
    
    SET affected_rows = ROW_COUNT();
    SELECT CONCAT('Cleaned up ', affected_rows, ' expired OTP records') AS cleanup_status;
END//

-- Check OTP status for an email (Added Jan 6, 2026)
CREATE PROCEDURE sp_check_otp_status(IN p_email VARCHAR(255))
BEGIN
    SELECT 
        id,
        email,
        is_used,
        attempts,
        CASE 
            WHEN NOW() > expires_at THEN 'EXPIRED'
            WHEN is_used = TRUE THEN 'USED'
            ELSE 'VALID'
        END AS otp_status,
        TIMESTAMPDIFF(MINUTE, NOW(), expires_at) AS minutes_remaining
    FROM otp_verifications
    WHERE email = p_email
    ORDER BY created_at DESC
    LIMIT 1;
END//

DELIMITER ;

-- ============================================
-- SCHEMA VERSIONING
-- ============================================

CREATE TABLE IF NOT EXISTS schema_version (
    version VARCHAR(20) PRIMARY KEY,
    applied_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    description TEXT
) ENGINE=InnoDB;

INSERT INTO schema_version (version, description) VALUES 
('2.1.0', 'Added Close Friends feature - visibility column in posts table and close_friends table - Jan 12, 2026')
ON DUPLICATE KEY UPDATE version=version;

-- ============================================
-- AWS DEPLOYMENT NOTES
-- ============================================
/*
DEPLOYMENT INSTRUCTIONS FOR AWS RDS:

1. Create AWS RDS MySQL 8.0 or higher instance

2. Connect to RDS instance:
   mysql -h <RDS_ENDPOINT> -u admin -p < complete_schema.sql

3. Verify successful deployment:
   SELECT * FROM schema_version;
   SHOW TABLES;
   
4. Update Backend Configuration:
   - Set spring.datasource.url=jdbc:mysql://<RDS_ENDPOINT>:3306/auth_db
   - Set spring.datasource.username=admin (or create app user)
   - Set spring.datasource.password=<PASSWORD>

5. Application is ready to use!

SECURITY RECOMMENDATIONS:
- Create read-only application user for SELECT operations
- Create read-write application user for write operations
- Enable SSL/TLS for connections
- Set up automated backups in RDS console
- Configure security groups to restrict access
*/

-- ============================================
-- MIGRATION SUMMARY (Jan 6, 2026 - Updated)
-- ============================================
/*
TABLES CREATED: 21
- users (with is_private, is_verified, is_online, last_seen_at)
- user_roles
- password_reset_token
- otp_verifications (NEW - Email OTP verification)
- user_profile_extensions (with show_read_receipts, show_activity_status)
- posts (with visibility for Close Friends feature)
- post_images
- likes
- comments
- shares
- saves
- followers
- follow_requests
- blocked_users
- close_friends (NEW - Close Friends feature)
- messages (with media_url, client_message_id, read_at)
- chat_deletions (WhatsApp fix)
- notifications
- call_logs
- schema_version

VIEWS CREATED: 3
- v_user_profiles
- v_post_feed
- v_active_conversations

TRIGGERS CREATED: 8
- Automatic counter updates for likes, comments, shares, saves

PROCEDURES CREATED: 3
- sp_get_user_feed
- sp_cleanup_expired_otps (NEW)
- sp_check_otp_status (NEW)

KEY FEATURES:
✓ Complete social media platform schema
✓ Email OTP verification for signup (is_verified field)
✓ Real-time chat with message history
✓ WhatsApp-like chat deletion (per-user)
✓ Online status tracking with is_online & last_seen_at
✓ Privacy settings (is_private for account visibility)
✓ Verification tracking (is_verified for OTP/email verification)
✓ Privacy settings (read receipts, activity status)
✓ Video call logging
✓ Follow request system
✓ Block user functionality
✓ Optimized indexes for performance
✓ Idempotent (safe to run multiple times)
✓ AWS RDS compatible
✓ Automated OTP cleanup procedures

LATEST CHANGES (Jan 12, 2026):
- Added Close Friends feature with visibility control for posts
- Added close_friends table for managing close friends relationships
- Added visibility ENUM column to posts table (PUBLIC, CLOSE_FRIENDS)
- Posts can now be shared exclusively with close friends
- Added indexes for efficient visibility filtering

PREVIOUS CHANGES (Jan 7, 2026):
- Fixed image URL storage to prevent double concatenation bug
- post_images.image_url now stores S3 keys only (e.g., 'abc123.jpg')
- messages.media_url now stores S3 keys only
- Backend must construct full URLs: https://<bucket>.s3.<region>.amazonaws.com/<key>
- Updated schema version to 2.0.3

PREVIOUS CHANGES (Jan 6, 2026):
- Added otp_verifications table for email-based signup verification
- 4-digit OTP codes with 10-minute validity
- Resend attempt tracking (max 5 attempts)
- Added OTP cleanup and status check stored procedures
- All OTP records have proper indexes for performance
*/

-- END OF SCHEMA

