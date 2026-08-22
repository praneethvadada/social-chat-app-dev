package com.socialmedia.social.repository;

import com.socialmedia.social.entity.StatusAudience;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;

public interface StatusAudienceRepository extends JpaRepository<StatusAudience, Long> {

    List<StatusAudience> findByStatusId(Long statusId);

    /** Batch-load for a page of statuses so feed filtering isn't N+1. */
    List<StatusAudience> findByStatusIdIn(List<Long> statusIds);

    @Query("SELECT CASE WHEN COUNT(a) > 0 THEN true ELSE false END FROM StatusAudience a " +
           "WHERE a.statusId = :statusId AND a.userId = :userId AND a.permission = 'ALLOW'")
    boolean isAllowed(@Param("statusId") Long statusId, @Param("userId") Long userId);

    @Query("SELECT CASE WHEN COUNT(a) > 0 THEN true ELSE false END FROM StatusAudience a " +
           "WHERE a.statusId = :statusId AND a.userId = :userId AND a.permission = 'DENY'")
    boolean isDenied(@Param("statusId") Long statusId, @Param("userId") Long userId);
}
