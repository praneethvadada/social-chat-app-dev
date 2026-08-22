package com.socialmedia.social.repository;

import com.socialmedia.social.entity.StatusView;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface StatusViewRepository extends JpaRepository<StatusView, Long> {

    boolean existsByStatusIdAndViewerId(Long statusId, Long viewerId);

    long countByStatusId(Long statusId);

    List<StatusView> findByStatusIdOrderByViewedAtDesc(Long statusId);

    /** Status ids (from the given set) that this viewer has already seen. */
    @Query("SELECT v.statusId FROM StatusView v WHERE v.viewerId = :viewerId AND v.statusId IN :statusIds")
    List<Long> findSeenStatusIds(@Param("viewerId") Long viewerId,
                                 @Param("statusIds") List<Long> statusIds);

    // ---- S3: reactions (stored on the view row - a reaction implies a view) ----

    Optional<StatusView> findByStatusIdAndViewerId(Long statusId, Long viewerId);

    /** [emoji, count] pairs for a status, non-null reactions only. */
    @Query("SELECT v.reaction, COUNT(v) FROM StatusView v " +
           "WHERE v.statusId = :statusId AND v.reaction IS NOT NULL GROUP BY v.reaction")
    List<Object[]> countReactionsByStatus(@Param("statusId") Long statusId);
}
