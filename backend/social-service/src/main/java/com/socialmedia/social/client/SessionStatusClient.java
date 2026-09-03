package com.socialmedia.social.client;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Phase 5 (closing a gap found after the chats-service rollout): asks
 * auth-service whether a session (the JWT's "sid" claim) is still ACTIVE,
 * so a session revoked there (single-active-web-session takeover, remote
 * device logout) actually stops working here too - previously social-
 * service had no revocation check at all, so a revoked session could still
 * browse profiles/posts until its JWT naturally expired, even though chats
 * (Phase 5) and auth (Phase 1) already enforced it. Identical shape to
 * chats-service's own SessionStatusClient: short-lived in-memory cache,
 * fail-open on error (an auth-service blip must not lock every user out).
 */
@Component
@Slf4j
public class SessionStatusClient {

    private final RestTemplate restTemplate;
    private final String authServiceUrl;

    private final Map<String, Cached> cache = new ConcurrentHashMap<>();
    private static final long TTL_MS = 15_000;

    public SessionStatusClient(RestTemplate restTemplate,
                                @Value("${auth.service.url:http://localhost:8081}") String authServiceUrl) {
        this.restTemplate = restTemplate;
        this.authServiceUrl = authServiceUrl;
    }

    /**
     * False ONLY when auth-service explicitly says REVOKED - a null/absent
     * sid, an unreachable auth-service, or NOT_TRACKED (legacy token) all
     * resolve to "active" (fail open), matching Phase 1's own treatment of
     * untracked sessions as implicitly trusted.
     */
    public boolean isActive(String sessionToken) {
        if (sessionToken == null || sessionToken.isBlank()) {
            return true;
        }

        Cached c = cache.get(sessionToken);
        if (c != null && c.expiry > System.currentTimeMillis()) {
            return c.active;
        }

        try {
            String url = authServiceUrl + "/internal/sessions/" + sessionToken + "/status";
            @SuppressWarnings("unchecked")
            Map<String, String> body = restTemplate.getForObject(url, Map.class);
            boolean active = body == null || !"REVOKED".equals(body.get("status"));
            cache.put(sessionToken, new Cached(active, System.currentTimeMillis() + TTL_MS));
            return active;
        } catch (Exception e) {
            log.warn("[SessionStatus] Failed to check session {}: {}", sessionToken, e.getMessage());
            return true;
        }
    }

    private record Cached(boolean active, long expiry) {}
}
