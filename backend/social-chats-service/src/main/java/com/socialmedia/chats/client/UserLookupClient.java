package com.socialmedia.chats.client;

import com.socialmedia.chats.dto.UserSummary;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;

import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Reads user profile data from auth-service over REST.
 *
 * Chats-service does not own the users table, so display fields (username,
 * full name, avatar) are fetched here. A short-lived in-memory cache keeps a
 * conversation-list render from hammering auth-service for every partner.
 */
@Component
@Slf4j
public class UserLookupClient {

    private final RestTemplate restTemplate;
    private final String authServiceUrl;

    // Tiny best-effort cache: userId -> (summary, expiry). Not authoritative.
    private final Map<Long, Cached> cache = new ConcurrentHashMap<>();
    private static final long TTL_MS = 60_000; // 1 minute

    public UserLookupClient(RestTemplate restTemplate,
                            @Value("${auth.service.url:http://localhost:8081}") String authServiceUrl) {
        this.restTemplate = restTemplate;
        this.authServiceUrl = authServiceUrl;
    }

    /** Fetch one user summary, or null if unavailable. */
    public UserSummary getUser(Long userId) {
        if (userId == null) return null;

        Cached c = cache.get(userId);
        if (c != null && c.expiry > System.currentTimeMillis()) {
            return c.summary;
        }

        try {
            String url = authServiceUrl + "/users/" + userId + "/summary";
            UserSummary summary = restTemplate.getForObject(url, UserSummary.class);
            if (summary != null) {
                if (summary.getUserId() == null) summary.setUserId(userId);
                cache.put(userId, new Cached(summary, System.currentTimeMillis() + TTL_MS));
            }
            return summary;
        } catch (Exception e) {
            log.warn("[UserLookup] Failed to fetch user {}: {}", userId, e.getMessage());
            return null;
        }
    }

    /** Fetch many summaries in one call. Falls back to per-user on error. */
    @SuppressWarnings("unchecked")
    public List<UserSummary> getUsers(List<Long> userIds) {
        if (userIds == null || userIds.isEmpty()) return Collections.emptyList();
        try {
            String url = authServiceUrl + "/users/summaries";
            UserSummary[] result = restTemplate.postForObject(url, userIds, UserSummary[].class);
            if (result != null) {
                for (UserSummary s : result) {
                    if (s.getUserId() != null) {
                        cache.put(s.getUserId(), new Cached(s, System.currentTimeMillis() + TTL_MS));
                    }
                }
                return List.of(result);
            }
        } catch (Exception e) {
            log.warn("[UserLookup] Batch lookup failed ({} ids): {}", userIds.size(), e.getMessage());
        }
        // Fallback: fetch individually so a single bad id doesn't blank the list.
        return userIds.stream().map(this::getUser).filter(java.util.Objects::nonNull).toList();
    }

    private record Cached(UserSummary summary, long expiry) {}
}
