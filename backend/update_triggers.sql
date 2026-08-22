DROP TRIGGER IF EXISTS trg_after_like_insert;
DROP TRIGGER IF EXISTS trg_after_like_delete;

DELIMITER //

CREATE TRIGGER trg_after_like_insert
AFTER INSERT ON likes
FOR EACH ROW
BEGIN
    IF NEW.target_type = 'POST' THEN
        UPDATE posts SET likes_count = likes_count + 1 WHERE id = NEW.target_id;
    END IF;
END//

CREATE TRIGGER trg_after_like_delete
AFTER DELETE ON likes
FOR EACH ROW
BEGIN
    IF OLD.target_type = 'POST' THEN
        UPDATE posts SET likes_count = likes_count - 1 WHERE id = OLD.target_id;
    END IF;
END//

DELIMITER ;
