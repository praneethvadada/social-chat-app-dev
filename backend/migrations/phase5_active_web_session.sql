-- Targets: auth_db (owned by auth-service)
-- Phase 5 of the device/session/2FA architecture plan: single-active-web-
-- session enforcement. Documentation-only (auth-service runs with
-- ddl-auto=update — see phase1_device_sessions.sql's own note).

USE auth_db;

CREATE TABLE IF NOT EXISTS active_web_session (
    user_id BIGINT PRIMARY KEY,
    session_id BIGINT NOT NULL,
    device_id BIGINT NOT NULL,
    granted_at DATETIME NOT NULL
);
