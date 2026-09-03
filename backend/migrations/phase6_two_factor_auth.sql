-- Targets: auth_db (owned by auth-service)
-- Phase 6 of the device/session/2FA architecture plan: 2FA configuration
-- (enable/disable/change-method) + the otp_verifications purpose-keying
-- fix flagged back in the original plan (Q3). Documentation-only
-- (auth-service runs with ddl-auto=update — see phase1_device_sessions.sql's
-- own note; ddl-auto=update does not add new constraints to an existing
-- table, so this must be applied manually).

USE auth_db;

ALTER TABLE users
    ADD COLUMN two_factor_enabled TINYINT(1) NOT NULL DEFAULT 0,
    ADD COLUMN two_factor_method VARCHAR(10) NULL;

-- Existing rows all belonged to the (undifferentiated) signup/link flow —
-- backfill before making the column NOT NULL.
ALTER TABLE otp_verifications
    ADD COLUMN purpose VARCHAR(30) NULL;
UPDATE otp_verifications SET purpose = 'EMAIL_VERIFICATION' WHERE purpose IS NULL;
ALTER TABLE otp_verifications
    MODIFY COLUMN purpose VARCHAR(30) NOT NULL;
ALTER TABLE otp_verifications
    ADD CONSTRAINT uk_email_purpose UNIQUE (email, purpose);
