package com.socialmedia.chats.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.web.client.RestTemplateBuilder;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.client.RestTemplate;

import java.time.Duration;

/**
 * RestTemplate configuration for inter-service communication.
 *
 * Phase 10 hardening: this bean is confirmed used ONLY for internal
 * service-to-service calls in this service (UserLookupClient, FCMService,
 * SessionStatusClient, BlockClient — never a third-party/external API), so
 * it's safe to stamp every outgoing call with the shared internal-service
 * secret here rather than editing each client class individually. The
 * receiving side (auth-service's/social-service's own internal-path gates)
 * checks it.
 *
 * Timeouts added after a real 3+ minute hang was observed in testing
 * (social-service's FCMService's own outbound call to Firebase, not a
 * RestTemplate call, had no timeout at all — see auth-service's AsyncConfig
 * for the full story). This bean had no timeout either; a slow/unresponsive
 * internal service could otherwise hang a caller indefinitely.
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
