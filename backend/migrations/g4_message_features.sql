-- G4: advanced messaging inside conversations - reply, pin, delete, reactions.
USE social_chats_db;

-- Reply / pin / delete live on the message itself.
-- Reply data is a SNAPSHOT (sender + preview) so a quoted message still renders
-- after the original is deleted, and rendering needs no extra query per bubble.
ALTER TABLE messages
  ADD COLUMN reply_to_message_id BIGINT NULL,
  ADD COLUMN reply_to_sender_id BIGINT NULL,
  ADD COLUMN reply_to_preview VARCHAR(300) NULL,
  ADD COLUMN is_pinned BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN pinned_at DATETIME(6) NULL,
  ADD COLUMN pinned_by BIGINT NULL,
  -- Tombstone rather than row removal: "This message was deleted" keeps the
  -- conversation coherent and preserves replies that quote it.
  ADD COLUMN is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN deleted_at DATETIME(6) NULL,
  ADD COLUMN deleted_by BIGINT NULL,
  ADD INDEX idx_conversation_pinned (conversation_id, is_pinned);

CREATE TABLE IF NOT EXISTS message_reactions (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  message_id BIGINT NOT NULL,
  user_id BIGINT NOT NULL,
  reaction VARCHAR(20) NOT NULL COMMENT 'stable key (heart, laugh, ...), not the emoji glyph',
  created_at DATETIME(6) NOT NULL,
  UNIQUE KEY uk_message_user (message_id, user_id) COMMENT 'one reaction per user per message',
  KEY idx_message (message_id),
  CONSTRAINT fk_reaction_message FOREIGN KEY (message_id)
    REFERENCES messages(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
