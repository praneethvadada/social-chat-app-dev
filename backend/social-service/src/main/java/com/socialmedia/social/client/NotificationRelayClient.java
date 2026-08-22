package com.socialmedia.social.client;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;

import java.util.HashMap;
import java.util.Map;

/**
 * Relays real-time notifications to chats-service, which owns the client
 * WebSocket connections after the chat split.
 *
 * Posts-side events (follow/like/comment, presence-to-followers) used to be
 * pushed on this service's own broker; clients are no longer connected there,
 * so we forward them over REST to chats-service's /internal/relay endpoint.
 *
 * Best-effort: failures are logged, not thrown (FCM push is the durable path).
 */
@Component
@Slf4j
public class NotificationRelayClient {

    private final RestTemplate restTemplate;
    private final String chatsServiceUrl;

    public NotificationRelayClient(RestTemplate restTemplate,
                                   @Value("${chats.service.url:http://localhost:8083}") String chatsServiceUrl) {
        this.restTemplate = restTemplate;
        this.chatsServiceUrl = chatsServiceUrl;
    }

    /** Deliver {@code payload} to {@code userId}'s {@code destination} (e.g. /queue/notifications). */
    public void relayToUser(Long userId, String destination, Object payload) {
        if (userId == null || destination == null) return;
        try {
            Map<String, Object> body = new HashMap<>();
            body.put("userId", userId);
            body.put("destination", destination);
            body.put("payload", payload);
            restTemplate.postForObject(chatsServiceUrl + "/internal/relay/to-user", body, Void.class);
        } catch (Exception e) {
            log.warn("[NotificationRelay] Failed to relay to user {} at {}: {}",
                    userId, destination, e.getMessage());
        }
    }
}
