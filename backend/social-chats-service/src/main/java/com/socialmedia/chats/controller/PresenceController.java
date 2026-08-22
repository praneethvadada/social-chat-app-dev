package com.socialmedia.chats.controller;

import com.socialmedia.chats.service.PresenceService;
import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Controller;
import lombok.RequiredArgsConstructor;
import java.time.LocalDateTime;
import java.util.HashMap;
import java.util.Map;

/**
 * PresenceController - Handle online/offline status updates (PHASE 3)
 * 
 * Handles presence updates when users come online/offline.
 * Broadcasts presence to conversation participants via WebSocket.
 */
@Controller
@RequiredArgsConstructor
public class PresenceController {
    
    private final SimpMessagingTemplate messagingTemplate;
    private final PresenceService presenceService;
    
    /**
     * Handle presence update from client
     * 
     * Receives: {userId, isOnline, timestamp}
     * Broadcasts: {type: "presence_update", userId, isOnline, timestamp}
     * 
     * Sent to: Topic (could be broadcast to all or specific group)
     */
    @MessageMapping("/presence.update")
    public void handlePresenceUpdate(@Payload Map<String, Object> payload) {
        try {
            final Long userId = Long.parseLong(payload.get("userId").toString());
            final Boolean isOnline = (Boolean) payload.get("isOnline");
            final String timestamp = payload.get("timestamp").toString();
            
            System.out.println("[PresenceController] Presence update from user=" + userId + " isOnline=" + isOnline);
            
            // ✅ CRITICAL FIX: Only add to presenceMap, never remove via controller!
            // Removing should ONLY happen when WebSocket session disconnects.
            // If we remove on isOnline=false, users appear offline even when their WS is still connected.
            if (isOnline != null && isOnline) {
                presenceService.markOnlineFromController(userId);
                System.out.println("[PresenceController] ✅ User " + userId + " added to presenceMap");
            } else if (isOnline != null && !isOnline) {
                // ✅ UPDATE: User requested to go offline (e.g. Logout)
                // We SHOULD remove them from presenceMap to ensure they don't appear online.
                presenceService.markOfflineFromController(userId);
                System.out.println("[PresenceController] ✅ User " + userId + " removed from presenceMap (Manual Offline/Logout)");
            }
            
            // Create presence notification
            Map<String, Object> notification = new HashMap<>();
            notification.put("type", "presence_update");
            notification.put("userId", userId);
            notification.put("isOnline", isOnline);
            notification.put("timestamp", timestamp);
            
            // Broadcast to all clients (could be optimized to only chat participants)
            // Currently sends to all connected users
            messagingTemplate.convertAndSend("/topic/presence", notification);
            
            System.out.println("[PresenceController] ✅ Presence broadcast: user=" + userId + " online=" + isOnline);
            
        } catch (Exception e) {
            System.out.println("[PresenceController] ❌ Error handling presence update: " + e.getMessage());
            e.printStackTrace();
        }
    }
    
    /**
     * Handle request for initial presence status
     * Client calls this AFTER subscribing to get current online users
     * 
     * Receives: {userId}
     * Sends: USER_CONNECTED for each online user to /user/{userId}/queue/presence
     */
    @MessageMapping("/presence.getInitial")
    public void handleGetInitialPresence(@Payload Map<String, Object> payload) {
        try {
            final Long userId = Long.parseLong(payload.get("userId").toString());
            System.out.println("[PresenceController] Initial presence request from user=" + userId);
            
            // Send all currently online users to this user
            presenceService.sendOnlineUsersTo(userId);
            
        } catch (Exception e) {
            System.out.println("[PresenceController] ❌ Error handling initial presence request: " + e.getMessage());
            e.printStackTrace();
        }
    }
}
