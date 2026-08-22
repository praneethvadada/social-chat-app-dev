package com.socialmedia.social.repository;

import com.socialmedia.social.entity.FollowRequest;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface FollowRequestRepository extends JpaRepository<FollowRequest, Long> {
    boolean existsByRequesterIdAndReceiverId(Long requesterId, Long receiverId);
    Page<FollowRequest> findByReceiverIdOrderByCreatedAtDesc(Long receiverId, Pageable pageable);
    Optional<FollowRequest> findByRequesterIdAndReceiverId(Long requesterId, Long receiverId);
}
