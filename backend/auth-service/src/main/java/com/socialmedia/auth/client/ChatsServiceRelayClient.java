package com.socialmedia.auth.client;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;

import java.util.Map;

/**
 * Pushes a live WebSocket notification to a user via chats-service's
 * existing generic relay (RelayController.POST /internal/relay/to-user) —
 * same direct-URL-plus-graceful-degradation shape as chats-service's own
 * UserLookupClient calling auth-service, just in the other direction.
 * Best-effort only: a failure here must never block the request that
 * triggered it (e.g. a storage transfer completing).
 */
@Component
public class ChatsServiceRelayClient {

    private static final Logger log = LoggerFactory.getLogger(ChatsServiceRelayClient.class);

    private final RestTemplate restTemplate;

    @Value("${chats.service.url:http://localhost:8083}")
    private String chatsServiceUrl;

    public ChatsServiceRelayClient(RestTemplate restTemplate) {
        this.restTemplate = restTemplate;
    }

    public void relayToUser(Long userId, String destination, Map<String, Object> payload) {
        try {
            restTemplate.postForEntity(
                    chatsServiceUrl + "/internal/relay/to-user",
                    Map.of("userId", userId, "destination", destination, "payload", payload),
                    Void.class
            );
        } catch (Exception e) {
            log.warn("Failed to relay {} to user {}: {}", destination, userId, e.getMessage());
        }
    }
}
