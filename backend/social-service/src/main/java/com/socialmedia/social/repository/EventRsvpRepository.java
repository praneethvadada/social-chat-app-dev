package com.socialmedia.social.repository;

import com.socialmedia.social.entity.EventRsvp;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Optional;

@Repository
public interface EventRsvpRepository extends JpaRepository<EventRsvp, Long> {
    Optional<EventRsvp> findByPostIdAndUserId(Long postId, Long userId);
    List<EventRsvp> findByPostId(Long postId);
    Long countByPostIdAndStatus(Long postId, EventRsvp.RsvpStatus status);
}
