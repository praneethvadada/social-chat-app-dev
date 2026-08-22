-- ============================================
-- MIGRATION SCRIPT: Add Close Friends Feature
-- Date: January 12, 2026
-- Version: 2.1.0
-- Description: Adds close_friends table and visibility column to posts
-- ============================================

USE auth_db;

-- Step 1: Create close_friends table if it doesn't exist
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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci 
COMMENT='Stores close friends relationships - users can share posts exclusively with close friends';

-- Step 2: Add visibility column to posts table (only if it doesn't exist)
SET @dbname = DATABASE();
SET @tablename = 'posts';
SET @columnname = 'visibility';
SET @preparedStatement = (SELECT IF(
  (
    SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
    WHERE
      (TABLE_SCHEMA = @dbname)
      AND (TABLE_NAME = @tablename)
      AND (COLUMN_NAME = @columnname)
  ) > 0,
  'SELECT 1',
  CONCAT('ALTER TABLE ', @tablename, ' ADD COLUMN ', @columnname, ' ENUM(''PUBLIC'', ''CLOSE_FRIENDS'') NOT NULL DEFAULT ''PUBLIC'' COMMENT ''Post visibility: PUBLIC (visible to followers) or CLOSE_FRIENDS (visible to close friends only)'' AFTER is_public')
));
PREPARE alterIfNotExists FROM @preparedStatement;
EXECUTE alterIfNotExists;
DEALLOCATE PREPARE alterIfNotExists;

-- Step 3: Update existing posts to set visibility based on is_public
-- (Only run if visibility column was just added)
UPDATE posts 
SET visibility = CASE 
    WHEN is_public = TRUE THEN 'PUBLIC'
    ELSE 'PUBLIC'  -- Default all to PUBLIC for backward compatibility
END
WHERE visibility IS NULL OR visibility = '';

-- Step 4: Add indexes for visibility filtering (only if they don't exist)
SET @tablename = 'posts';
SET @indexname = 'idx_visibility';
SET @preparedStatement = (SELECT IF(
  (
    SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS
    WHERE
      (TABLE_SCHEMA = @dbname)
      AND (TABLE_NAME = @tablename)
      AND (INDEX_NAME = @indexname)
  ) > 0,
  'SELECT 1',
  CONCAT('CREATE INDEX ', @indexname, ' ON ', @tablename, ' (visibility)')
));
PREPARE alterIfNotExists FROM @preparedStatement;
EXECUTE alterIfNotExists;
DEALLOCATE PREPARE alterIfNotExists;

SET @indexname = 'idx_user_visibility';
SET @preparedStatement = (SELECT IF(
  (
    SELECT COUNT(*) FROM INFORMATION_SCHEMA.STATISTICS
    WHERE
      (TABLE_SCHEMA = @dbname)
      AND (TABLE_NAME = @tablename)
      AND (INDEX_NAME = @indexname)
  ) > 0,
  'SELECT 1',
  CONCAT('CREATE INDEX ', @indexname, ' ON ', @tablename, ' (user_id, visibility)')
));
PREPARE alterIfNotExists FROM @preparedStatement;
EXECUTE alterIfNotExists;
DEALLOCATE PREPARE alterIfNotExists;

-- Step 5: Update schema version
INSERT INTO schema_version (version, description) VALUES 
('2.1.0', 'Added Close Friends feature - visibility column in posts table and close_friends table - Jan 12, 2026')
ON DUPLICATE KEY UPDATE 
    description = 'Added Close Friends feature - visibility column in posts table and close_friends table - Jan 12, 2026',
    applied_at = CURRENT_TIMESTAMP;

-- Step 6: Verify migration
SELECT 
    'Migration Complete!' AS status,
    (SELECT COUNT(*) FROM close_friends) AS close_friends_count,
    (SELECT COUNT(*) FROM posts WHERE visibility = 'PUBLIC') AS public_posts,
    (SELECT COUNT(*) FROM posts WHERE visibility = 'CLOSE_FRIENDS') AS close_friends_posts,
    (SELECT version FROM schema_version ORDER BY applied_at DESC LIMIT 1) AS current_version;

-- ============================================
-- MIGRATION NOTES
-- ============================================
/*
WHAT THIS MIGRATION DOES:
1. Creates close_friends table with proper constraints and indexes
2. Adds visibility ENUM column to posts table
3. Migrates existing posts to PUBLIC visibility
4. Adds performance indexes for visibility filtering
5. Updates schema version to 2.1.0

BACKWARD COMPATIBILITY:
- Keeps is_public column for legacy support
- All existing posts default to PUBLIC visibility
- No breaking changes to existing functionality

ROLLBACK INSTRUCTIONS (if needed):
1. Remove visibility column:
   ALTER TABLE posts DROP COLUMN visibility;
   
2. Drop close_friends table:
   DROP TABLE IF EXISTS close_friends;
   
3. Remove schema version:
   DELETE FROM schema_version WHERE version = '2.1.0';

NEXT STEPS:
1. Deploy backend code with visibility support
2. Deploy frontend with Close Friends UI
3. Monitor database performance
4. (Optional) After 3 months, consider removing is_public column
*/
