-- ============================================
-- Migration: Create OTP Verification Table
-- ============================================
USE auth_db;

-- Create otp_verifications table if it doesn't exist
CREATE TABLE IF NOT EXISTS otp_verifications (
    id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    otp VARCHAR(4) NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at DATETIME NOT NULL,
    is_used BOOLEAN NOT NULL DEFAULT FALSE,
    attempts INT NOT NULL DEFAULT 0,
    INDEX idx_email (email),
    INDEX idx_expires_at (expires_at),
    INDEX idx_is_used (is_used)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Create a stored procedure to clean up expired OTPs (optional - run periodically)
DELIMITER $$
DROP PROCEDURE IF EXISTS cleanup_expired_otps $$
CREATE PROCEDURE cleanup_expired_otps()
BEGIN
    DELETE FROM otp_verifications
    WHERE expires_at < NOW() AND is_used = TRUE;
END$$
DELIMITER ;

-- Verify table was created
SELECT 'OTP Verification table created/verified successfully!' AS status;
