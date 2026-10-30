-- R1: user reports of users, posts and comments (Play Store UGC policy).
-- Lives in social_posts_db (social-service's database in production).
-- Hibernate ddl-auto=update creates the same table on startup; this script is
-- for running it by hand.
USE social_posts_db;

CREATE TABLE IF NOT EXISTS reports (
  id BIGINT PRIMARY KEY AUTO_INCREMENT,
  reporter_id BIGINT NOT NULL,
  target_type VARCHAR(20) NOT NULL COMMENT 'USER, POST or COMMENT',
  target_id BIGINT NOT NULL,
  reported_user_id BIGINT NOT NULL COMMENT 'owner of the post/comment, or the reported user',
  reason VARCHAR(20) NOT NULL COMMENT 'SPAM, HARASSMENT, HATE_SPEECH, NUDITY, VIOLENCE, SCAM, IMPERSONATION, OTHER',
  details VARCHAR(500) NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'PENDING' COMMENT 'PENDING, REVIEWED, ACTION_TAKEN, DISMISSED',
  created_at DATETIME(6) NOT NULL,
  UNIQUE KEY uk_report_reporter_target (reporter_id, target_type, target_id),
  KEY idx_report_status_created (status, created_at),
  KEY idx_report_reported_user (reported_user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Moderation queue: newest pending reports first.
-- SELECT * FROM reports WHERE status = 'PENDING' ORDER BY created_at DESC;
-- Mark one handled:
-- UPDATE reports SET status = 'ACTION_TAKEN' WHERE id = ?;
