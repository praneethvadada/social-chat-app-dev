-- ============================================
-- WORKBENCH MIGRATION SCRIPT
-- Apply OTP Verification Table
-- Database: auth_db
-- Created: January 6, 2026
-- ============================================

-- Step 1: Use the auth_db database
USE auth_db;

-- Step 2: Create OTP Verifications Table
CREATE TABLE IF NOT EXISTS otp_verifications (
    id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    otp VARCHAR(4) NOT NULL COMMENT '4-digit OTP code',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at DATETIME NOT NULL COMMENT 'OTP expiry time (10 minutes)',
    is_used BOOLEAN NOT NULL DEFAULT FALSE COMMENT 'Whether OTP has been verified',
    attempts INT NOT NULL DEFAULT 0 COMMENT 'Resend attempt counter',
    
    -- Indexes for efficient queries
    INDEX idx_email (email),
    INDEX idx_expires_at (expires_at),
    INDEX idx_is_used (is_used),
    UNIQUE KEY uk_email_unused (email, is_used)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Step 3: Create stored procedure to clean up expired OTPs
DELIMITER $$

DROP PROCEDURE IF EXISTS cleanup_expired_otps $$

CREATE PROCEDURE cleanup_expired_otps()
BEGIN
    DECLARE affected_rows INT;
    
    DELETE FROM otp_verifications
    WHERE expires_at < NOW() 
    AND is_used = TRUE;
    
    SET affected_rows = ROW_COUNT();
    SELECT CONCAT('Cleaned up ', affected_rows, ' expired OTP records') AS cleanup_status;
END$$

DELIMITER ;

-- Step 4: Create stored procedure to get OTP status
DELIMITER $$

DROP PROCEDURE IF EXISTS check_otp_status $$

CREATE PROCEDURE check_otp_status(IN p_email VARCHAR(255))
BEGIN
    SELECT 
        id,
        email,
        is_used,
        attempts,
        CASE 
            WHEN NOW() > expires_at THEN 'EXPIRED'
            WHEN is_used = TRUE THEN 'USED'
            ELSE 'VALID'
        END AS otp_status,
        TIMESTAMPDIFF(MINUTE, NOW(), expires_at) AS minutes_remaining
    FROM otp_verifications
    WHERE email = p_email
    ORDER BY created_at DESC
    LIMIT 1;
END$$

DELIMITER ;

-- Step 5: Create stored procedure to clean old OTP records
DELIMITER $$

DROP PROCEDURE IF EXISTS cleanup_old_otps $$

CREATE PROCEDURE cleanup_old_otps(IN p_days INT)
BEGIN
    DECLARE affected_rows INT;
    
    DELETE FROM otp_verifications
    WHERE created_at < DATE_SUB(NOW(), INTERVAL p_days DAY);
    
    SET affected_rows = ROW_COUNT();
    SELECT CONCAT('Deleted ', affected_rows, ' OTP records older than ', p_days, ' days') AS cleanup_result;
END$$

DELIMITER ;

-- Step 6: Verify migration
SELECT 'Migration Complete!' AS status;
SELECT CONCAT('OTP table created with ', COUNT(*) , ' records') AS table_info 
FROM otp_verifications;

-- Step 7: Display table structure
DESCRIBE otp_verifications;

-- Step 8: Update schema version
INSERT INTO schema_version (version, description) 
VALUES ('2.0.2', 'Added OTP Verification table for email verification - Jan 6, 2026')
ON DUPLICATE KEY UPDATE 
    version = VALUES(version),
    applied_at = CURRENT_TIMESTAMP;

-- ============================================
-- VERIFICATION QUERIES
-- ============================================

-- Check if OTP table exists
SELECT TABLE_NAME, TABLE_TYPE, ENGINE
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'auth_db' 
AND TABLE_NAME = 'otp_verifications';

-- Check all stored procedures
SELECT ROUTINE_NAME, ROUTINE_TYPE
FROM INFORMATION_SCHEMA.ROUTINES
WHERE ROUTINE_SCHEMA = 'auth_db'
AND ROUTINE_NAME IN ('cleanup_expired_otps', 'check_otp_status', 'cleanup_old_otps');

-- Check schema versions
SELECT version, applied_at, description
FROM schema_version
ORDER BY version DESC;

-- ============================================
-- USAGE EXAMPLES (For Testing)
-- ============================================

/*
-- Example 1: Check OTP status
CALL check_otp_status('test@example.com');

-- Example 2: Clean up expired OTPs (older than 1 day)
CALL cleanup_old_otps(1);

-- Example 3: Clean up all expired OTPs
CALL cleanup_expired_otps();

-- Example 4: Insert test OTP
INSERT INTO otp_verifications (email, otp, expires_at)
VALUES ('test@example.com', '1234', DATE_ADD(NOW(), INTERVAL 10 MINUTE));

-- Example 5: View all pending OTPs
SELECT email, otp, expires_at, TIMESTAMPDIFF(MINUTE, NOW(), expires_at) as minutes_remaining
FROM otp_verifications
WHERE is_used = FALSE AND expires_at > NOW();

-- Example 6: Mark OTP as used
UPDATE otp_verifications 
SET is_used = TRUE 
WHERE email = 'test@example.com' AND otp = '1234';
*/

-- ============================================
-- END OF WORKBENCH MIGRATION SCRIPT
-- ============================================
