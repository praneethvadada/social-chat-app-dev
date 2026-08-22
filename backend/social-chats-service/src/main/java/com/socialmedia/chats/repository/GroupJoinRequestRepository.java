package com.socialmedia.chats.repository;

import com.socialmedia.chats.entity.GroupJoinRequest;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface GroupJoinRequestRepository extends JpaRepository<GroupJoinRequest, Long> {

    Optional<GroupJoinRequest> findByConversationIdAndUserId(Long conversationId, Long userId);

    List<GroupJoinRequest> findByConversationIdAndStatusOrderByCreatedAtDesc(
            Long conversationId, GroupJoinRequest.Status status);
}
