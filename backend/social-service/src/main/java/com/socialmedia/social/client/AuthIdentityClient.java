package com.socialmedia.social.client;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestTemplate;

import java.util.HashMap;
import java.util.Map;

/**
 * Writes identity fields (username, full name) back to auth-service, which owns
 * auth_db.users.
 *
 * social-service keeps a replica of these fields in user_profiles for fast
 * reads/JOINs, but must never be the one to *decide* them - otherwise the two
 * databases could disagree about who owns a username.
 */
@Component
@Slf4j
public class AuthIdentityClient {

    private final RestTemplate restTemplate;
    private final String authServiceUrl;

    public AuthIdentityClient(RestTemplate restTemplate,
                              @Value("${auth.service.url:http://localhost:8081}") String authServiceUrl) {
        this.restTemplate = restTemplate;
        this.authServiceUrl = authServiceUrl;
    }

    /** Thrown when auth-service rejects the change (e.g. username taken). */
    public static class IdentityRejectedException extends RuntimeException {
        public IdentityRejectedException(String message) { super(message); }
    }

    /** Read the authoritative identity for one user (used by reconcile). */
    @SuppressWarnings("unchecked")
    public Map<String, Object> fetchIdentity(Long userId) {
        try {
            Map<String, Object> result = restTemplate.getForObject(
                    authServiceUrl + "/users/" + userId + "/summary", Map.class);
            return result == null ? Map.of() : result;
        } catch (Exception e) {
            log.warn("[AuthIdentity] Could not fetch identity for {}: {}", userId, e.getMessage());
            return Map.of();
        }
    }

    /**
     * Push identity changes upstream. Returns the authoritative values so the
     * caller can refresh its replica with exactly what auth stored.
     */
    @SuppressWarnings("unchecked")
    public Map<String, Object> updateIdentity(Long userId, String username, String fullName) {
        if (username == null && fullName == null) return Map.of();

        Map<String, String> body = new HashMap<>();
        if (username != null) body.put("username", username);
        if (fullName != null) body.put("fullName", fullName);

        try {
            Map<String, Object> result = restTemplate.exchange(
                    authServiceUrl + "/users/" + userId + "/identity",
                    org.springframework.http.HttpMethod.PUT,
                    new org.springframework.http.HttpEntity<>(body),
                    Map.class).getBody();
            return result == null ? Map.of() : result;
        } catch (HttpClientErrorException.Conflict e) {
            // Surface the real reason - a taken username must not look like a crash.
            throw new IdentityRejectedException("Username already taken");
        } catch (Exception e) {
            log.error("[AuthIdentity] Failed to update identity for {}: {}", userId, e.getMessage());
            throw new IdentityRejectedException("Could not update profile right now");
        }
    }
}
