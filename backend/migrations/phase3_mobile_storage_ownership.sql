-- Targets: auth_db (owned by auth-service)
-- Phase 3 of the device/session/2FA architecture plan: single-active-mobile-
-- device local chat storage ownership. Documentation-only (auth-service runs
-- with ddl-auto=update — see phase1_device_sessions.sql's own note).

USE auth_db;

CREATE TABLE IF NOT EXISTS mobile_storage_owner (
    user_id BIGINT PRIMARY KEY,
    device_id BIGINT NOT NULL,
    granted_at DATETIME NOT NULL
);

CREATE TABLE IF NOT EXISTS mobile_storage_history (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    from_device_id BIGINT,
    to_device_id BIGINT NOT NULL,
    transferred_at DATETIME NOT NULL,
    KEY idx_mobile_storage_history_user (user_id, transferred_at)
);
