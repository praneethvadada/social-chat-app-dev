package com.socialmedia.gateway.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.cloud.gateway.route.RouteLocator;
import org.springframework.cloud.gateway.route.builder.RouteLocatorBuilder;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class GatewayConfig {

    @Value("${AUTH_SERVICE_URL:http://localhost:8081}")
    private String authServiceUrl;

    @Value("${SOCIAL_SERVICE_URL:http://localhost:8082}")
    private String socialServiceUrl;

    // NEW: dedicated chats/calls/presence service (split out of social-service).
    @Value("${CHATS_SERVICE_URL:http://localhost:8083}")
    private String chatsServiceUrl;

    @Bean
    public RouteLocator customRouteLocator(RouteLocatorBuilder builder) {
        return builder.routes()
            // Phone/email sub-controllers are mapped at "/auth/phone/**" and
            // "/auth/email/**" on auth-service (matching SecurityConfig's permitAll
            // patterns), unlike AuthController which is root-mapped ("/register",
            // "/login", ...). So these need stripPrefix(1) (keep "/auth/..."),
            // while the general route below needs stripPrefix(2) (drop "/auth"
            // too). Must be declared BEFORE the general /api/auth/** route, same
            // pattern as the chats-messages/chats-conversations routes below.
            .route("auth-service-phone", r -> r
                .path("/api/auth/phone/**")
                .filters(f -> f
                    .stripPrefix(1)
                    .addRequestHeader("X-Gateway-Source", "api-gateway")
                    .retry(config -> config.setRetries(3)))
                .uri(authServiceUrl))

            .route("auth-service-email-link", r -> r
                .path("/api/auth/email/**")
                .filters(f -> f
                    .stripPrefix(1)
                    .addRequestHeader("X-Gateway-Source", "api-gateway")
                    .retry(config -> config.setRetries(3)))
                .uri(authServiceUrl))

            .route("auth-service", r -> r
                .path("/api/auth/**")
                .filters(f -> f
                    .stripPrefix(2)
                    .addRequestHeader("X-Gateway-Source", "api-gateway")
                    .retry(config -> config.setRetries(3)))
                .uri(authServiceUrl))

            // Chat messages -> chats-service. MUST be declared BEFORE the general
            // /api/social/** route, otherwise that broader pattern would swallow it.
            // stripPrefix(2) turns /api/social/messages/** into /messages/**.
            .route("chats-messages", r -> r
                .path("/api/social/messages/**")
                .filters(f -> f
                    .stripPrefix(2)
                    .addRequestHeader("X-Gateway-Source", "api-gateway")
                    .retry(config -> config.setRetries(3)))
                .uri(chatsServiceUrl))

            // G1: group conversations -> chats-service. Also more specific than
            // /api/social/**, so it must be declared before it.
            .route("chats-conversations", r -> r
                .path("/api/social/conversations/**")
                .filters(f -> f
                    .stripPrefix(2)
                    .addRequestHeader("X-Gateway-Source", "api-gateway")
                    .retry(config -> config.setRetries(3)))
                .uri(chatsServiceUrl))

            .route("social-service", r -> r
                .path("/api/social/**")
                .filters(f -> f
                    .stripPrefix(2)
                    .addRequestHeader("X-Gateway-Source", "api-gateway")
                    .retry(config -> config.setRetries(3)))
                .uri(socialServiceUrl))

            // WebSocket (STOMP chat/calls/presence/typing) -> chats-service.
            // NOTE: the mobile app currently connects directly to the chats host:port,
            // bypassing the gateway; this route covers any gateway-routed WS clients.
            .route("websocket-service", r -> r
                .path("/ws/**")
                .uri(chatsServiceUrl))

            // Call REST (Agora token, call history, accept/reject) -> chats-service.
            // stripPrefix(1) turns /api/calls/** into /calls/**.
            .route("calls", r -> r
                .path("/api/calls/**")
                .filters(f -> f
                    .stripPrefix(1)
                    .addRequestHeader("X-Gateway-Source", "api-gateway")
                    .retry(config -> config.setRetries(3)))
                .uri(chatsServiceUrl))

            .build();
    }
}
