package com.socialmedia.chats.controller;

import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.messaging.simp.SimpMessageHeaderAccessor;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Controller;
import lombok.RequiredArgsConstructor;
import com.socialmedia.chats.entity.CallParticipant;
import com.socialmedia.chats.service.CallService;
import com.socialmedia.chats.service.FCMService;
import com.socialmedia.chats.client.BlockClient;
import com.socialmedia.chats.entity.ConversationMember;
import com.socialmedia.chats.repository.CallParticipantRepository;
import com.socialmedia.chats.repository.ConversationMemberRepository;
import java.util.List;
import java.util.Map;

/**
 * Handles WebSocket call signaling events
 *
 * Responsibilities:
 * 1. Receive call signaling events (CALL_INVITE, CALL_ACCEPT, CALL_REJECT, CALL_END)
 * 2. Extract user IDs from session and payload
 * 3. Forward events to the recipient
 * 4. Log all events for debugging
 *
 * Events flow:
 * - CALL_INVITE: Caller -> Backend -> Receiver
 * - CALL_ACCEPT: Receiver -> Backend -> Caller
 * - CALL_REJECT: Receiver -> Backend -> Caller
 * - CALL_END: Either -> Backend -> Other
 *
 * Group events (fan out to every other conversation member instead of a
 * single recipient — see handleGroupCallSignal):
 * - GROUP_CALL_INVITE: Caller -> Backend -> every other group member
 * - GROUP_CALL_CANCEL: Caller cancels before anyone joined -> still-invited members
 * - GROUP_CALL_LEAVE: A joined participant leaves -> remaining joined members (call continues)
 * - GROUP_CALL_DECLINE / GROUP_CALL_END: legacy/compat, see below
 */
@Controller
@RequiredArgsConstructor
public class CallSignalingController {

    private final SimpMessagingTemplate messagingTemplate;
    private final FCMService fcmService;
    private final BlockClient blockService;
    private final ConversationMemberRepository conversationMemberRepository;
    private final CallParticipantRepository callParticipantRepository;
    private final CallService callService;

    @MessageMapping("/call.signal")
    public void handleCallSignal(
            @Payload Map<String, Object> message,
            SimpMessageHeaderAccessor headerAccessor) {
        try {
            // Extract sending user ID from WebSocket session
            Long senderUserId = extractUserIdFromSession(headerAccessor);
            if (senderUserId == null) {
                logError("handleCallSignal", "Sender userId not found in session");
                return;
            }

            // Extract event type (frontend sends "signalType")
            String eventType = (String) message.get("signalType");
            if (eventType == null) {
                logError("handleCallSignal", "Missing signalType in message");
                return;
            }

            // Group calls fan out to every other member of the conversation
            // instead of a single recipient — handled entirely separately
            // from the 1:1 path below, which stays untouched.
            if (isGroupCallEvent(eventType)) {
                handleGroupCallSignal(eventType, message, senderUserId);
                return;
            }

            // Extract recipient user ID
            Long recipientUserId = extractRecipientUserId(message);
            if (recipientUserId == null) {
                logError("handleCallSignal", "Recipient userId not found in message");
                return;
            }

            // ✅ BLOCKING FIX: Check if either user has blocked the other
            if (blockService.isEitherBlocked(senderUserId, recipientUserId)) {
                logError("handleCallSignal", "Call blocked: users have blocking relationship");
                sendRejection(senderUserId, recipientUserId, "blocked", "Unknown");
                return;
            }

            // ✅ Server-side busy detection: works even if the busy device's
            // process is dead (unlike the old 100%-client-side check), since
            // it reads call_participants instead of relying on the receiver's
            // live CallStateManager.
            if ("CALL_INVITE".equals(eventType) && callService.isUserBusy(recipientUserId)) {
                logInfo("handleCallSignal", "Recipient " + recipientUserId + " is busy — auto-rejecting", null);
                sendRejection(recipientUserId, senderUserId, "busy", null);
                return;
            }

            // Log the event
            logInfo("handleCallSignal",
                String.format("Event: %s | From: %d | To: %d", eventType, senderUserId, recipientUserId),
                message.get("payload"));

            // Validate state transitions based on event type
            if (!isValidEventTransition(eventType)) {
                logError("handleCallSignal", "Invalid event type: " + eventType);
                return;
            }

            // Prepare response with sender info included
            Map<String, Object> payload = (Map<String, Object>) message.getOrDefault("payload", new java.util.HashMap<>());
            if (payload instanceof java.util.HashMap) {
                payload = new java.util.HashMap<>(payload);
            }
            payload.put("fromUserId", senderUserId);
            payload.put("type", eventType);

            // Forward to recipient
            Map<String, Object> response = new java.util.HashMap<>();
            response.put("type", eventType);
            response.put("payload", payload);

            // Use topic-based pub/sub for more reliable delivery (not user queues)
            String destination = "/topic/calls." + recipientUserId;
            logInfo("handleCallSignal",
                String.format("Forwarding to %s", destination),
                response);

            messagingTemplate.convertAndSend(
                destination,
                response
            );

            // ✅ ENABLE FCM FOR CALLS (Data-Only High Priority)
            // This is required to wake the app from "Killed" state.
            // FCMService now sends this as a priority=high, content=data-only message.
            if ("CALL_INVITE".equals(eventType)) {
                try {
                    String channelName = (String) payload.getOrDefault("channelName", "default-call");
                    boolean isVideo = Boolean.parseBoolean(String.valueOf(payload.getOrDefault("isVideo", false)));
                    fcmService.onIncomingCall(recipientUserId, senderUserId, channelName, isVideo, null, null);
                    logInfo("handleCallSignal", "Triggered FCM for CALL_INVITE to user " + recipientUserId + " (video=" + isVideo + ")", null);
                } catch (Exception e) {
                    logError("handleCallSignal", "FCM error for incoming call: " + e.getMessage());
                }
            }

            logInfo("handleCallSignal",
                String.format("✓ Forwarded %s from user %d to user %d", eventType, senderUserId, recipientUserId),
                null);

        } catch (Exception e) {
            logError("handleCallSignal", "Exception: " + e.getMessage());
            e.printStackTrace();
        }
    }

    /** Sends a CALL_REJECT back to `toUserId`, as if `fromUserId` rejected the call, with a reason. */
    private void sendRejection(Long fromUserId, Long toUserId, String reason, String actorUsername) {
        Map<String, Object> rejectionPayload = new java.util.HashMap<>();
        rejectionPayload.put("type", "CALL_REJECT");
        rejectionPayload.put("fromUserId", fromUserId);
        rejectionPayload.put("toUserId", toUserId);
        rejectionPayload.put("reason", reason);
        if (actorUsername != null) rejectionPayload.put("actorUsername", actorUsername);
        Map<String, Object> rejection = new java.util.HashMap<>();
        rejection.put("type", "CALL_REJECT");
        rejection.put("payload", rejectionPayload);
        messagingTemplate.convertAndSend("/topic/calls." + toUserId, rejection);
    }

    private boolean isGroupCallEvent(String eventType) {
        return eventType != null && (
            eventType.equals("GROUP_CALL_INVITE") ||
            eventType.equals("GROUP_CALL_DECLINE") ||
            eventType.equals("GROUP_CALL_CANCEL") ||
            eventType.equals("GROUP_CALL_LEAVE") ||
            eventType.equals("GROUP_CALL_END")
        );
    }

    /**
     * Fans a group call signal out, reusing each member's existing personal
     * call topic (/topic/calls.{userId}) — the same channel 1:1 signaling
     * already uses, so no new client-side subscription is needed.
     *
     * GROUP_CALL_INVITE fans to every other current conversation member
     * (skipping busy/blocked ones — they simply never get invited, and stay
     * INVITED so they show up as a missed call once the call ends).
     * GROUP_CALL_CANCEL fans only to members still INVITED/RINGING on this
     * specific call (the caller backed out before anyone joined).
     * GROUP_CALL_LEAVE fans to the remaining JOINED members as a roster
     * update — the call keeps running for them.
     */
    @SuppressWarnings("unchecked")
    private void handleGroupCallSignal(String eventType, Map<String, Object> message, Long senderUserId) {
        Object groupIdObj = message.get("groupId");
        if (groupIdObj == null) {
            Object payloadObj = message.get("payload");
            if (payloadObj instanceof Map) {
                groupIdObj = ((Map<String, Object>) payloadObj).get("groupId");
            }
        }
        if (groupIdObj == null) {
            logError("handleGroupCallSignal", "Missing groupId");
            return;
        }
        Long groupId = groupIdObj instanceof Number
            ? ((Number) groupIdObj).longValue()
            : Long.parseLong(groupIdObj.toString());

        Long callId = extractCallId(message);

        Map<String, Object> payload = (Map<String, Object>) message.getOrDefault("payload", new java.util.HashMap<>());
        payload = new java.util.HashMap<>(payload);
        payload.put("fromUserId", senderUserId);
        payload.put("groupId", groupId);
        payload.put("type", eventType);

        Map<String, Object> response = new java.util.HashMap<>();
        response.put("type", eventType);
        response.put("payload", payload);

        if (eventType.equals("GROUP_CALL_CANCEL")) {
            handleGroupCallCancel(callId, response);
            return;
        }
        if (eventType.equals("GROUP_CALL_LEAVE")) {
            handleGroupCallLeave(callId, senderUserId, response);
            return;
        }

        // GROUP_CALL_INVITE / GROUP_CALL_DECLINE / GROUP_CALL_END (legacy —
        // GROUP_CALL_END is still accepted as a synonym for cancel-or-leave
        // from older clients, fanned to the full member list as before).
        List<ConversationMember> members = conversationMemberRepository.findByConversationId(groupId);
        int fanned = 0;
        for (ConversationMember member : members) {
            Long memberId = member.getUserId();
            if (memberId.equals(senderUserId)) continue;
            if (blockService.isEitherBlocked(senderUserId, memberId)) continue;

            if (eventType.equals("GROUP_CALL_INVITE") && callService.isUserBusy(memberId)) {
                logInfo("handleGroupCallSignal", "Member " + memberId + " is busy — skipping invite", null);
                continue;
            }

            messagingTemplate.convertAndSend("/topic/calls." + memberId, response);
            fanned++;

            if (eventType.equals("GROUP_CALL_INVITE")) {
                if (callId != null) {
                    callService.recordParticipant(callId, memberId, CallParticipant.Status.RINGING, null);
                }
                try {
                    String channelName = (String) payload.getOrDefault("channelName", "default-call");
                    boolean isVideo = Boolean.parseBoolean(String.valueOf(payload.getOrDefault("isVideo", false)));
                    String groupName = (String) payload.get("groupName");
                    fcmService.onIncomingCall(memberId, senderUserId, channelName, isVideo, groupId, groupName);
                } catch (Exception e) {
                    logError("handleGroupCallSignal", "FCM error for member " + memberId + ": " + e.getMessage());
                }
            }
        }

        logInfo("handleGroupCallSignal",
            String.format("%s | group=%d | from=%d | fanned to %d member(s)", eventType, groupId, senderUserId, fanned),
            null);
    }

    private void handleGroupCallCancel(Long callId, Map<String, Object> response) {
        if (callId == null) {
            logError("handleGroupCallCancel", "Missing callId");
            return;
        }
        List<CallParticipant> pending = callParticipantRepository.findByCallIdAndStatus(callId, CallParticipant.Status.INVITED);
        pending.addAll(callParticipantRepository.findByCallIdAndStatus(callId, CallParticipant.Status.RINGING));
        for (CallParticipant p : pending) {
            p.setStatus(CallParticipant.Status.MISSED); // never got to answer — now moot
            callParticipantRepository.save(p);
            messagingTemplate.convertAndSend("/topic/calls." + p.getUserId(), response);
        }
        logInfo("handleGroupCallCancel", "call=" + callId + " | notified " + pending.size() + " pending member(s)", null);
    }

    private void handleGroupCallLeave(Long callId, Long senderUserId, Map<String, Object> response) {
        if (callId == null) {
            logError("handleGroupCallLeave", "Missing callId");
            return;
        }
        // Marks sender LEFT; if they were last JOINED, ends the call and
        // marks stragglers MISSED (with a push) — see CallService.
        callService.leaveParticipant(callId, senderUserId);

        List<CallParticipant> remaining = callParticipantRepository.findByCallIdAndStatus(callId, CallParticipant.Status.JOINED);
        for (CallParticipant p : remaining) {
            messagingTemplate.convertAndSend("/topic/calls." + p.getUserId(), response);
        }
        logInfo("handleGroupCallLeave", "call=" + callId + " | from=" + senderUserId + " | notified " + remaining.size() + " remaining member(s)", null);
    }

    @SuppressWarnings("unchecked")
    private Long extractCallId(Map<String, Object> message) {
        Object callIdObj = message.get("callId");
        if (callIdObj == null) {
            Object payloadObj = message.get("payload");
            if (payloadObj instanceof Map) {
                callIdObj = ((Map<String, Object>) payloadObj).get("callId");
            }
        }
        if (callIdObj == null) return null;
        return callIdObj instanceof Number ? ((Number) callIdObj).longValue() : Long.parseLong(callIdObj.toString());
    }

    /**
     * Extract user ID from WebSocket session attributes
     */
    private Long extractUserIdFromSession(SimpMessageHeaderAccessor accessor) {
        try {
            if (accessor == null || accessor.getSessionAttributes() == null) {
                return null;
            }

            Object userIdObj = accessor.getSessionAttributes().get("userId");
            if (userIdObj instanceof Long) {
                return (Long) userIdObj;
            }

            if (userIdObj != null) {
                return Long.parseLong(userIdObj.toString());
            }

            return null;
        } catch (Exception e) {
            logError("extractUserIdFromSession", e.getMessage());
            return null;
        }
    }

    /**
     * Extract recipient user ID from message payload
     */
    private Long extractRecipientUserId(Map<String, Object> message) {
        try {
            // Try direct toUserId field
            Object toUserIdObj = message.get("toUserId");
            if (toUserIdObj != null) {
                if (toUserIdObj instanceof Long) {
                    return (Long) toUserIdObj;
                }
                return Long.parseLong(toUserIdObj.toString());
            }

            // Try from payload
            Object payloadObj = message.get("payload");
            if (payloadObj instanceof Map) {
                Map<String, Object> payload = (Map<String, Object>) payloadObj;
                Object toUserIdPayload = payload.get("toUserId");
                if (toUserIdPayload != null) {
                    if (toUserIdPayload instanceof Long) {
                        return (Long) toUserIdPayload;
                    }
                    return Long.parseLong(toUserIdPayload.toString());
                }
            }

            return null;
        } catch (Exception e) {
            logError("extractRecipientUserId", e.getMessage());
            return null;
        }
    }

    /**
     * Validate if event type is a known call signaling event
     */
    private boolean isValidEventTransition(String eventType) {
        return eventType != null && (
            eventType.equals("CALL_INVITE") ||
            eventType.equals("CALL_ACCEPT") ||
            eventType.equals("CALL_REJECT") ||
            eventType.equals("CALL_END")
        );
    }

    /**
     * Log info message
     */
    private void logInfo(String method, String message, Object payload) {
        System.out.println("[CallSignalingController] " + method + " | " + message);
        if (payload != null) {
            System.out.println("[CallSignalingController] Payload: " + payload);
        }
    }

    /**
     * Log error message
     */
    private void logError(String method, String message) {
        System.out.println("[CallSignalingController] ✗ " + method + " | ERROR: " + message);
    }
}
