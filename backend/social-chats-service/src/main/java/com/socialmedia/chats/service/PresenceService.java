package com.socialmedia.chats.service;

import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Service;

import java.util.concurrent.ConcurrentHashMap;

@Service
public class PresenceService {

    private final ConcurrentHashMap<Long, String> presenceMap = new ConcurrentHashMap<>();
    // Last time we heard from each online user (heartbeat / connect), epoch millis.
    // Used to reap users whose WebSocket disconnect event was missed.
    private final ConcurrentHashMap<Long, Long> lastSeen = new ConcurrentHashMap<>();
    private final SimpMessagingTemplate messagingTemplate;

    public PresenceService(SimpMessagingTemplate messagingTemplate) {
        this.messagingTemplate = messagingTemplate;
    }

    /** Record a heartbeat for an already-online user (called on presence.update). */
    public void touch(Long userId) {
        if (userId != null && presenceMap.containsKey(userId)) {
            lastSeen.put(userId, System.currentTimeMillis());
        }
    }

    /**
     * Remove users we haven't heard from in longer than {@code maxAgeMs} and
     * broadcast their disconnect. Safety net for missed WS disconnect events
     * (app killed, network drop). Replaces the old DB-based cleanup scheduler.
     */
    public int sweepStale(long maxAgeMs) {
        long cutoff = System.currentTimeMillis() - maxAgeMs;
        int removed = 0;
        for (java.util.Map.Entry<Long, Long> e : lastSeen.entrySet()) {
            if (e.getValue() < cutoff) {
                Long staleUser = e.getKey();
                markOffline(staleUser, null); // broadcasts USER_DISCONNECTED
                lastSeen.remove(staleUser);
                removed++;
            }
        }
        if (removed > 0) {
            System.out.println("[PRESENCE] 🧹 Swept " + removed + " stale user(s) offline (maxAge=" + maxAgeMs + "ms)");
        }
        return removed;
    }

    public void markOnline(Long userId, String sessionId) {
        if (userId == null) return;
        presenceMap.put(userId, sessionId);
        lastSeen.put(userId, System.currentTimeMillis());
        System.out.println("[PRESENCE] 🟢🟢🟢 ONLINE userId=" + userId + " sessionId=" + sessionId);
        System.out.println("[PRESENCE]    └─ Total online users: " + presenceMap.size() + " → " + presenceMap.keySet());
        // Broadcast USER_CONNECTED
        try {
            java.util.Map<String, Object> payload = new java.util.HashMap<>();
            payload.put("type", "USER_CONNECTED");
            payload.put("userId", userId);
            messagingTemplate.convertAndSend("/topic/presence", payload);
            System.out.println("[PRESENCE] ✅ Broadcast USER_CONNECTED for userId=" + userId);
        } catch (Exception e) {
            System.out.println("[PRESENCE] Failed to broadcast USER_CONNECTED: " + e.getMessage());
        }
    }

    public void markOffline(Long userId, String sessionId) {
        if (userId == null) return;
        // Only remove if sessionId matches current mapping to avoid racing sessions
        String existing = presenceMap.get(userId);
        if (existing != null && (sessionId == null || existing.equals(sessionId))) {
            presenceMap.remove(userId);
            lastSeen.remove(userId);
            try {
                java.util.Map<String, Object> payload = new java.util.HashMap<>();
                payload.put("type", "USER_DISCONNECTED");
                payload.put("userId", userId);
                messagingTemplate.convertAndSend("/topic/presence", payload);
                System.out.println("[PRESENCE] OFFLINE userId=" + userId);
            } catch (Exception e) {
                System.out.println("[PRESENCE] Failed to broadcast USER_DISCONNECTED: " + e.getMessage());
            }
        }
    }

    public boolean isOnline(Long userId) {
        return presenceMap.containsKey(userId);
    }
    
    /**
     * Get all currently online user IDs
     */
    public java.util.Set<Long> getOnlineUserIds() {
        return presenceMap.keySet();
    }
    
    /**
     * Send current online users to a specific user (for initial sync)
     */
    public void sendOnlineUsersTo(Long userId) {
        if (userId == null) return;
        
        try {
            java.util.Set<Long> onlineUsers = presenceMap.keySet();
            System.out.println("[PRESENCE] 📤📤📤 sendOnlineUsersTo called for userId=" + userId);
            System.out.println("[PRESENCE]    ├─ Online users count: " + onlineUsers.size());
            System.out.println("[PRESENCE]    └─ Online user IDs: " + onlineUsers);
            
            int sentCount = 0;
            for (Long onlineUserId : onlineUsers) {
                if (!onlineUserId.equals(userId)) {  // Don't send user their own status
                    java.util.Map<String, Object> payload = new java.util.HashMap<>();
                    payload.put("type", "USER_CONNECTED");
                    payload.put("userId", onlineUserId);
                    
                    System.out.println("[PRESENCE]    Sending USER_CONNECTED for " + onlineUserId + " to /user/" + userId + "/queue/presence");
                    messagingTemplate.convertAndSendToUser(
                        userId.toString(),
                        "/queue/presence",
                        payload
                    );
                    sentCount++;
                }
            }
            
            System.out.println("[PRESENCE] ✅✅✅ Sent " + sentCount + " initial presence updates to userId=" + userId);
        } catch (Exception e) {
            System.out.println("[PRESENCE] ❌ Error sending initial presence: " + e.getMessage());
            e.printStackTrace();
        }
    }
    
    /**
     * Mark user online WITHOUT broadcasting (used by PresenceController to avoid double broadcast)
     * The controller will handle the broadcast separately
     */
    public void markOnlineFromController(Long userId) {
        if (userId == null) return;
        presenceMap.put(userId, "controller-" + System.currentTimeMillis());
        lastSeen.put(userId, System.currentTimeMillis());
        System.out.println("[PRESENCE] 🟢 ONLINE (from controller) userId=" + userId);
        System.out.println("[PRESENCE]    └─ Total online users: " + presenceMap.size() + " → " + presenceMap.keySet());
    }
    
    /**
     * Mark user offline WITHOUT broadcasting (used by PresenceController to avoid double broadcast)
     */
    public void markOfflineFromController(Long userId) {
        if (userId == null) return;
        presenceMap.remove(userId);
        lastSeen.remove(userId);
        System.out.println("[PRESENCE] ⚫ OFFLINE (from controller) userId=" + userId);
        System.out.println("[PRESENCE]    └─ Total online users: " + presenceMap.size() + " → " + presenceMap.keySet());
    }
}
