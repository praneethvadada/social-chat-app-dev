package com.socialmedia.auth.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.web.client.RestTemplateBuilder;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.RestTemplate;

import java.time.Duration;

/**
 * RestTemplate configuration for inter-service communication (mirrors
 * social-chats-service's own). Phase 10 hardening: this bean is confirmed
 * used ONLY for internal service-to-service calls in this service
 * (ChatsServiceRelayClient, SecurityPushRelayClient) — never a third-party/
 * external API — so it's safe to stamp every outgoing call with the shared
 * internal-service secret here, rather than editing each client class
 * individually. The receiving side (chats-service's/social-service's own
 * "/internal/**" gates) checks it.
 *
 * Timeouts added after a real 3+ minute hang was observed in testing (a
 * downstream service's own outbound call — to Firebase, not to this
 * RestTemplate — hung with no timeout at all; see AsyncConfig's doc
 * comment for the full story). This RestTemplate itself had no timeout
 * either — a genuinely slow/unresponsive internal service could otherwise
 * hang a caller indefinitely with no bound. These calls are all
 * best-effort relays already wrapped in try/catch by their callers
 * (ChatsServiceRelayClient, SecurityPushRelayClient), so failing fast on a
 * timeout is strictly better than hanging — the caller already treats
 * "failed" and "never happened" identically.
 */
@Configuration
public class RestTemplateConfig {

    @Value("${internal.service.secret}")
    private String internalServiceSecret;

    @Bean
    public RestTemplate restTemplate(RestTemplateBuilder builder) {
        return builder
                .setConnectTimeout(Duration.ofSeconds(5))
                .setReadTimeout(Duration.ofSeconds(10))
                .additionalInterceptors((request, body, execution) -> {
                    request.getHeaders().add("X-Internal-Secret", internalServiceSecret);
                    return execution.execute(request, body);
                })
                .build();
    }
}
