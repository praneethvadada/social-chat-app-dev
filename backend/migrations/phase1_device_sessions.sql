-- Targets: auth_db (owned by auth-service)
-- Phase 1 of the device/session/2FA architecture plan: device identity,
-- login sessions, and a security audit log. auth-service runs with
-- spring.jpa.hibernate.ddl-auto=update, so these tables are created
-- automatically from the @Entity classes (Device, UserSession,
-- SecurityEvent) — this file is a documentation/deploy-reference copy of
-- that schema, not something that needs to be run by hand in dev.
--
-- NOTE for whoever edits migrations next: several older files in this
-- directory (2025-12-28-add-message-clientid-readat.sql,
-- V2025__chat_schema_fix.sql, add_chat_deletion_tracking.sql) say
-- "USE auth_db" while actually documenting social_chats_db tables
-- (messages/chat_deletions) — a pre-existing inconsistency, not something
-- introduced here. This file's own "USE auth_db" is correct for the tables
-- it documents below.

USE auth_db;

CREATE TABLE IF NOT EXISTS devices (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    device_id VARCHAR(64) NOT NULL,
    platform VARCHAR(10) NOT NULL,
    os_name VARCHAR(50),
    os_version VARCHAR(30),
    app_version VARCHAR(30),
    browser_name VARCHAR(50),
    browser_version VARCHAR(30),
    device_model VARCHAR(100),
    push_token VARCHAR(500),
    created_at DATETIME NOT NULL,
    updated_at DATETIME NOT NULL,
    UNIQUE KEY uk_user_device (user_id, device_id)
);

CREATE TABLE IF NOT EXISTS user_sessions (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    device_id BIGINT NOT NULL,
    session_token VARCHAR(64) NOT NULL,
    status VARCHAR(10) NOT NULL,
    ip_address VARCHAR(45),
    created_at DATETIME NOT NULL,
    last_active_at DATETIME,
    revoked_at DATETIME,
    revoked_reason VARCHAR(50),
    UNIQUE KEY uk_session_token (session_token),
    KEY idx_user_status (user_id, status)
);

CREATE TABLE IF NOT EXISTS security_events (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    event_type VARCHAR(40) NOT NULL,
    device_id BIGINT,
    session_id BIGINT,
    ip_address VARCHAR(45),
    user_agent VARCHAR(255),
    metadata TEXT,
    created_at DATETIME NOT NULL,
    KEY idx_user_created (user_id, created_at)
);
