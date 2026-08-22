-- G3: GROUP BAN - deliberately its own table and its own lifecycle.
--
-- Spec §16/§27: a group ban must NEVER reuse the personal blocked_users table.
-- The three systems stay independent:
--   USER BLOCK  (auth_db.blocked_users)  -> restricts private interaction
--   GROUP REMOVE (delete membership)     -> out of this group, may rejoin
--   GROUP BAN   (this table)             -> out of this group, cannot rejoin
USE social_chats_db;

CREATE TABLE IF NOT EXISTS group_bans (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  conversation_id BIGINT NOT NULL,
  user_id BIGINT NOT NULL COMMENT 'the banned user',
  banned_by BIGINT NOT NULL COMMENT 'admin/owner who issued the ban',
  reason VARCHAR(255) NULL,
  status VARCHAR(10) NOT NULL DEFAULT 'ACTIVE' COMMENT 'ACTIVE or LIFTED',
  created_at DATETIME(6) NOT NULL,
  expires_at DATETIME(6) NULL COMMENT 'NULL = permanent (temporary bans supported)',
  lifted_at DATETIME(6) NULL,
  lifted_by BIGINT NULL,
  UNIQUE KEY uk_conversation_user (conversation_id, user_id),
  KEY idx_conversation_status (conversation_id, status),
  CONSTRAINT fk_group_ban_conversation FOREIGN KEY (conversation_id)
    REFERENCES conversations(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='Group-level bans. Independent of personal blocks (spec 16/27).';
