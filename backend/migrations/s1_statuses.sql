-- S1: 24-hour status. Lives in auth_db (owned by social-service).
-- Columns for privacy/replies exist now (spec §T/§U) so S4 needs no table rewrite.
USE auth_db;

CREATE TABLE IF NOT EXISTS statuses (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  user_id BIGINT NOT NULL,
  type VARCHAR(10) NOT NULL COMMENT 'TEXT, IMAGE or VIDEO (extensible: GIF, POLL...)',
  content VARCHAR(1000) NULL COMMENT 'text body, or caption for media',
  media_url VARCHAR(500) NULL,
  thumbnail_url VARCHAR(500) NULL,
  background_color VARCHAR(20) NULL COMMENT 'for TEXT statuses',
  privacy_type VARCHAR(20) NOT NULL DEFAULT 'CONTACTS' COMMENT 'CONTACTS | EXCEPT | ONLY (S4)',
  allow_replies BOOLEAN NOT NULL DEFAULT TRUE,
  allow_reactions BOOLEAN NOT NULL DEFAULT TRUE,
  is_deleted BOOLEAN NOT NULL DEFAULT FALSE,
  created_at DATETIME(6) NOT NULL,
  expires_at DATETIME(6) NOT NULL COMMENT 'created_at + 24h; every query filters on this',
  KEY idx_user_expires (user_id, expires_at),
  KEY idx_expires (expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS status_views (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  status_id BIGINT NOT NULL,
  viewer_id BIGINT NOT NULL,
  viewed_at DATETIME(6) NOT NULL,
  reaction VARCHAR(20) NULL COMMENT 'emoji reaction (S3)',
  UNIQUE KEY uk_status_viewer (status_id, viewer_id),
  KEY idx_status (status_id),
  CONSTRAINT fk_status_view_status FOREIGN KEY (status_id)
    REFERENCES statuses(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Explicit per-status audience (used by S4 "except..."/"only share with...").
-- Created now so the privacy model is table-complete from the start.
CREATE TABLE IF NOT EXISTS status_audience (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  status_id BIGINT NOT NULL,
  user_id BIGINT NOT NULL,
  permission VARCHAR(10) NOT NULL DEFAULT 'ALLOW' COMMENT 'ALLOW or DENY',
  UNIQUE KEY uk_status_audience (status_id, user_id),
  CONSTRAINT fk_status_audience_status FOREIGN KEY (status_id)
    REFERENCES statuses(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
