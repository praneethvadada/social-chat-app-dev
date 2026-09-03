package com.socialmedia.chats.config;

import com.socialmedia.chats.client.SessionStatusClient;
import com.socialmedia.chats.security.JwtTokenProvider;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.Collections;

@Component
@RequiredArgsConstructor
public class JwtAuthenticationFilter extends OncePerRequestFilter {

    private final JwtTokenProvider tokenProvider;
    private final SessionStatusClient sessionStatusClient;

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {
        
        try {
            String jwt = getJwtFromRequest(request);
            System.out.println("[JWT FILTER] Request path: " + request.getRequestURI());
            System.out.println("[JWT FILTER] JWT token present: " + (jwt != null));
            
            if (StringUtils.hasText(jwt) && tokenProvider.validateToken(jwt)
                    && !tokenProvider.isTwoFactorChallengeToken(jwt) && !tokenProvider.isWebSessionConfirmToken(jwt)) {
                Long userId = tokenProvider.getUserIdFromToken(jwt);
                String sessionToken = tokenProvider.getSessionIdFromToken(jwt);
                System.out.println("[JWT FILTER] Token valid, userId: " + userId);

                // Phase 5: a session revoked at auth-service (single-active-web-
                // session takeover, remote device logout) must stop working here
                // too, not just there — see SessionStatusClient's own doc comment.
                if (sessionToken != null && !sessionStatusClient.isActive(sessionToken)) {
                    System.out.println("[JWT FILTER] Session revoked, refusing to authenticate: " + sessionToken);
                    filterChain.doFilter(request, response);
                    return;
                }

                UsernamePasswordAuthenticationToken authentication =
                    new UsernamePasswordAuthenticationToken(userId, null,
                        Collections.singletonList(new SimpleGrantedAuthority("ROLE_USER")));

                SecurityContextHolder.getContext().setAuthentication(authentication);

                request.setAttribute("userId", userId);
                System.out.println("[JWT FILTER] Authentication set for userId: " + userId);
            } else {
                System.out.println("[JWT FILTER] Token validation failed. JWT present: " + StringUtils.hasText(jwt));
                if (StringUtils.hasText(jwt)) {
                    System.out.println("[JWT FILTER] Token validation result: " + tokenProvider.validateToken(jwt));
                }
            }
        } catch (Exception ex) {
            logger.error("Could not set user authentication in security context", ex);
            System.out.println("[JWT FILTER] Exception: " + ex.getMessage());
            ex.printStackTrace();
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
