package com.socialmedia.chats.controller;

import com.socialmedia.chats.entity.CallLog;
import com.socialmedia.chats.entity.CallParticipant;
import com.socialmedia.chats.entity.ConversationMember;
import com.socialmedia.chats.repository.CallLogRepository;
import com.socialmedia.chats.repository.CallParticipantRepository;
import com.socialmedia.chats.repository.ConversationMemberRepository;
import com.socialmedia.chats.service.AgoraTokenService;
import com.socialmedia.chats.service.CallService;
import com.socialmedia.chats.service.FCMService;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import io.swagger.v3.oas.annotations.Operation;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/calls")
public class CallsController {

    private final AgoraTokenService tokenService;
    private final CallLogRepository callLogRepository;
    private final CallParticipantRepository callParticipantRepository;
    private final ConversationMemberRepository conversationMemberRepository;
    private final SimpMessagingTemplate messagingTemplate;
    private final CallService callService;
    private final FCMService fcmService;

    public CallsController(AgoraTokenService tokenService,
                            CallLogRepository callLogRepository,
                            CallParticipantRepository callParticipantRepository,
                            ConversationMemberRepository conversationMemberRepository,
                            SimpMessagingTemplate messagingTemplate,
                            CallService callService,
                            FCMService fcmService) {
        this.tokenService = tokenService;
        this.callLogRepository = callLogRepository;
        this.callParticipantRepository = callParticipantRepository;
        this.conversationMemberRepository = conversationMemberRepository;
        this.messagingTemplate = messagingTemplate;
        this.callService = callService;
        this.fcmService = fcmService;
    }

    @GetMapping("/token")
    @Operation(summary = "Get Agora token for a channel. Requires authentication.")
    public ResponseEntity<Map<String, String>> getToken(@RequestAttribute("userId") Long userId,
                                                        @RequestParam String channel,
                                                        @RequestParam int uid) {
        if (userId == null) return ResponseEntity.status(401).build();

        String token = tokenService.buildRtcToken(channel, uid);
        String appId = tokenService.getAppId();
        return ResponseEntity.ok(Map.of("appId", appId, "token", token));
    }

    @PostMapping
    @Operation(summary = "Log call start. Requires authentication.")
    public ResponseEntity<CallLog> logCall(@RequestAttribute("userId") Long userId, @RequestBody Map<String, Object> payload) {
        if (userId == null) return ResponseEntity.status(401).build();

        CallLog call = new CallLog();
        call.setInitiatorId(userId);

        // Map toUserId from payload
        if (payload.get("toUserId") != null) {
            call.setReceiverId(((Number) payload.get("toUserId")).longValue());
        }

        Long groupId = null;
        if (payload.get("groupId") != null) {
            groupId = ((Number) payload.get("groupId")).longValue();
            call.setGroupId(groupId);
        }

        if (payload.get("channelName") != null) {
            call.setChannelName((String) payload.get("channelName"));
        }

        // Map isVideo to callType
        if (payload.get("isVideo") != null) {
            boolean isVideo = (Boolean) payload.get("isVideo");
            call.setCallType(isVideo ? "VIDEO" : "AUDIO");
        } else {
            call.setCallType("AUDIO"); // Default to AUDIO
        }

        // Group calls are "ACTIVE" the moment the caller joins Agora (no
        // ringing wait for the caller); 1:1 calls stay "INITIATED" until
        // accepted.
        call.setStatus(groupId != null ? "ACTIVE" : "INITIATED");

        CallLog saved = callLogRepository.save(call);

        if (groupId != null) {
            // Caller is already on the call.
            callService.recordParticipant(saved.getId(), userId, CallParticipant.Status.JOINED, null);

            // Every other current group member starts as INVITED; the
            // GROUP_CALL_INVITE fan-out (CallSignalingController) flips the
            // ones actually notified to RINGING.
            List<ConversationMember> members = conversationMemberRepository.findByConversationId(groupId);
            for (ConversationMember member : members) {
                if (member.getUserId().equals(userId)) continue;
                callService.recordParticipant(saved.getId(), member.getUserId(), CallParticipant.Status.INVITED, null);
            }
        }

        return ResponseEntity.ok(saved);
    }

    @PostMapping("/{callId}/participants/join")
    @Operation(summary = "Join a call (capacity-checked for group calls). Requires authentication.")
    public ResponseEntity<?> joinParticipant(
            @PathVariable Long callId,
            @RequestAttribute("userId") Long userId,
            @RequestBody Map<String, Object> body) {
        if (userId == null) return ResponseEntity.status(401).build();

        Integer agoraUid = body.get("agoraUid") != null ? ((Number) body.get("agoraUid")).intValue() : null;
        CallService.JoinResult result = callService.joinParticipant(callId, userId, agoraUid);

        if (!result.success()) {
            if (result.callFull()) {
                return ResponseEntity.status(409).body(Map.of("reason", "call_full"));
            }
            return ResponseEntity.notFound().build();
        }
        return ResponseEntity.ok(result.participant());
    }

    @PostMapping("/{callId}/participants/leave")
    @Operation(summary = "Leave a call — the call continues for remaining participants. Requires authentication.")
    public ResponseEntity<?> leaveParticipant(
            @PathVariable Long callId,
            @RequestAttribute("userId") Long userId) {
        if (userId == null) return ResponseEntity.status(401).build();
        callService.leaveParticipant(callId, userId);
        return ResponseEntity.ok().build();
    }

    @GetMapping("/group/{groupId}/active")
    @Operation(summary = "Look up whether there's an in-progress call for this group (\"join later\"). Requires authentication.")
    public ResponseEntity<?> getActiveGroupCall(
            @PathVariable Long groupId,
            @RequestAttribute("userId") Long userId) {
        if (userId == null) return ResponseEntity.status(401).build();

        return callService.findActiveCallForGroup(groupId)
                .<ResponseEntity<?>>map(call -> {
                    long count = callParticipantRepository.countByCallIdAndStatus(call.getId(), CallParticipant.Status.JOINED);
                    return ResponseEntity.ok(Map.of(
                            "active", true,
                            "callId", call.getId(),
                            "channelName", call.getChannelName(),
                            "isVideo", "VIDEO".equals(call.getCallType()),
                            "participantCount", count
                    ));
                })
                .orElseGet(() -> ResponseEntity.ok(Map.of("active", false)));
    }

    @PostMapping("/reject")
    @Operation(summary = "Reject a call via REST (for use when app is killed/background). Requires authentication.")
    public ResponseEntity<?> rejectCall(@RequestAttribute("userId") Long userId, @RequestBody Map<String, Object> payload) {
        if (userId == null) return ResponseEntity.status(401).build();

        // Expects: callerId (who called me), channelName
        Object callerIdObj = payload.get("callerId");
        if (callerIdObj == null) return ResponseEntity.badRequest().body("Missing callerId");

        Long callerId = ((Number) callerIdObj).longValue();
        String channelName = (String) payload.get("channelName");

        // Construct rejection signal
        Map<String, Object> signal = new java.util.HashMap<>();
        signal.put("type", "CALL_REJECT");
        Map<String, Object> signalPayload = new java.util.HashMap<>();
        signalPayload.put("fromUserId", userId); // I am rejecting
        signalPayload.put("toUserId", callerId); // Rejecting you
        signalPayload.put("channelName", channelName);
        signalPayload.put("type", "CALL_REJECT");
        signal.put("payload", signalPayload);

        // Send to Caller via WebSocket
        String destination = "/topic/calls." + callerId;
        messagingTemplate.convertAndSend(destination, signal);

        System.out.println("[CallsController] 📵 REST Reject: User " + userId + " rejected call from " + callerId);

        return ResponseEntity.ok().build();
    }

    @PostMapping("/accept")
    @Operation(summary = "Accept a call via REST (signals caller immediately).")
    public ResponseEntity<?> acceptCall(@RequestAttribute("userId") Long userId, @RequestBody Map<String, Object> payload) {
        if (userId == null) return ResponseEntity.status(401).build();

        Object callerIdObj = payload.get("callerId");
        if (callerIdObj == null) return ResponseEntity.badRequest().body("Missing callerId");
        Long callerId = ((Number) callerIdObj).longValue();
        String channelName = (String) payload.get("channelName");
        boolean isVideo = (Boolean) payload.getOrDefault("isVideo", false);

        Map<String, Object> signal = new java.util.HashMap<>();
        signal.put("type", "CALL_ACCEPT");
        Map<String, Object> signalPayload = new java.util.HashMap<>();
        signalPayload.put("fromUserId", userId);
        signalPayload.put("toUserId", callerId);
        signalPayload.put("channelName", channelName);
        signalPayload.put("isVideo", isVideo);
        signalPayload.put("type", "CALL_ACCEPT");
        signal.put("payload", signalPayload);

        // Send to Caller
        String destination = "/topic/calls." + callerId;
        messagingTemplate.convertAndSend(destination, signal);

        System.out.println("[CallsController] 📞 REST Accept: User " + userId + " accepted call from " + callerId);
        return ResponseEntity.ok().build();
    }

    @PutMapping("/{callId}/status")
    @Operation(summary = "Update call status (rejected, accepted, ended, missed). Requires authentication.")
    public ResponseEntity<CallLog> updateCallStatus(
            @PathVariable Long callId,
            @RequestAttribute("userId") Long userId,
            @RequestBody Map<String, Object> updateRequest) {
        if (userId == null) return ResponseEntity.status(401).build();

        var callOptional = callLogRepository.findById(callId);
        if (callOptional.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        CallLog call = callOptional.get();

        // Authorize: 1:1 initiator/receiver, or a tracked participant
        // (covers group calls, where receiverId is null and would NPE on a
        // direct .equals(userId) check).
        boolean isInitiator = call.getInitiatorId().equals(userId);
        boolean isReceiver = call.getReceiverId() != null && call.getReceiverId().equals(userId);
        boolean isParticipant = callParticipantRepository.findByCallIdAndUserId(callId, userId).isPresent();
        if (!isInitiator && !isReceiver && !isParticipant) {
            return ResponseEntity.status(403).build();
        }

        // Update status (normalized to uppercase — the canonical vocabulary
        // is INITIATED/RINGING/ACCEPTED/ACTIVE/ENDED/DECLINED/MISSED/CANCELED/BUSY).
        String newStatus = (String) updateRequest.get("status");
        if (newStatus != null && !newStatus.isEmpty()) {
            String normalized = newStatus.toUpperCase();
            call.setStatus(normalized);

            if ("MISSED".equals(normalized) && call.getGroupId() == null && call.getReceiverId() != null) {
                try {
                    boolean isVideo = "VIDEO".equals(call.getCallType());
                    fcmService.onMissedCall(call.getReceiverId(), call.getInitiatorId(), isVideo);
                } catch (Exception ignored) {
                }
            }
        }

        // Update duration if provided
        Object durationObj = updateRequest.get("duration");
        if (durationObj != null) {
            if (durationObj instanceof Number) {
                call.setDuration(((Number) durationObj).longValue());
            }
        }

        CallLog updated = callLogRepository.save(call);
        return ResponseEntity.ok(updated);    }

    @GetMapping("/history")
    @Operation(summary = "Get call history for the authenticated user. Returns both incoming and outgoing calls, most recent first.")
    public ResponseEntity<?> getCallHistory(@RequestAttribute("userId") Long userId) {
        if (userId == null) return ResponseEntity.status(401).build();
        return ResponseEntity.ok(callLogRepository.findCallLogsForUser(userId));
    }

    @DeleteMapping("/{callId}")
    @Operation(summary = "Delete a call from history for the authenticated user (soft delete). Requires authentication.")
    public ResponseEntity<?> deleteCall(
            @PathVariable Long callId,
            @RequestAttribute("userId") Long userId) {
        if (userId == null) return ResponseEntity.status(401).build();

        var callOptional = callLogRepository.findById(callId);
        if (callOptional.isEmpty()) {
            return ResponseEntity.notFound().build();
        }

        CallLog call = callOptional.get();

        if (call.getGroupId() != null) {
            // Group call: soft-delete is per-participant, not the two
            // initiator/receiver booleans (receiverId is null here).
            var participant = callParticipantRepository.findByCallIdAndUserId(callId, userId);
            if (participant.isEmpty()) {
                return ResponseEntity.status(403).build();
            }
            participant.get().setDeletedForUser(true);
            callParticipantRepository.save(participant.get());
        } else if (call.getInitiatorId().equals(userId)) {
            call.setDeletedForInitiator(true);
            callLogRepository.save(call);
        } else if (call.getReceiverId() != null && call.getReceiverId().equals(userId)) {
            call.setDeletedForReceiver(true);
            callLogRepository.save(call);
        } else {
            return ResponseEntity.status(403).build();
        }

        return ResponseEntity.ok(Map.of("message", "Call deleted successfully", "callId", callId));
    }
}
