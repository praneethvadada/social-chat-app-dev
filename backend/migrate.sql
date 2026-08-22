-- ============================================
-- Migration Script: social_db → auth_db
-- ============================================
-- This script migrates all data from social_db to auth_db

USE auth_db;

-- Disable foreign key checks temporarily
SET FOREIGN_KEY_CHECKS = 0;

-- ============================================
-- 1. Migrate Posts
-- ============================================
INSERT IGNORE INTO auth_db.posts (id, user_id, content, is_public, likes_count, comments_count, shares_count, saves_count, created_at, updated_at)
SELECT id, user_id, content, is_public, likes_count, comments_count, shares_count, saves_count, created_at, updated_at
FROM social_db.posts
ON DUPLICATE KEY UPDATE
    content = VALUES(content),
    is_public = VALUES(is_public),
    likes_count = VALUES(likes_count),
    comments_count = VALUES(comments_count),
    shares_count = VALUES(shares_count),
    saves_count = VALUES(saves_count),
    updated_at = VALUES(updated_at);

-- Migrate post images
INSERT IGNORE INTO auth_db.post_images (post_id, image_url, display_order)
SELECT post_id, image_url, 0
FROM social_db.post_images;

-- ============================================
-- 2. Migrate Likes
-- ============================================
INSERT IGNORE INTO auth_db.likes (id, user_id, post_id, created_at)
SELECT id, user_id, post_id, created_at
FROM social_db.likes
ON DUPLICATE KEY UPDATE user_id = user_id;

-- ============================================
-- 3. Migrate Comments
-- ============================================
INSERT IGNORE INTO auth_db.comments (id, post_id, user_id, parent_comment_id, content, created_at, updated_at)
SELECT id, post_id, user_id, parent_comment_id, content, created_at, updated_at
FROM social_db.comments
ON DUPLICATE KEY UPDATE
    content = VALUES(content),
    updated_at = VALUES(updated_at);

-- ============================================
-- 4. Migrate Followers
-- ============================================
INSERT IGNORE INTO auth_db.followers (id, follower_id, following_id, created_at)
SELECT id, follower_id, following_id, created_at
FROM social_db.followers
ON DUPLICATE KEY UPDATE follower_id = follower_id;

-- ============================================
-- 5. Migrate Blocked Users
-- ============================================
INSERT IGNORE INTO auth_db.blocked_users (id, blocker_id, blocked_id, created_at)
SELECT id, blocker_id, blocked_id, created_at
FROM social_db.blocked_users
ON DUPLICATE KEY UPDATE blocker_id = blocker_id;

-- ============================================
-- 6. Migrate Shares
-- ============================================
INSERT IGNORE INTO auth_db.shares (id, user_id, post_id, created_at)
SELECT id, user_id, post_id, created_at
FROM social_db.shares
ON DUPLICATE KEY UPDATE user_id = user_id;

-- ============================================
-- 7. Migrate Saves
-- ============================================
INSERT IGNORE INTO auth_db.saves (id, user_id, post_id, created_at)
SELECT id, user_id, post_id, created_at
FROM social_db.saves
ON DUPLICATE KEY UPDATE user_id = user_id;

-- ============================================
-- 8. Migrate Messages
-- ============================================
INSERT IGNORE INTO auth_db.messages (id, sender_id, receiver_id, content, is_read, created_at, updated_at)
SELECT id, sender_id, receiver_id, content, is_read, created_at, updated_at
FROM social_db.messages
ON DUPLICATE KEY UPDATE
    content = VALUES(content),
    is_read = VALUES(is_read),
    updated_at = VALUES(updated_at);

-- Re-enable foreign key checks
SET FOREIGN_KEY_CHECKS = 1;

-- ============================================
-- Verification Queries
-- ============================================
SELECT 'Posts migrated:' AS status, COUNT(*) AS count FROM auth_db.posts;
SELECT 'Post images migrated:' AS status, COUNT(*) AS count FROM auth_db.post_images;
SELECT 'Likes migrated:' AS status, COUNT(*) AS count FROM auth_db.likes;
SELECT 'Comments migrated:' AS status, COUNT(*) AS count FROM auth_db.comments;
SELECT 'Followers migrated:' AS status, COUNT(*) AS count FROM auth_db.followers;
SELECT 'Blocked users migrated:' AS status, COUNT(*) AS count FROM auth_db.blocked_users;
SELECT 'Shares migrated:' AS status, COUNT(*) AS count FROM auth_db.shares;
SELECT 'Saves migrated:' AS status, COUNT(*) AS count FROM auth_db.saves;
SELECT 'Messages migrated:' AS status, COUNT(*) AS count FROM auth_db.messages;

-- ============================================
-- 9. Create call_logs table if not exists
-- ============================================
-- STALE: this shape (caller_id/callee_id/channel/recording_url) is an
-- orphaned early draft and does not match the actual entity in use
-- (com.socialmedia.chats.entity.CallLog -> social-chats-service's own DB,
-- columns initiator_id/receiver_id/group_id/channel_name/call_type/status).
-- See backend/complete_schema_v2.sql and COMPLETE_SCHEMA_AWS_PRODUCTION.sql
-- for the current, authoritative call_logs + call_participants schema.
CREATE TABLE IF NOT EXISTS auth_db.call_logs (
    id BIGINT PRIMARY KEY AUTO_INCREMENT,
    initiator_id BIGINT,
    caller_id BIGINT,
    callee_id BIGINT,
    type VARCHAR(32),
    status VARCHAR(32),
    channel VARCHAR(255),
    duration BIGINT,
    recording_url VARCHAR(1024),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
