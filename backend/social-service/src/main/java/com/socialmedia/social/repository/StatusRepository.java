package com.socialmedia.social.repository;

import com.socialmedia.social.entity.Status;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.List;

public interface StatusRepository extends JpaRepository<Status, Long> {

    /**
     * Active (non-expired, non-deleted) statuses from the given authors,
     * oldest first so a user's statuses play in posting order.
     */
    @Query("SELECT s FROM Status s WHERE s.userId IN :authorIds " +
           "AND s.isDeleted = false AND s.expiresAt > :now " +
           "ORDER BY s.userId, s.createdAt ASC")
    List<Status> findActiveByAuthors(@Param("authorIds") List<Long> authorIds,
                                     @Param("now") LocalDateTime now);

    @Query("SELECT s FROM Status s WHERE s.userId = :userId " +
           "AND s.isDeleted = false AND s.expiresAt > :now ORDER BY s.createdAt ASC")
    List<Status> findActiveByUser(@Param("userId") Long userId,
                                  @Param("now") LocalDateTime now);

    /** S4 archive: the owner's EXPIRED but not-deleted statuses, newest first. */
    @Query("SELECT s FROM Status s WHERE s.userId = :userId " +
           "AND s.isDeleted = false AND s.expiresAt <= :now ORDER BY s.createdAt DESC")
    List<Status> findExpiredByUser(@Param("userId") Long userId,
                                   @Param("now") LocalDateTime now);

    /** Hard-delete rows that expired a while ago (housekeeping only). */
    @Modifying
    @Query("DELETE FROM Status s WHERE s.expiresAt < :cutoff")
    int deleteExpiredBefore(@Param("cutoff") LocalDateTime cutoff);
}
