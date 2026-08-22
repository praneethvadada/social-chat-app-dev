package com.socialmedia.chats.repository;

import com.socialmedia.chats.entity.CallParticipant;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface CallParticipantRepository extends JpaRepository<CallParticipant, Long> {
    List<CallParticipant> findByCallId(Long callId);

    Optional<CallParticipant> findByCallIdAndUserId(Long callId, Long userId);

    long countByCallIdAndStatus(Long callId, CallParticipant.Status status);

    List<CallParticipant> findByCallIdAndStatus(Long callId, CallParticipant.Status status);

    List<CallParticipant> findByCallIdAndStatusIn(Long callId, List<CallParticipant.Status> statuses);

    List<CallParticipant> findByUserIdAndStatus(Long userId, CallParticipant.Status status);
}
