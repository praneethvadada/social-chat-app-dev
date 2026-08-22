-- Phase 3 Database Migration: Add status column to messages table
-- This allows tracking message lifecycle: sending → sent → read
-- Run this migration on production database

-- Add status column to messages table
ALTER TABLE messages ADD COLUMN status VARCHAR(20) DEFAULT 'sent' AFTER is_read;

-- Create index on status for faster queries
CREATE INDEX idx_messages_status ON messages(status);

-- Add comment to document the column
ALTER TABLE messages MODIFY status VARCHAR(20) COMMENT 'Message status: sending, sent, or read';

-- Update existing messages based on is_read flag
-- Messages with is_read=1 should have status='read'
-- Messages with is_read=0 should have status='sent'
UPDATE messages SET status = 'read' WHERE is_read = 1;
UPDATE messages SET status = 'sent' WHERE is_read = 0;

-- Verify the migration
SELECT COUNT(*) as total_messages,
       SUM(CASE WHEN status='sent' THEN 1 ELSE 0 END) as sent_count,
       SUM(CASE WHEN status='read' THEN 1 ELSE 0 END) as read_count
FROM messages;
