package com.socialmedia.chats.client;

import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestTemplate;

import java.util.Map;

/**
 * Checks block relationships via posts-service (which owns blocked_users).
 *
 * Fail-open policy: if the block service is unreachable we allow the action
 * rather than blocking legitimate messages/calls on a transient outage.
 */
@Component
@Slf4j
public class BlockClient {

    private final RestTemplate restTemplate;
    private final String socialServiceUrl;

    public BlockClient(RestTemplate restTemplate,
                       @Value("${social.service.url:http://localhost:8082}") String socialServiceUrl) {
        this.restTemplate = restTemplate;
        this.socialServiceUrl = socialServiceUrl;
    }

    /** True if either user has blocked the other. Fails open (false) on error. */
    @SuppressWarnings("unchecked")
    public boolean isEitherBlocked(Long userId1, Long userId2) {
        if (userId1 == null || userId2 == null) return false;
        try {
            String url = socialServiceUrl + "/blocks/internal/check-either?userId1=" + userId1 + "&userId2=" + userId2;
            Map<String, Object> body = restTemplate.getForObject(url, Map.class);
            if (body != null && Boolean.TRUE.equals(body.get("isBlocked"))) {
                return true;
            }
            return false;
        } catch (Exception e) {
            log.warn("[BlockClient] check-either failed for {}/{}: {} - failing open", userId1, userId2, e.getMessage());
            return false;
        }
    }
}
