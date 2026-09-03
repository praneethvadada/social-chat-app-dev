package com.socialmedia.auth.client;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;

import java.util.Map;

/**
 * Post-Phase-10, user-requested: pushes a mobile notification for a
 * security event (login / failed-login-attempt) via social-service's
 * existing FCM setup (InternalPushController → FCMService) — auth-service
 * has no Firebase config of its own. Same direct-URL-plus-graceful-
 * degradation shape as ChatsServiceRelayClient, just to social-service
 * instead of chats-service, and for FCM instead of a WebSocket frame.
 * Best-effort only: a failure here must never block the login flow that
 * triggered it.
 */
@Component
public class SecurityPushRelayClient {

    private static final Logger log = LoggerFactory.getLogger(SecurityPushRelayClient.class);

    private final RestTemplate restTemplate;

    @Value("${social.service.url:http://localhost:8082}")
    private String socialServiceUrl;

    public SecurityPushRelayClient(RestTemplate restTemplate) {
        this.restTemplate = restTemplate;
    }

    // Must never block the login/security-event flow that triggered it —
    // see AsyncConfig's own doc comment for why this matters (a real 3+
    // minute hang was observed in testing before this was added).
    @Async
    public void sendSecurityAlert(Long userId, String title, String body) {
        try {
            restTemplate.postForEntity(
                    socialServiceUrl + "/push/internal/security-alert",
                    Map.of("userId", userId.toString(), "title", title, "body", body),
                    Void.class
            );
        } catch (Exception e) {
            log.warn("Failed to push security alert to user {}: {}", userId, e.getMessage());
        }
    }
}
