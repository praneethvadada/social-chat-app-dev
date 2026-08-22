package com.socialmedia.social.service;

import com.google.firebase.messaging.FirebaseMessaging;
import com.google.firebase.messaging.Message;
import com.google.firebase.messaging.Notification;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestTemplate;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Firebase Cloud Messaging Service
 * Sends push notifications to mobile devices
 * Handles all notification types: messages, likes, comments, mentions, calls, follows
 * Uses REST calls to auth-service for user data
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class FCMService {

    private final RestTemplate restTemplate;
    
    @Value("${auth.service.url:http://localhost:8081}")
    private String authServiceUrl;

    /**
     * Save user's FCM token via auth-service REST call
     * Called when user opens app - token is sent from mobile app
     */
    public void saveFCMToken(Long userId, String token) {
        try {
            String url = authServiceUrl + "/users/" + userId + "/fcm-token";
            Map<String, String> tokenData = new HashMap<>();
            tokenData.put("fcmToken", token);
            
            restTemplate.postForObject(url, tokenData, Void.class);
            log.info("[FCM] ✅ FCM token saved for user {}: {}...", userId, token.substring(0, Math.min(20, token.length())));
        } catch (Exception e) {
            log.error("[FCM] ❌ Error saving FCM token for user {}: {}", userId, e.getMessage());
        }
    }

    /**
     * Send notification to single user
     */
    public boolean sendNotificationToUser(Long userId, String title, String body, Map<String, String> data) {
        try {
            String fcmToken = getFCMToken(userId);

            if (fcmToken == null || fcmToken.isEmpty()) {
                log.warn("[FCM] ⚠️ No FCM token for user {}", userId);
                return false;
            }

            return sendNotificationToToken(fcmToken, title, body, data);
        } catch (Exception e) {
            log.error("[FCM] ❌ Error sending notification to user {}: {}", userId, e.getMessage());
            return false;
        }
    }
    
    /**
     * Get FCM token from auth-service
     */
    private String getFCMToken(Long userId) {
        try {
            log.info("[FCM DEBUG] Getting FCM token for user {}", userId);
            String url = authServiceUrl + "/users/" + userId + "/fcm-token";
            log.info("[FCM DEBUG] Auth-service URL: {}", url);
            
            String token = restTemplate.getForObject(url, String.class);
            log.info("[FCM DEBUG] Token retrieved: {}", token != null ? token.substring(0, Math.min(20, token.length())) + "..." : "NULL");
            log.info("[FCM DEBUG] Token is null? {}", token == null);
            log.info("[FCM DEBUG] Token is empty? {}", token != null && token.isEmpty());
            log.info("[FCM DEBUG] Token length: {}", token != null ? token.length() : 0);
            
            return token;
        } catch (Exception e) {
            log.error("[FCM DEBUG] Error getting FCM token for user {}: {}", userId, e.getMessage());
            log.error("[FCM DEBUG] Exception type: {}", e.getClass().getName());
            log.error("[FCM DEBUG] Full exception: ", e);
            return null;
        }
    }

    /**
     * Send notification to multiple users
     */
    public void sendNotificationToMultipleUsers(List<Long> userIds, String title, String body, Map<String, String> data) {
        for (Long userId : userIds) {
            sendNotificationToUser(userId, title, body, data);
        }
    }

    /**
     * Send notification using FCM token
     */
    private boolean sendNotificationToToken(String token, String title, String body, Map<String, String> data) {
        try {
            Map<String, String> notificationData = data != null ? new HashMap<>(data) : new HashMap<>();
            
            // 🔥 CRITICAL: Check message type
            boolean isCall = notificationData.containsKey("type") && "CALL_INVITE".equalsIgnoreCase(notificationData.get("type"));
            boolean isMessage = notificationData.containsKey("type") && "new_message".equalsIgnoreCase(notificationData.get("type"));

            Message.Builder messageBuilder = Message.builder()
                    .setToken(token)
                    .putAllData(notificationData);

            if (isCall) {
                // 📞 CALL MODE: Data-only, High Priority, No Notification Payload
                // This ensures onMessageReceived is triggered even if app is closed
                messageBuilder.setAndroidConfig(com.google.firebase.messaging.AndroidConfig.builder()
                        .setPriority(com.google.firebase.messaging.AndroidConfig.Priority.HIGH)
                    // Keep call invite alive briefly to survive short doze/network delays.
                    .setTtl(120 * 1000) // 120s
                        .build());
                
                log.info("[FCM] 📞 Sending CALL Data Message (Data-only, High Priority)");
            } else if (isMessage) {
                // 💬 MESSAGE MODE: Data-only, High Priority, No Notification Payload
                // Flutter handles all message notification UI to prevent duplicates
                messageBuilder.setAndroidConfig(com.google.firebase.messaging.AndroidConfig.builder()
                        .setPriority(com.google.firebase.messaging.AndroidConfig.Priority.HIGH)
                        .setTtl(60 * 1000) // 60s for messages
                        .build());
                
                log.info("[FCM] 💬 Sending MESSAGE Data Message (Data-only, Flutter will show UI)");
            } else {
                // 📩 OTHER: Standard Notification with UI (follows, likes, comments)
                messageBuilder.setAndroidConfig(com.google.firebase.messaging.AndroidConfig.builder()
                    .setPriority(com.google.firebase.messaging.AndroidConfig.Priority.HIGH)
                    .build());
                messageBuilder.setNotification(Notification.builder()
                        .setTitle(title)
                        .setBody(body)
                        .build());
                
                log.info("[FCM] 📬 Sending INTERACTION Notification (with UI)");
            }

            String response = FirebaseMessaging.getInstance().send(messageBuilder.build());
            log.info("[FCM] ✅ Notification sent: {}", response);
            return true;
        } catch (Exception e) {
            log.error("[FCM] ❌ Error sending notification: {}", e.getMessage());
            return false;
        }
    }

    // =====================================================
    // TRIGGER FUNCTIONS - Call these in your API endpoints
    // =====================================================

    /**
     * TRIGGER: New message received
     * Call this in MessageController.sendMessage()
     */
    public void onNewMessage(Long senderId, Long recipientId, String messagePreview) {
        try {
            String senderName = getUserUsername(senderId);
            if (senderName == null) return;

            String preview = messagePreview.length() > 50 
                    ? messagePreview.substring(0, 50) + "..." 
                    : messagePreview;

            Map<String, String> data = new HashMap<>();
            data.put("type", "new_message");
            data.put("senderId", senderId.toString());
            data.put("senderName", senderName);
            data.put("messagePreview", preview);

            sendNotificationToUser(
                    recipientId,
                    "New Message from " + senderName,
                    preview,
                    data
            );

            log.info("[FCM] 📬 Chat notification sent to user {} with sender: {}", recipientId, senderName);
        } catch (Exception e) {
            log.error("[FCM] Error in onNewMessage: {}", e.getMessage());
        }
    }
    
    /**
     * Get user username from auth-service
     */
    private String getUserUsername(Long userId) {
        try {
            String url = authServiceUrl + "/users/" + userId + "/username";
            String username = restTemplate.getForObject(url, String.class);
            return username;
        } catch (Exception e) {
            log.error("[FCM] Error getting username for user {}: {}", userId, e.getMessage());
            return null;
        }
    }

    /**
     * TRIGGER: Post liked
     * Call this in LikeController.likePost()
     */
    public void onPostLiked(Long postOwnerId, Long likerUserId, Long postId) {
        try {
            String likerName = getUserUsername(likerUserId);
            if (likerName == null) return;

            Map<String, String> data = new HashMap<>();
            data.put("type", "like");
            data.put("postId", postId.toString());
            data.put("userId", likerUserId.toString());

            sendNotificationToUser(
                    postOwnerId,
                    "Post Liked",
                    likerName + " liked your post",
                    data
            );

            log.info("[FCM] ❤️ Like notification sent to user {}", postOwnerId);
        } catch (Exception e) {
            log.error("[FCM] Error in onPostLiked: {}", e.getMessage());
        }
    }

    /**
     * TRIGGER: Comment on post
     * Call this in CommentController.createComment()
     */
    public void onPostCommented(Long postOwnerId, Long commenterUserId, Long postId, String commentContent) {
        try {
            String commenterName = getUserUsername(commenterUserId);
            if (commenterName == null) return;

            String preview = commentContent.length() > 50 
                    ? commentContent.substring(0, 50) + "..." 
                    : commentContent;

            Map<String, String> data = new HashMap<>();
            data.put("type", "comment");
            data.put("postId", postId.toString());
            data.put("userId", commenterUserId.toString());

            sendNotificationToUser(
                    postOwnerId,
                    "New Comment",
                    commenterName + ": " + preview,
                    data
            );

            log.info("[FCM] 💬 Comment notification sent to user {}", postOwnerId);
        } catch (Exception e) {
            log.error("[FCM] Error in onPostCommented: {}", e.getMessage());
        }
    }

    /**
     * TRIGGER: User mentioned
     * Call this in NotificationController.sendMentionNotifications()
     */
    public void onUserMentioned(List<Long> mentionedUserIds, Long mentionerUserId, Long postId, String postContent) {
        try {
            String mentionerName = getUserUsername(mentionerUserId);
            if (mentionerName == null) return;

            String preview = postContent.length() > 50 
                    ? postContent.substring(0, 50) + "..." 
                    : postContent;

            Map<String, String> data = new HashMap<>();
            data.put("type", "mention");
            data.put("postId", postId.toString());
            data.put("userId", mentionerUserId.toString());

            for (Long userId : mentionedUserIds) {
                sendNotificationToUser(
                        userId,
                        "You were mentioned",
                        mentionerName + " mentioned you",
                        data
                );
            }

            log.info("[FCM] @ Mention notification sent to {} users", mentionedUserIds.size());
        } catch (Exception e) {
            log.error("[FCM] Error in onUserMentioned: {}", e.getMessage());
        }
    }

    /**
     * TRIGGER: User followed
     * Call this in FollowerController.followUser()
     */
    public void onUserFollowed(Long followedUserId, Long followerUserId) {
        try {
            String followerName = getUserUsername(followerUserId);
            if (followerName == null) return;

            Map<String, String> data = new HashMap<>();
            data.put("type", "follow");
            data.put("userId", followerUserId.toString());

            sendNotificationToUser(
                    followedUserId,
                    "New Follower",
                    followerName + " started following you",
                    data
            );

            log.info("[FCM] 👤 Follow notification sent to user {}", followedUserId);
        } catch (Exception e) {
            log.error("[FCM] Error in onUserFollowed: {}", e.getMessage());
        }
    }

    /**
     * TRIGGER: Incoming call
     * Call this in CallSignalingController.initiateCall()
     */
    public void onIncomingCall(Long recipientUserId, Long callerUserId, String channelId, boolean isVideo) {
        try {
            String callerName = getUserUsername(callerUserId);
            if (callerName == null) return;

            Map<String, String> data = new HashMap<>();
            data.put("type", "CALL_INVITE");
            data.put("callerId", callerUserId.toString());
            data.put("fromUserId", callerUserId.toString());  // Flutter expects this field
            data.put("actorId", callerUserId.toString());     // Backup field name
            data.put("actorUsername", callerName);             // Caller name
            data.put("callerName", callerName);                // Another backup
            data.put("channelId", channelId);
            data.put("channelName", channelId); // ✅ MATCH Android expectation
            data.put("isVideo", String.valueOf(isVideo)); // ✅ Pass isVideo flag
            data.put("playRingtone", "true");   // ✅ Force ringtone
            data.put("action", "INCOMING_CALL");

            sendNotificationToUser(
                    recipientUserId,
                    "Incoming Call",
                    callerName + " is calling...",
                    data
            );
            
            log.info("[FCM] 📞 Call notification sent to user {} from caller {} (video={})", recipientUserId, callerUserId, isVideo);
        } catch (Exception e) {
            log.error("[FCM] Error in onIncomingCall: {}", e.getMessage());
        }
    }

    /**
     * TRIGGER: Follow request received
     * Call this in FollowRequestController.sendFollowRequest()
     */
    public void onFollowRequestReceived(Long receiverUserId, Long requesterUserId) {
        try {
            String requesterName = getUserUsername(requesterUserId);
            if (requesterName == null) return;

            Map<String, String> data = new HashMap<>();
            data.put("type", "follow_request");
            data.put("userId", requesterUserId.toString());

            sendNotificationToUser(
                    receiverUserId,
                    "Follow Request",
                    requesterName + " sent you a follow request",
                    data
            );

            log.info("[FCM] 👥 Follow request notification sent to user {}", receiverUserId);
        } catch (Exception e) {
            log.error("[FCM] Error in onFollowRequestReceived: {}", e.getMessage());
        }
    }
}
