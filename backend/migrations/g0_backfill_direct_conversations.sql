-- G0 backfill: wrap every existing 1:1 message pair in a DIRECT conversation.
-- Idempotent: INSERT IGNORE on unique keys; UPDATE only touches NULL conversation_id.
USE social_chats_db;

-- 1) One DIRECT conversation per distinct user pair found in messages
INSERT IGNORE INTO conversations (type, created_by, direct_key, created_at, updated_at)
SELECT 'DIRECT', p.lo, CONCAT(p.lo, ':', p.hi), p.first_at, p.last_at
FROM (
  SELECT LEAST(m.sender_id, m.receiver_id)    AS lo,
         GREATEST(m.sender_id, m.receiver_id) AS hi,
         MIN(m.created_at) AS first_at,
         MAX(m.created_at) AS last_at
  FROM messages m
  GROUP BY LEAST(m.sender_id, m.receiver_id), GREATEST(m.sender_id, m.receiver_id)
) p;

-- 2) Both participants become members (DIRECT has no roles; MEMBER for both)
INSERT IGNORE INTO conversation_members (conversation_id, user_id, role, joined_at)
SELECT c.id, CAST(SUBSTRING_INDEX(c.direct_key, ':', 1) AS UNSIGNED), 'MEMBER', c.created_at
FROM conversations c WHERE c.type = 'DIRECT';

INSERT IGNORE INTO conversation_members (conversation_id, user_id, role, joined_at)
SELECT c.id, CAST(SUBSTRING_INDEX(c.direct_key, ':', -1) AS UNSIGNED), 'MEMBER', c.created_at
FROM conversations c WHERE c.type = 'DIRECT';

-- 3) Stamp conversation_id onto the historical messages
UPDATE messages m
JOIN conversations c
  ON c.type = 'DIRECT'
 AND c.direct_key = CONCAT(LEAST(m.sender_id, m.receiver_id), ':', GREATEST(m.sender_id, m.receiver_id))
SET m.conversation_id = c.id
WHERE m.conversation_id IS NULL;
