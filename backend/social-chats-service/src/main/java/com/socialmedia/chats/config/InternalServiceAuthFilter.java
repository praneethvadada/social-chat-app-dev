package com.socialmedia.chats.config;

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
 * Phase 10 hardening: gates the service-to-service "internal" endpoint
 * (/internal/relay/**) that SecurityConfig deliberately keeps out of the
 * normal JWT/anyRequest().authenticated() flow — it's called by sibling
 * services (auth-service, social-service), not end-user clients. Mirrors
 * auth-service's InternalServiceAuthFilter exactly — see its own doc
 * comment for the full rationale (these paths were reachable from the
 * public internet through the gateway with zero gating).
 */
@Component
public class InternalServiceAuthFilter extends OncePerRequestFilter {

    private static final Logger log = LoggerFactory.getLogger(InternalServiceAuthFilter.class);
    private static final String HEADER = "X-Internal-Secret";

    private static final List<String> INTERNAL_PATH_PATTERNS = List.of(
            "/internal/relay/**"
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

    private boolean constantTimeEquals(String a, String b) {
        if (a == null || b == null) return false;
        return java.security.MessageDigest.isEqual(a.getBytes(java.nio.charset.StandardCharsets.UTF_8),
                b.getBytes(java.nio.charset.StandardCharsets.UTF_8));
    }
}
