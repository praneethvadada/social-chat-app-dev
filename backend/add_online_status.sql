-- Add online status tracking to users table
ALTER TABLE users ADD COLUMN is_online BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE users ADD COLUMN last_seen_at DATETIME;

-- Create index for online users queries
CREATE INDEX idx_is_online ON users(is_online);
CREATE INDEX idx_last_seen_at ON users(last_seen_at);
