-- G0: unified conversation model for social-chats-service.
-- 1:1 chats become DIRECT conversations; groups (G1) will be GROUP conversations.
-- Non-destructive: messages keeps sender_id/receiver_id; conversation_id starts nullable.
USE social_chats_db;

CREATE TABLE IF NOT EXISTS conversations (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  type VARCHAR(10) NOT NULL COMMENT 'DIRECT or GROUP',
  name VARCHAR(100) NULL COMMENT 'group name; NULL for DIRECT',
  description VARCHAR(500) NULL,
  photo_url VARCHAR(255) NULL,
  created_by BIGINT NOT NULL,
  -- For DIRECT conversations: "minUserId:maxUserId". Unique key guarantees at
  -- most ONE direct conversation per user pair (find-or-create race-safe).
  direct_key VARCHAR(41) NULL,
  created_at DATETIME(6) NOT NULL,
  updated_at DATETIME(6) NOT NULL,
  UNIQUE KEY uk_direct_key (direct_key),
  KEY idx_type (type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS conversation_members (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  conversation_id BIGINT NOT NULL,
  user_id BIGINT NOT NULL,
  role VARCHAR(10) NOT NULL DEFAULT 'MEMBER' COMMENT 'OWNER, ADMIN or MEMBER',
  joined_at DATETIME(6) NOT NULL,
  muted_until DATETIME(6) NULL,
  UNIQUE KEY uk_conversation_user (conversation_id, user_id),
  KEY idx_user (user_id),
  CONSTRAINT fk_member_conversation FOREIGN KEY (conversation_id)
    REFERENCES conversations(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- messages joins the model via a nullable column (old 1:1 path keeps working)
SET @col_exists = (SELECT COUNT(*) FROM information_schema.columns
  WHERE table_schema='social_chats_db' AND table_name='messages' AND column_name='conversation_id');
SET @ddl = IF(@col_exists = 0,
  'ALTER TABLE messages ADD COLUMN conversation_id BIGINT NULL, ADD INDEX idx_conversation (conversation_id, created_at)',
  'SELECT "conversation_id already exists"');
PREPARE stmt FROM @ddl; EXECUTE stmt; DEALLOCATE PREPARE stmt;
