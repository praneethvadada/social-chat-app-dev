package com.socialmedia.auth.config;

import feign.RequestInterceptor;
import feign.RequestTemplate;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;

import jakarta.servlet.http.HttpServletRequest;

/**
 * Feign client configuration to add JWT token to inter-service calls
 */
@Configuration
public class FeignConfig implements RequestInterceptor {

    @Override
    public void apply(RequestTemplate template) {
        // 🔴 FIX: Extract JWT from the current HTTP request and forward it to Feign calls
        try {
            ServletRequestAttributes attrs = (ServletRequestAttributes) RequestContextHolder.getRequestAttributes();
            if (attrs != null) {
                HttpServletRequest request = attrs.getRequest();
                String authHeader = request.getHeader("Authorization");
                
                // If Authorization header exists, add it to the Feign request
                if (authHeader != null && !authHeader.isEmpty()) {
                    template.header("Authorization", authHeader);
                }
            }
        } catch (Exception e) {
            // If no request context available (shouldn't happen in normal flow), continue without token
            // This is expected for async or background processes
        }
    }
}
