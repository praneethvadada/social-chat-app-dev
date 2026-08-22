-- Add privacy settings columns for read receipts and activity status
ALTER TABLE users ADD COLUMN show_read_receipts BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE users ADD COLUMN show_activity_status BOOLEAN NOT NULL DEFAULT true;

-- Create index for faster filtering
CREATE INDEX idx_show_read_receipts ON users(show_read_receipts);
CREATE INDEX idx_show_activity_status ON users(show_activity_status);

COMMIT;
