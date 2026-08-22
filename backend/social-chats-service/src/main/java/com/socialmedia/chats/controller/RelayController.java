package com.socialmedia.chats.controller;

import lombok.Data;
import lombok.extern.slf4j.Slf4j;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

/**
 * Internal relay: lets sibling services push a real-time message to a user who
 * is connected to THIS service's WebSocket broker.
 *
 * Needed because chats-service now owns the client WebSocket connections. When
 * posts-service (social-service) wants to deliver a follow/like/comment
 * notification in real time, it POSTs here and we forward it over STOMP.
 *
 * Service-to-service only; permitted without a user JWT (see SecurityConfig).
 */
@RestController
@RequestMapping("/internal/relay")
@Slf4j
public class RelayController {

    private final SimpMessagingTemplate messagingTemplate;

    public RelayController(SimpMessagingTemplate messagingTemplate) {
        this.messagingTemplate = messagingTemplate;
    }

    @PostMapping("/to-user")
    public ResponseEntity<Void> toUser(@RequestBody RelayRequest req) {
        if (req.getUserId() == null || req.getDestination() == null) {
            return ResponseEntity.badRequest().build();
        }
        try {
            messagingTemplate.convertAndSendToUser(
                    req.getUserId().toString(), req.getDestination(), req.getPayload());
            return ResponseEntity.ok().build();
        } catch (Exception e) {
            log.warn("[Relay] Failed to deliver to user {} at {}: {}",
                    req.getUserId(), req.getDestination(), e.getMessage());
            return ResponseEntity.ok().build(); // best-effort; don't fail the caller
        }
    }

    @Data
    public static class RelayRequest {
        private Long userId;
        private String destination;   // e.g. /queue/notifications
        private Object payload;       // arbitrary JSON forwarded as-is
    }
}
