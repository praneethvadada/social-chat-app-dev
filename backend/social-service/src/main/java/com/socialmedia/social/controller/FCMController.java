package com.socialmedia.social.controller;

import com.socialmedia.social.service.FCMService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.Map;

/**
 * FCM Controller
 * Handles Firebase Cloud Messaging token management and push notifications
 */
@RestController
@RequestMapping("/fcm-token")
@RequiredArgsConstructor
@Slf4j
@Tag(name = "Push Notifications", description = "Firebase Cloud Messaging for push notifications")
public class FCMController {

    private final FCMService fcmService;

    /**
     * Save FCM token for authenticated user
     * Called when mobile app starts - sends the FCM token for receiving push notifications
     *
     * @param userId FCM token from mobile device
     * @param request Contains { "token": "fcm_token_string" }
     * @return Success response
     */
    @PostMapping
    @Operation(summary = "Save FCM token for push notifications")
    public ResponseEntity<?> saveFCMToken(
            @RequestAttribute("userId") Long userId,
            @RequestBody FCMTokenRequest request) {

        try {
            if (request.getToken() == null || request.getToken().isEmpty()) {
                return ResponseEntity.badRequest().body(
                        createErrorResponse("FCM token is required")
                );
            }

            fcmService.saveFCMToken(userId, request.getToken());

            log.info("[FCM] ✅ FCM token saved for user {}", userId);

            return ResponseEntity.ok(createSuccessResponse(
                    "FCM token saved successfully",
                    userId
            ));
        } catch (Exception e) {
            log.error("[FCM] ❌ Error saving FCM token: {}", e.getMessage());
            return ResponseEntity.status(500).body(
                    createErrorResponse("Failed to save FCM token: " + e.getMessage())
            );
        }
    }

    /**
     * Send test push notification (for testing purposes)
     * Only for development - send test notification to authenticated user
     */
    @PostMapping("/test")
    @Operation(summary = "Send test notification (development only)")
    public ResponseEntity<?> sendTestNotification(
            @RequestAttribute("userId") Long userId) {

        try {
            Map<String, String> data = new HashMap<>();
            data.put("type", "test");
            data.put("timestamp", String.valueOf(System.currentTimeMillis()));

            boolean sent = fcmService.sendNotificationToUser(
                    userId,
                    "Test Notification",
                    "Push notifications are working! 🚀",
                    data
            );

            if (sent) {
                return ResponseEntity.ok(createSuccessResponse(
                        "Test notification sent successfully",
                        userId
                ));
            } else {
                return ResponseEntity.status(400).body(
                        createErrorResponse("No FCM token found for user - notification not sent")
                );
            }
        } catch (Exception e) {
            log.error("[FCM] ❌ Error sending test notification: {}", e.getMessage());
            return ResponseEntity.status(500).body(
                    createErrorResponse("Failed to send test notification: " + e.getMessage())
            );
        }
    }

    // ===================== HELPER METHODS =====================

    private Map<String, Object> createSuccessResponse(String message, Long userId) {
        Map<String, Object> response = new HashMap<>();
        response.put("success", true);
        response.put("message", message);
        response.put("userId", userId);
        response.put("timestamp", System.currentTimeMillis());
        return response;
    }

    private Map<String, Object> createErrorResponse(String message) {
        Map<String, Object> response = new HashMap<>();
        response.put("success", false);
        response.put("error", message);
        response.put("timestamp", System.currentTimeMillis());
        return response;
    }

    // ===================== DTO CLASS =====================

    /**
     * Request body for saving FCM token
     */
    public static class FCMTokenRequest {
        private String token;

        public String getToken() {
            return token;
        }

        public void setToken(String token) {
            this.token = token;
        }
    }
}
