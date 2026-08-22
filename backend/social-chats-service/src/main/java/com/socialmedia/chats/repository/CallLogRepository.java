package com.socialmedia.chats.repository;

import com.socialmedia.chats.entity.CallLog;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface CallLogRepository extends JpaRepository<CallLog, Long> {
	// Fetch call logs where the user is the 1:1 initiator/receiver, OR a
	// tracked participant of a group call (call_participants), most recent
	// first, excluding whatever the user soft-deleted from their own view.
	@Query("SELECT c FROM CallLog c WHERE " +
	       "((c.initiatorId = :userId AND c.deletedForInitiator = false) OR " +
	       "(c.receiverId = :userId AND c.deletedForReceiver = false) OR " +
	       "EXISTS (SELECT 1 FROM CallParticipant p WHERE p.callId = c.id " +
	       "        AND p.userId = :userId AND p.deletedForUser = false)) " +
	       "ORDER BY c.createdAt DESC")
	List<CallLog> findCallLogsForUser(@Param("userId") Long userId);

	// The single in-progress call for a group, if any — backs "join later".
	Optional<CallLog> findFirstByGroupIdAndStatusOrderByCreatedAtDesc(Long groupId, String status);
}
