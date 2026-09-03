package com.socialmedia.social.controller;

import com.socialmedia.social.service.FCMService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * Post-Phase-10, user-requested: auth-service has no Firebase/FCM setup of
 * its own — social-service already does (FCMService), so auth-service
 * relays security-alert push requests here (mirrors ChatsServiceRelayClient's
 * existing pattern for WebSocket pushes, just for FCM instead). Internal
 * service-to-service only — gated by InternalServiceAuthFilter + kept out of
 * SecurityConfig's anyRequest().authenticated(), same as /blocks/internal/**
 * and /profiles/internal/**.
 *
 * Known limitation, not silently glossed over: this reuses the EXISTING
 * single-token-per-user FCM mechanism (users.fcm_token, written by
 * ApiService.saveFCMToken on the client) - it reaches whichever mobile
 * device most recently synced its token, not literally every mobile device
 * the account has ever used. Device.pushToken (the newer, per-device
 * column added in Phase 1) is never actually populated by the Flutter
 * client today, so true multi-device fanout isn't available without a
 * separate, larger piece of work wiring that up end-to-end.
 */
@RestController
@RequestMapping("/push/internal")
public class InternalPushController {

    private final FCMService fcmService;

    public InternalPushController(FCMService fcmService) {
        this.fcmService = fcmService;
    }

    @PostMapping("/security-alert")
    public ResponseEntity<Void> securityAlert(@RequestBody Map<String, String> request) {
        Long userId = Long.valueOf(request.get("userId"));
        String title = request.get("title");
        String body = request.get("body");
        fcmService.sendNotificationToUser(userId, title, body, Map.of("type", "security_alert"));
        return ResponseEntity.ok().build();
    }
}
