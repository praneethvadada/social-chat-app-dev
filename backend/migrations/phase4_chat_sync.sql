-- Targets: social_chats_db (owned by social-chats-service)
-- Phase 4 of the device/session/2FA architecture plan: chat synchronization
-- (per-conversation sync cursor) & idempotent offline-retry send.
-- Documentation-only (social-chats-service runs with ddl-auto=update, which
-- does NOT retroactively add constraints to an already-existing table -
-- apply this manually against any pre-existing dev/prod database).

USE social_chats_db;

ALTER TABLE conversation_members
    ADD COLUMN last_sync_cursor BIGINT NULL,
    ADD COLUMN last_sync_at DATETIME NULL;

-- Idempotent-retry guarantee: the same sender retrying the same
-- clientMessageId must never produce a second row. MySQL treats each NULL as
-- distinct under a unique index, so legacy rows/paths that never set
-- clientMessageId are unaffected.
ALTER TABLE messages
    ADD CONSTRAINT uk_sender_client_message_id UNIQUE (senderId, clientMessageId);
