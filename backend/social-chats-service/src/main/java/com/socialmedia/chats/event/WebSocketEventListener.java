package com.socialmedia.chats.event;

import com.socialmedia.chats.service.PresenceService;
import org.springframework.context.event.EventListener;
import org.springframework.messaging.simp.stomp.StompHeaderAccessor;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.messaging.SessionConnectedEvent;
import org.springframework.web.socket.messaging.SessionDisconnectEvent;

/**
 * WebSocket event listener to handle connect/disconnect and presence broadcasting.
 * Stores presence in-memory (ConcurrentHashMap inside PresenceService) and broadcasts
 * USER_CONNECTED / USER_DISCONNECTED events to /topic/presence.
 */
@Component
public class WebSocketEventListener {

    private final PresenceService presenceService;

    public WebSocketEventListener(PresenceService presenceService) {
        this.presenceService = presenceService;
    }

    @EventListener
    public void handleWebSocketConnectListener(SessionConnectedEvent event) {
        try {
            StompHeaderAccessor headerAccessor = StompHeaderAccessor.wrap(event.getMessage());
            Object sessionId = headerAccessor.getSessionId();
            System.out.println("[WS] CONNECTED session=" + sessionId);
            
            // Debug: Log what we have access to
            System.out.println("[WS]    ├─ sessionAttributes: " + headerAccessor.getSessionAttributes());
            System.out.println("[WS]    ├─ user (principal): " + headerAccessor.getUser());
            
            Long userId = null;
            
            // Method 1: Try to get from session attributes
            Object userIdObj = headerAccessor.getSessionAttributes() != null 
                ? headerAccessor.getSessionAttributes().get("userId") 
                : null;
            if (userIdObj != null) {
                userId = Long.parseLong(userIdObj.toString());
                System.out.println("[WS]    ├─ userId from sessionAttributes: " + userId);
            }
            
            // Method 2: Try to get from principal (fallback)
            if (userId == null && headerAccessor.getUser() != null) {
                try {
                    userId = Long.parseLong(headerAccessor.getUser().getName());
                    System.out.println("[WS]    ├─ userId from principal: " + userId);
                } catch (NumberFormatException e) {
                    System.out.println("[WS]    ├─ principal name not a number: " + headerAccessor.getUser().getName());
                }
            }
            
            if (userId != null) {
                System.out.println("[WS]    └─ ✅ Calling markOnline for userId=" + userId);
                presenceService.markOnline(userId, sessionId != null ? sessionId.toString() : null);
            } else {
                System.out.println("[WS]    └─ ❌ No userId found - cannot mark online!");
            }
        } catch (Exception e) {
            System.out.println("[WS] CONNECTED - error obtaining session/user: " + e.getMessage());
            e.printStackTrace();
        }
    }

    @EventListener
    public void handleWebSocketDisconnectListener(SessionDisconnectEvent event) {
        try {
            StompHeaderAccessor headerAccessor = StompHeaderAccessor.wrap(event.getMessage());
            Object sessionId = headerAccessor.getSessionId();
            System.out.println("[WS] DISCONNECTED session=" + sessionId);
            
            // Debug: Log what we have access to
            System.out.println("[WS]    ├─ sessionAttributes: " + headerAccessor.getSessionAttributes());
            System.out.println("[WS]    ├─ user (principal): " + headerAccessor.getUser());
            
            Long userId = null;
            
            // Method 1: Try to get from session attributes
            Object userIdObj = headerAccessor.getSessionAttributes() != null 
                ? headerAccessor.getSessionAttributes().get("userId") 
                : null;
            if (userIdObj != null) {
                userId = Long.parseLong(userIdObj.toString());
                System.out.println("[WS]    ├─ userId from sessionAttributes: " + userId);
            }
            
            // Method 2: Try to get from principal (fallback)
            if (userId == null && headerAccessor.getUser() != null) {
                try {
                    userId = Long.parseLong(headerAccessor.getUser().getName());
                    System.out.println("[WS]    ├─ userId from principal: " + userId);
                } catch (NumberFormatException e) {
                    System.out.println("[WS]    ├─ principal name not a number: " + headerAccessor.getUser().getName());
                }
            }
            
            if (userId != null) {
                System.out.println("[WS]    └─ ✅ Calling markOffline for userId=" + userId);
                presenceService.markOffline(userId, sessionId != null ? sessionId.toString() : null);
            } else {
                System.out.println("[WS]    └─ ❌ No userId found - cannot mark offline!");
            }
        } catch (Exception e) {
            System.out.println("[WS] DISCONNECTED - error obtaining session/user: " + e.getMessage());
            e.printStackTrace();
        }
    }
}
