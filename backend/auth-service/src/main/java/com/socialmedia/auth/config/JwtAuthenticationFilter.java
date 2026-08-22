package com.socialmedia.auth.config;

import com.socialmedia.auth.security.JwtTokenProvider;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.Collections;

/**
 * auth-service had no JWT-authenticating filter at all before this feature
 * (every existing endpoint is permitAll — other services validate JWTs
 * themselves for their own routes). The new "link a secondary identifier to
 * my account" endpoints (PhoneAuthController's PHONE_VERIFICATION purpose,
 * /auth/email/link) need to know who the calling user is, so this mirrors
 * social-chats-service's JwtAuthenticationFilter using auth-service's own
 * JwtTokenProvider. It optionally authenticates: it never rejects a
 * request itself (paths stay in SecurityConfig's permitAll list so the
 * unauthenticated PHONE_SIGNUP variant of the same endpoints keeps
 * working) — controllers check for a populated "userId" request attribute
 * themselves where authentication is actually required.
 */
@Component
public class JwtAuthenticationFilter extends OncePerRequestFilter {

    private final JwtTokenProvider tokenProvider;

    public JwtAuthenticationFilter(JwtTokenProvider tokenProvider) {
        this.tokenProvider = tokenProvider;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {
        try {
            String jwt = getJwtFromRequest(request);
            if (StringUtils.hasText(jwt) && tokenProvider.validateToken(jwt)) {
                Long userId = tokenProvider.getUserIdFromToken(jwt);
                UsernamePasswordAuthenticationToken authentication = new UsernamePasswordAuthenticationToken(
                        userId, null, Collections.singletonList(new SimpleGrantedAuthority("ROLE_USER")));
                SecurityContextHolder.getContext().setAuthentication(authentication);
                request.setAttribute("userId", userId);
            }
        } catch (Exception ex) {
            logger.warn("Could not set user authentication from JWT: " + ex.getMessage());
        }
        filterChain.doFilter(request, response);
    }

    private String getJwtFromRequest(HttpServletRequest request) {
        String bearerToken = request.getHeader("Authorization");
        if (StringUtils.hasText(bearerToken) && bearerToken.startsWith("Bearer ")) {
            return bearerToken.substring(7);
        }
        return null;
    }
}
