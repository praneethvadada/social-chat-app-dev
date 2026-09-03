package com.socialmedia.auth.config;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import org.springframework.util.AntPathMatcher;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.List;

/**
 * Phase 10 hardening: gates the service-to-service "internal" endpoints
 * (/users/**, /internal/sessions/**) that SecurityConfig deliberately keeps
 * out of the normal JWT/anyRequest().authenticated() flow — they're called
 * by sibling services (social-service, chats-service), not end-user
 * clients, so there's no user Bearer token to check.
 *
 * Before this: those paths were plain permitAll with NOTHING distinguishing
 * "a real internal caller" from "anyone who found the URL" — and they ARE
 * reachable from the public internet, not just inside the deployment
 * network: GatewayConfig proxies /api/auth/** straight through with
 * stripPrefix(2), no gating in between. Worst case was PUT
 * /users/{userId}/identity letting anyone rewrite any account's
 * username/fullName with zero authentication — same severity class as the
 * account-deletion bug fixed earlier this phase, but needing even less
 * (no password, no OTP, nothing).
 *
 * Runs BEFORE JwtAuthenticationFilter (see SecurityConfig) and, for a
 * matched internal path, requires X-Internal-Secret to match
 * internal.service.secret — a shared value across auth-service,
 * social-service, and social-chats-service, the same convention already
 * used for jwt.secret. RestTemplateConfig in each of those services stamps
 * this header on every outgoing call automatically (their shared
 * RestTemplate bean is confirmed used exclusively for internal
 * service-to-service calls), so no individual client class needed
 * changing.
 */
@Component
public class InternalServiceAuthFilter extends OncePerRequestFilter {

    private static final Logger log = LoggerFactory.getLogger(InternalServiceAuthFilter.class);
    private static final String HEADER = "X-Internal-Secret";

    private static final List<String> INTERNAL_PATH_PATTERNS = List.of(
            "/users/**",
            "/internal/sessions/**"
    );

    private final AntPathMatcher pathMatcher = new AntPathMatcher();

    @Value("${internal.service.secret}")
    private String expectedSecret;

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {
        String path = request.getRequestURI();
        boolean isInternalPath = INTERNAL_PATH_PATTERNS.stream().anyMatch(pattern -> pathMatcher.match(pattern, path));

        if (!isInternalPath) {
            filterChain.doFilter(request, response);
            return;
        }

        String provided = request.getHeader(HEADER);
        if (provided == null || !constantTimeEquals(provided, expectedSecret)) {
            log.warn("[InternalServiceAuth] Rejected unauthorized call to internal path {} from {}", path, request.getRemoteAddr());
            response.sendError(HttpServletResponse.SC_FORBIDDEN, "Forbidden");
            return;
        }

        filterChain.doFilter(request, response);
    }

    /** Avoids leaking secret-length/content via response-timing differences on a plain String.equals(). */
    private boolean constantTimeEquals(String a, String b) {
        if (a == null || b == null) return false;
        return java.security.MessageDigest.isEqual(a.getBytes(java.nio.charset.StandardCharsets.UTF_8),
                b.getBytes(java.nio.charset.StandardCharsets.UTF_8));
    }
}
