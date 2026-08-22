package com.socialmedia.chats.service;

import com.socialmedia.chats.entity.CallLog;
import com.socialmedia.chats.entity.CallParticipant;
import com.socialmedia.chats.entity.Conversation;
import com.socialmedia.chats.repository.CallLogRepository;
import com.socialmedia.chats.repository.CallParticipantRepository;
import com.socialmedia.chats.repository.ConversationRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.List;
import java.util.Optional;

/**
 * Central place for call lifecycle logic that both CallsController (REST)
 * and CallSignalingController (WebSocket) need: participant roster/capacity,
 * "is this user already on a call" (server-side busy detection), and the
 * "last joined participant left -> call ended, mark stragglers missed" rule.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class CallService {

    public static final int MAX_GROUP_PARTICIPANTS = 12;

    /** A CallLog in one of these states is no longer "active"/"busy". */
    private static final List<String> TERMINAL_STATUSES =
            List.of("ENDED", "DECLINED", "MISSED", "CANCELED", "BUSY");

    private final CallLogRepository callLogRepository;
    private final CallParticipantRepository callParticipantRepository;
    private final ConversationRepository conversationRepository;
    private final FCMService fcmService;

    public record JoinResult(boolean success, boolean callFull, CallParticipant participant) {}

    /** True if the user currently has a JOINED row on any non-terminal call. */
    public boolean isUserBusy(Long userId) {
        List<CallParticipant> joined =
                callParticipantRepository.findByUserIdAndStatus(userId, CallParticipant.Status.JOINED);
        for (CallParticipant p : joined) {
            Optional<CallLog> call = callLogRepository.findById(p.getCallId());
            if (call.isPresent() && !TERMINAL_STATUSES.contains(call.get().getStatus())) {
                return true;
            }
        }
        return false;
    }

    public Optional<CallLog> findActiveCallForGroup(Long groupId) {
        return callLogRepository.findFirstByGroupIdAndStatusOrderByCreatedAtDesc(groupId, "ACTIVE");
    }

    /** Inserts (or returns the existing) participant row, without capacity enforcement. */
    public CallParticipant recordParticipant(Long callId, Long userId, CallParticipant.Status status, Integer agoraUid) {
        CallParticipant p = callParticipantRepository.findByCallIdAndUserId(callId, userId).orElseGet(CallParticipant::new);
        p.setCallId(callId);
        p.setUserId(userId);
        if (agoraUid != null) p.setAgoraUid(agoraUid);
        p.setStatus(status);
        if (p.getInvitedAt() == null) p.setInvitedAt(Instant.now());
        if (status == CallParticipant.Status.JOINED && p.getJoinedAt() == null) p.setJoinedAt(Instant.now());
        return callParticipantRepository.save(p);
    }

    /** Capacity-checked join — the server-authoritative gate on MAX_GROUP_PARTICIPANTS. */
    public JoinResult joinParticipant(Long callId, Long userId, Integer agoraUid) {
        if (callLogRepository.findById(callId).isEmpty()) {
            return new JoinResult(false, false, null);
        }

        CallParticipant existing = callParticipantRepository.findByCallIdAndUserId(callId, userId).orElse(null);
        boolean alreadyJoined = existing != null && existing.getStatus() == CallParticipant.Status.JOINED;

        long joinedCount = callParticipantRepository.countByCallIdAndStatus(callId, CallParticipant.Status.JOINED);
        if (!alreadyJoined && joinedCount >= MAX_GROUP_PARTICIPANTS) {
            return new JoinResult(false, true, null);
        }

        CallParticipant p = recordParticipant(callId, userId, CallParticipant.Status.JOINED, agoraUid);
        return new JoinResult(true, false, p);
    }

    /**
     * Marks the user LEFT. If they were the last JOINED participant, the call
     * is considered ended: the CallLog is marked ENDED, and anyone still
     * INVITED/RINGING (never answered) is marked MISSED with a push.
     */
    public void leaveParticipant(Long callId, Long userId) {
        callParticipantRepository.findByCallIdAndUserId(callId, userId).ifPresent(p -> {
            p.setStatus(CallParticipant.Status.LEFT);
            p.setLeftAt(Instant.now());
            callParticipantRepository.save(p);
        });

        long stillJoined = callParticipantRepository.countByCallIdAndStatus(callId, CallParticipant.Status.JOINED);
        if (stillJoined > 0) return;

        callLogRepository.findById(callId).ifPresent(call -> {
            if (TERMINAL_STATUSES.contains(call.getStatus())) return;
            call.setStatus("ENDED");
            callLogRepository.save(call);

            List<CallParticipant> stragglers = callParticipantRepository.findByCallIdAndStatusIn(
                    callId, List.of(CallParticipant.Status.INVITED, CallParticipant.Status.RINGING));
            if (stragglers.isEmpty()) return;

            String groupName = null;
            if (call.getGroupId() != null) {
                groupName = conversationRepository.findById(call.getGroupId())
                        .map(Conversation::getName).orElse(null);
            }

            for (CallParticipant straggler : stragglers) {
                straggler.setStatus(CallParticipant.Status.MISSED);
                callParticipantRepository.save(straggler);
                try {
                    if (call.getGroupId() != null) {
                        fcmService.onMissedGroupCall(straggler.getUserId(), call.getGroupId(), groupName);
                    }
                } catch (Exception e) {
                    log.error("[CallService] Failed to send missed-group-call push to {}: {}", straggler.getUserId(), e.getMessage());
                }
            }
        });
    }
}
