package com.socialmedia.social.config;

import com.socialmedia.social.security.JwtTokenProvider;
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

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {
        
        try {
            String jwt = getJwtFromRequest(request);
            System.out.println("[JWT FILTER] Request path: " + request.getRequestURI());
            System.out.println("[JWT FILTER] JWT token present: " + (jwt != null));
            
            if (StringUtils.hasText(jwt) && tokenProvider.validateToken(jwt)) {
                Long userId = tokenProvider.getUserIdFromToken(jwt);
                System.out.println("[JWT FILTER] Token valid, userId: " + userId);
                
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
