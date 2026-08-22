-- =================================================
-- SIMPLE MIGRATION: Add All Missing Profile Columns
-- Run this in your MySQL client (DBeaver, phpMyAdmin, etc.)
-- =================================================

USE auth_db;

-- Add all missing columns with default values
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS cover_photo VARCHAR(255),
ADD COLUMN IF NOT EXISTS location VARCHAR(100),
ADD COLUMN IF NOT EXISTS website VARCHAR(255),
ADD COLUMN IF NOT EXISTS date_of_birth DATE,
ADD COLUMN IF NOT EXISTS is_private BOOLEAN NOT NULL DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS is_verified BOOLEAN NOT NULL DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS show_read_receipts BOOLEAN NOT NULL DEFAULT TRUE,
ADD COLUMN IF NOT EXISTS show_activity_status BOOLEAN NOT NULL DEFAULT TRUE;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_is_private ON users(is_private);
CREATE INDEX IF NOT EXISTS idx_show_read_receipts ON users(show_read_receipts);
CREATE INDEX IF NOT EXISTS idx_show_activity_status ON users(show_activity_status);

-- Verify columns
SELECT 'Migration completed!' AS status;
SHOW COLUMNS FROM users;
