-- =====================================================
-- DATABASE MIGRATION - Add FCM Token Field
-- =====================================================
-- 
-- This script adds the FCM (Firebase Cloud Messaging) token field to the users table
-- Run this migration on your database to enable push notifications
--
-- Database: auth_db
-- Table: users
-- =====================================================

-- Step 1: Add fcm_token column to users table
ALTER TABLE users ADD COLUMN fcm_token VARCHAR(500) NULL;

-- Step 2: Create index on fcm_token for faster lookups (optional but recommended)
CREATE INDEX idx_fcm_token ON users(fcm_token);

-- Step 3: Verify the column was added
DESC users;
-- Should show: fcm_token | varchar(500) | YES | | NULL |

-- =====================================================
-- Rollback (if needed)
-- =====================================================
-- 
-- If you need to revert this migration:
-- DROP INDEX idx_fcm_token ON users;
-- ALTER TABLE users DROP COLUMN fcm_token;
--
-- =====================================================

-- =====================================================
-- Testing
-- =====================================================
-- 
-- After running this migration, you can verify:
-- 
-- 1. Check column exists:
--    SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS 
--    WHERE TABLE_NAME='users' AND COLUMN_NAME='fcm_token';
--
-- 2. Insert test data:
--    UPDATE users SET fcm_token='test_token_12345...' WHERE id=1;
--
-- 3. Query saved tokens:
--    SELECT id, username, fcm_token FROM users WHERE fcm_token IS NOT NULL;
--
-- =====================================================
