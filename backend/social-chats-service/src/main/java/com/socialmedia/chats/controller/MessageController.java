package com.socialmedia.chats.controller;

import com.socialmedia.chats.dto.ConversationResponse;
import com.socialmedia.chats.dto.MessageRequest;
import com.socialmedia.chats.dto.MessageResponse;
import com.socialmedia.chats.service.MessageService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.http.ResponseEntity;
import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.messaging.simp.SimpMessageHeaderAccessor;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@Controller
@RequiredArgsConstructor
public class MessageController {

    private final MessageService messageService;
    private final org.springframework.messaging.simp.SimpMessagingTemplate messagingTemplate;

    @PostMapping("/messages")
    @ResponseBody
    public ResponseEntity<MessageResponse> sendMessage(
            @Valid @RequestBody MessageRequest request,
            @RequestAttribute("userId") Long userId) {
        MessageResponse response = messageService.sendMessage(request, userId);
        return ResponseEntity.ok(response);
    }

    @GetMapping("/messages/conversation/{otherUserId}")
    @ResponseBody
    public ResponseEntity<Page<MessageResponse>> getConversation(
            @PathVariable Long otherUserId,
            @RequestAttribute("userId") Long userId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "50") int size) {
        Pageable pageable = PageRequest.of(page, size);
        Page<MessageResponse> messages = messageService.getConversation(userId, otherUserId, pageable);
        return ResponseEntity.ok(messages);
    }

    @PutMapping("/messages/{messageId}/read")
    @ResponseBody
    public ResponseEntity<Void> markAsRead(
            @PathVariable Long messageId,
            @RequestAttribute("userId") Long userId) {
        messageService.markAsRead(messageId, userId);
        return ResponseEntity.ok().build();
    }

    @PutMapping("/messages/conversation/{otherUserId}/read")
    @ResponseBody
    public ResponseEntity<Void> markConversationAsRead(
            @PathVariable Long otherUserId,
            @RequestAttribute("userId") Long userId) {
        messageService.markConversationAsRead(userId, otherUserId);
        return ResponseEntity.ok().build();
    }

    @GetMapping("/messages/unread-count")
    @ResponseBody
    public ResponseEntity<Long> getUnreadCount(
            @RequestAttribute("userId") Long userId) {
        Long count = messageService.getUnreadCount(userId);
        return ResponseEntity.ok(count);
    }

    @GetMapping("/messages/unread")
    @ResponseBody
    public ResponseEntity<List<MessageResponse>> getUnreadMessages(
            @RequestAttribute("userId") Long userId) {
        List<MessageResponse> messages = messageService.getUnreadMessages(userId);
        return ResponseEntity.ok(messages);
    }

    @GetMapping("/messages/conversations")
    @ResponseBody
    public ResponseEntity<List<ConversationResponse>> getConversations(
            @RequestAttribute("userId") Long userId) {
        List<ConversationResponse> conversations = messageService.getConversations(userId);
        return ResponseEntity.ok(conversations);
    }

    @DeleteMapping("/messages/conversation/{otherUserId}")
    @ResponseBody
    public ResponseEntity<Void> deleteConversation(
            @PathVariable Long otherUserId,
            @RequestAttribute("userId") Long userId) {
        messageService.deleteConversation(userId, otherUserId);
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/messages/conversation/{otherUserId}/restore")
    @ResponseBody
    public ResponseEntity<Void> restoreConversation(
            @PathVariable Long otherUserId,
            @RequestAttribute("userId") Long userId) {
        messageService.restoreConversation(userId, otherUserId);
        return ResponseEntity.ok().build();
    }

    @MessageMapping("/chat.send")
    public void sendMessageViaWebSocket(
            @Payload MessageRequest request,
            SimpMessageHeaderAccessor headerAccessor) {
        try {
            // Debug: Print incoming request
            System.out.println("\n[MessageController] ===== WEBSOCKET MESSAGE RECEIVED =====");
            if (request != null) {
                System.out.println("[MessageController] Request receiverId: " + request.getReceiverId());
                System.out.println("[MessageController] Request content: " + request.getContent());
                System.out.println("[MessageController] Request mediaUrl: " + request.getMediaUrl());
                System.out.println("[MessageController] Request clientMessageId: " + request.getClientMessageId());
            } else {
                System.out.println("[MessageController] Request is NULL!");
            }
            
            Object userIdObj = headerAccessor.getSessionAttributes().get("userId");
            Long userId = null;

            if (userIdObj != null) {
                userId = Long.parseLong(userIdObj.toString());
            }

            String clientMessageId = request != null ? request.getClientMessageId() : null;

            if (userId == null) {
                // Cannot route an ack without knowing the sender. The client-side ack
                // timeout is the safety net that surfaces this as a failed message.
                System.out.println("[MessageController] ❌ ERROR: userId not found in session - cannot ack");
                return;
            }

            System.out.println("[MessageController] Sender userId: " + userId);
            System.out.println("[MessageController] Receiver userId (from request): " + (request != null ? request.getReceiverId() : "null"));

            if (request == null || request.getReceiverId() == null) {
                System.out.println("[MessageController] ❌ ERROR: receiverId is null in request!");
                sendAck(userId, clientMessageId, null, false, "Recipient missing - message not sent");
                return;
            }

            messageService.sendMessage(request, userId);
            System.out.println("[MessageController] ✅ Message sent to service");
            sendAck(userId, clientMessageId, request.getReceiverId(), true, null);

            System.out.println("[MessageController] ===== END WEBSOCKET MESSAGE =====\n");
        } catch (Exception e) {
            System.out.println("[MessageController] ❌ Error in WebSocket send: " + e.getMessage());
            e.printStackTrace();

            // Report the failure back to the sender so the message shows as failed
            // rather than sitting on a misleading tick.
            try {
                Object uid = headerAccessor.getSessionAttributes().get("userId");
                if (uid != null && request != null) {
                    sendAck(Long.parseLong(uid.toString()), request.getClientMessageId(),
                            request.getReceiverId(), false, "Server error - message not sent");
                }
            } catch (Exception ackError) {
                System.out.println("[MessageController] ❌ Failed to send error ack: " + ackError.getMessage());
            }
        }
    }

    /**
     * Send a delivery acknowledgement for an outgoing message back to its sender.
     * The client keeps the message in the pending (⏱) state until this arrives,
     * so every send resolves to either ✓ (success) or ❌ (failure).
     */
    private void sendAck(Long senderId, String clientMessageId, Long receiverId,
                         boolean success, String error) {
        try {
            java.util.Map<String, Object> ack = new java.util.HashMap<>();
            ack.put("clientMessageId", clientMessageId);
            ack.put("receiverId", receiverId);
            ack.put("success", success);
            if (error != null) {
                ack.put("error", error);
            }

            messagingTemplate.convertAndSendToUser(
                    senderId.toString(),
                    "/queue/message-ack",
                    ack);
            System.out.println("[MessageController] 📬 ACK sent to /user/" + senderId
                    + "/queue/message-ack success=" + success + " clientMessageId=" + clientMessageId);
        } catch (Exception e) {
            System.out.println("[MessageController] ❌ Error sending ack: " + e.getMessage());
        }
    }

    @MessageMapping("/chat.typing")
    public void handleTypingViaWebSocket(@Payload com.socialmedia.chats.dto.TypingRequest request,
                                         SimpMessageHeaderAccessor headerAccessor) {
        try {
            Object userIdObj = headerAccessor.getSessionAttributes().get("userId");
            Long userId = null;
            if (userIdObj != null) {
                userId = Long.parseLong(userIdObj.toString());
            }

            if (userId != null && request.getReceiverId() != null) {
                java.util.Map<String, Object> payload = new java.util.HashMap<>();
                payload.put("type", "typing");
                payload.put("fromUserId", userId);
                payload.put("toUserId", request.getReceiverId());
                payload.put("isTyping", request.getIsTyping() == Boolean.TRUE);
                payload.put("timestamp", java.time.LocalDateTime.now(java.time.ZoneId.of("UTC")));

                // Forward typing event to the recipient's typing queue
                try {
                    messagingTemplate.convertAndSendToUser(request.getReceiverId().toString(), "/queue/typing", payload);
                } catch (Exception ex) {
                    System.out.println("[MessageController] Error forwarding typing event: " + ex.getMessage());
                }
            }
        } catch (Exception e) {
            System.out.println("[MessageController] Error handling typing via WebSocket: " + e.getMessage());
            e.printStackTrace();
        }
    }

}
