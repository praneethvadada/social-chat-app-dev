-- Fix follow_requests schema
-- This migration updates the table to match current entity mapping
USE auth_db;

-- MySQL-compatible idempotent migration in procedure style.
DELIMITER $$

DROP PROCEDURE IF EXISTS apply_fix_follow_requests $$
CREATE PROCEDURE apply_fix_follow_requests()
BEGIN
    DECLARE has_receiver INT DEFAULT 0;
    DECLARE has_target INT DEFAULT 0;
    DECLARE fk_exists INT DEFAULT 0;
    DECLARE idx_exists INT DEFAULT 0;
    DECLARE equivalent_unique_exists INT DEFAULT 0;
    DECLARE single_requester_unique_count INT DEFAULT 0;

    -- Verify target table exists.
    SELECT COUNT(*) INTO idx_exists
    FROM information_schema.TABLES
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'follow_requests';

    IF idx_exists = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Table follow_requests does not exist in current database';
    END IF;

    -- Remove any accidental unique index on requester_id alone.
    -- This would incorrectly allow only one follow-request row per requester.
    SELECT COUNT(*) INTO single_requester_unique_count
    FROM (
      SELECT INDEX_NAME
      FROM information_schema.STATISTICS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'follow_requests'
        AND NON_UNIQUE = 0
        AND INDEX_NAME <> 'PRIMARY'
      GROUP BY INDEX_NAME
      HAVING COUNT(*) = 1
         AND SUM(CASE WHEN COLUMN_NAME = 'requester_id' THEN 1 ELSE 0 END) = 1
    ) t;

    IF single_requester_unique_count > 0 THEN
      SET @drop_single_unique_sql := (
        SELECT GROUP_CONCAT(CONCAT('DROP INDEX ', INDEX_NAME) SEPARATOR ', ')
        FROM (
          SELECT INDEX_NAME
          FROM information_schema.STATISTICS
          WHERE TABLE_SCHEMA = DATABASE()
            AND TABLE_NAME = 'follow_requests'
            AND NON_UNIQUE = 0
            AND INDEX_NAME <> 'PRIMARY'
          GROUP BY INDEX_NAME
          HAVING COUNT(*) = 1
             AND SUM(CASE WHEN COLUMN_NAME = 'requester_id' THEN 1 ELSE 0 END) = 1
        ) d
      );

      SET @drop_single_unique_sql := CONCAT('ALTER TABLE follow_requests ', @drop_single_unique_sql);
      PREPARE stmt FROM @drop_single_unique_sql;
      EXECUTE stmt;
      DEALLOCATE PREPARE stmt;
    END IF;

    -- Drop old receiver FK if present so column/index normalization can run safely.
    SELECT COUNT(*) INTO fk_exists
    FROM information_schema.TABLE_CONSTRAINTS
    WHERE CONSTRAINT_SCHEMA = DATABASE()
      AND TABLE_NAME = 'follow_requests'
      AND CONSTRAINT_TYPE = 'FOREIGN KEY'
      AND CONSTRAINT_NAME = 'fk_follow_req_receiver';

    IF fk_exists > 0 THEN
        ALTER TABLE follow_requests DROP FOREIGN KEY fk_follow_req_receiver;
    END IF;

    -- Drop canonical index if present; it will be recreated.
    SELECT COUNT(*) INTO idx_exists
    FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'follow_requests'
      AND INDEX_NAME = 'idx_receiver_status';

    IF idx_exists > 0 THEN
        ALTER TABLE follow_requests DROP INDEX idx_receiver_status;
    END IF;

    -- Normalize target_id/receiver_id.
    SELECT COUNT(*) INTO has_receiver
    FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'follow_requests'
      AND COLUMN_NAME = 'receiver_id';

    SELECT COUNT(*) INTO has_target
    FROM information_schema.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'follow_requests'
      AND COLUMN_NAME = 'target_id';

    IF has_receiver > 0 AND has_target > 0 THEN
        ALTER TABLE follow_requests DROP COLUMN target_id;
    ELSEIF has_receiver = 0 AND has_target > 0 THEN
        ALTER TABLE follow_requests
            CHANGE COLUMN target_id receiver_id BIGINT NOT NULL COMMENT 'User receiving follow request';
    ELSEIF has_receiver = 0 AND has_target = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Neither receiver_id nor target_id exists in follow_requests';
    END IF;

    -- Ensure canonical unique index exists (or an equivalent unique index already exists).
    SELECT COUNT(*) INTO idx_exists
    FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'follow_requests'
      AND INDEX_NAME = 'uk_follow_request';

    IF idx_exists = 0 THEN
        SELECT COUNT(*) INTO equivalent_unique_exists
        FROM (
            SELECT INDEX_NAME
            FROM information_schema.STATISTICS
            WHERE TABLE_SCHEMA = DATABASE()
              AND TABLE_NAME = 'follow_requests'
              AND NON_UNIQUE = 0
              AND INDEX_NAME <> 'PRIMARY'
            GROUP BY INDEX_NAME
            HAVING COUNT(*) = 2
               AND SUM(CASE WHEN COLUMN_NAME = 'requester_id' THEN 1 ELSE 0 END) = 1
               AND SUM(CASE WHEN COLUMN_NAME = 'receiver_id' THEN 1 ELSE 0 END) = 1
        ) t;

        IF equivalent_unique_exists = 0 THEN
            ALTER TABLE follow_requests
                ADD UNIQUE KEY uk_follow_request (requester_id, receiver_id);
        END IF;
    END IF;

    -- Ensure receiver/status index exists.
    SELECT COUNT(*) INTO idx_exists
    FROM information_schema.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = 'follow_requests'
      AND INDEX_NAME = 'idx_receiver_status';

    IF idx_exists = 0 THEN
        ALTER TABLE follow_requests
            ADD INDEX idx_receiver_status (receiver_id, status);
    END IF;

    -- Ensure receiver FK exists.
    SELECT COUNT(*) INTO fk_exists
    FROM information_schema.TABLE_CONSTRAINTS
    WHERE CONSTRAINT_SCHEMA = DATABASE()
      AND TABLE_NAME = 'follow_requests'
      AND CONSTRAINT_TYPE = 'FOREIGN KEY'
      AND CONSTRAINT_NAME = 'fk_follow_req_receiver';

    IF fk_exists = 0 THEN
        ALTER TABLE follow_requests
            ADD CONSTRAINT fk_follow_req_receiver
            FOREIGN KEY (receiver_id) REFERENCES users(id) ON DELETE CASCADE;
    END IF;

    SELECT 'follow_requests migration completed successfully!' AS status;
    SHOW CREATE TABLE follow_requests;
END $$

DELIMITER ;

CALL apply_fix_follow_requests;
DROP PROCEDURE apply_fix_follow_requests;
