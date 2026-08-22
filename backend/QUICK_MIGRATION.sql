-- =================================================
-- QUICK MIGRATION: Add Profile Columns to users table
-- =================================================
-- INSTRUCTIONS:
-- 1. Open DBeaver or your MySQL client
-- 2. Connect to auth_db database
-- 3. Copy and paste the SQL below
-- 4. Execute it
-- =================================================

-- Add the missing columns to users table
ALTER TABLE users 
ADD COLUMN cover_photo VARCHAR(255),
ADD COLUMN location VARCHAR(100),
ADD COLUMN website VARCHAR(255),
ADD COLUMN date_of_birth DATE,
ADD COLUMN is_private BOOLEAN NOT NULL DEFAULT FALSE,
ADD COLUMN is_verified BOOLEAN NOT NULL DEFAULT FALSE;

-- Verify columns were added
SHOW COLUMNS FROM users;
