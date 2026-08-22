-- G5: group controls - permissions, invite links, join requests, notifications.
USE social_chats_db;

-- Per-group permissions (spec §R). Defaults deliberately match the behaviour
-- G1-G4 already ship and verify, so enabling this changes nothing until an
-- owner edits it.
ALTER TABLE conversations
  ADD COLUMN who_can_send VARCHAR(10) NOT NULL DEFAULT 'EVERYONE'
    COMMENT 'EVERYONE or ADMINS',
  ADD COLUMN who_can_edit_info VARCHAR(10) NOT NULL DEFAULT 'ADMINS',
  ADD COLUMN who_can_add_members VARCHAR(10) NOT NULL DEFAULT 'ADMINS',
  ADD COLUMN who_can_pin VARCHAR(10) NOT NULL DEFAULT 'ADMINS',
  ADD COLUMN approve_new_members BOOLEAN NOT NULL DEFAULT FALSE
    COMMENT 'when true, invite-link joins become join requests';

-- Per-member notification preference (spec §U). muted_until already exists.
ALTER TABLE conversation_members
  ADD COLUMN notification_level VARCHAR(10) NOT NULL DEFAULT 'ALL'
    COMMENT 'ALL, MENTIONS or NONE';

-- Invite links (spec §O). Codes are revocable and resettable.
CREATE TABLE IF NOT EXISTS group_invites (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  conversation_id BIGINT NOT NULL,
  code VARCHAR(32) NOT NULL,
  created_by BIGINT NOT NULL,
  created_at DATETIME(6) NOT NULL,
  expires_at DATETIME(6) NULL COMMENT 'NULL = no expiry',
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE KEY uk_code (code),
  KEY idx_conversation_active (conversation_id, is_active),
  CONSTRAINT fk_invite_conversation FOREIGN KEY (conversation_id)
    REFERENCES conversations(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Join requests (spec §P), used when approve_new_members is on.
CREATE TABLE IF NOT EXISTS group_join_requests (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  conversation_id BIGINT NOT NULL,
  user_id BIGINT NOT NULL,
  status VARCHAR(10) NOT NULL DEFAULT 'PENDING' COMMENT 'PENDING, ACCEPTED or REJECTED',
  created_at DATETIME(6) NOT NULL,
  decided_at DATETIME(6) NULL,
  decided_by BIGINT NULL,
  UNIQUE KEY uk_conversation_user (conversation_id, user_id),
  KEY idx_conversation_status (conversation_id, status),
  CONSTRAINT fk_join_request_conversation FOREIGN KEY (conversation_id)
    REFERENCES conversations(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
