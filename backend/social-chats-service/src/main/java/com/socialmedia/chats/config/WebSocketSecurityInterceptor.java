package com.socialmedia.chats.config;

import com.socialmedia.chats.client.SessionStatusClient;
import com.socialmedia.chats.security.JwtTokenProvider;
import org.springframework.messaging.Message;
import org.springframework.messaging.MessageChannel;
import org.springframework.messaging.simp.stomp.StompCommand;
import org.springframework.messaging.simp.stomp.StompHeaderAccessor;
import org.springframework.messaging.support.ChannelInterceptor;
import org.springframework.messaging.support.MessageHeaderAccessor;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.stereotype.Component;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import java.util.Collections;
import java.util.List;

@Component
@RequiredArgsConstructor
@Slf4j
public class WebSocketSecurityInterceptor implements ChannelInterceptor {

    private final JwtTokenProvider jwtTokenProvider;
    private final SessionStatusClient sessionStatusClient;

    @Override
    public Message<?> preSend(Message<?> message, MessageChannel channel) {
        StompHeaderAccessor accessor = MessageHeaderAccessor.getAccessor(message, StompHeaderAccessor.class);

        if (accessor == null) {
            return message;
        }

        if (StompCommand.CONNECT.equals(accessor.getCommand())) {
            try {
                System.out.println("\n[WebSocketSecurityInterceptor] ===== CONNECT FRAME RECEIVED =====");
                
                // Read the Authorization header from the STOMP CONNECT frame
                List<String> authHeaders = accessor.getNativeHeader("Authorization");
                System.out.println("[WebSocketSecurityInterceptor] 🔍 authHeaders from getNativeHeader: " + (authHeaders != null ? "Found " + authHeaders.size() + " headers" : "NULL"));
                
                // Try alternative: check all native headers
                if (authHeaders == null || authHeaders.isEmpty()) {
                    System.out.println("[WebSocketSecurityInterceptor] ⚠️ Authorization header not in nativeHeader, checking alternatives...");
                    java.util.Map<String, java.util.List<String>> allHeaders = accessor.toNativeHeaderMap();
                    System.out.println("[WebSocketSecurityInterceptor] 📊 All native headers: " + allHeaders.keySet());
                    if (allHeaders.containsKey("authorization")) {
                        authHeaders = allHeaders.get("authorization");
                        System.out.println("[WebSocketSecurityInterceptor] ✅ Found 'authorization' (lowercase): " + authHeaders);
                    }
                }
                
                String token = null;

                if (authHeaders != null && !authHeaders.isEmpty()) {
                    String authHeader = authHeaders.get(0);
                    System.out.println("[WebSocketSecurityInterceptor] 📝 AuthHeader value (first 30 chars): " + authHeader.substring(0, Math.min(30, authHeader.length())) + "...");
                    if (authHeader.startsWith("Bearer ")) {
                        token = authHeader.substring(7);
                        System.out.println("[WebSocketSecurityInterceptor] ✅ Token extracted successfully");
                    } else {
                        System.out.println("[WebSocketSecurityInterceptor] ❌ AuthHeader does NOT start with 'Bearer '");
                    }
                } else {
                    System.out.println("[WebSocketSecurityInterceptor] ❌ authHeaders is NULL or EMPTY!");
                }

                if (token != null && jwtTokenProvider.validateToken(token)
                        && !jwtTokenProvider.isTwoFactorChallengeToken(token) && !jwtTokenProvider.isWebSessionConfirmToken(token)) {
                    Long userId = jwtTokenProvider.getUserIdFromToken(token);
                    String sessionToken = jwtTokenProvider.getSessionIdFromToken(token);
                    System.out.println("[WebSocketSecurityInterceptor] ✅ Token validated, userId: " + userId);

                    // Phase 5: refuse the handshake outright for an already-revoked
                    // session (single-active-web-session takeover, remote device
                    // logout) — no point completing a connection that every
                    // subsequent frame would then reject anyway.
                    if (sessionToken != null && !sessionStatusClient.isActive(sessionToken)) {
                        System.out.println("[WebSocketSecurityInterceptor] ❌ Session revoked, refusing CONNECT: " + sessionToken);
                        log.warn("[WS] CONNECT refused — session revoked, sid={}", sessionToken);
                        throw new org.springframework.messaging.MessagingException("Session revoked");
                    }

                    if (userId != null) {
                        // Store userId + sid in session attributes
                        accessor.getSessionAttributes().put("userId", userId);
                        if (sessionToken != null) {
                            accessor.getSessionAttributes().put("sid", sessionToken);
                        }

                        // Set a Principal so convertAndSendToUser routes reliably
                        UsernamePasswordAuthenticationToken principal =
                                new UsernamePasswordAuthenticationToken(userId.toString(), null, Collections.emptyList());
                        accessor.setUser(principal);

                        System.out.println("[WebSocketSecurityInterceptor] ✅ SESSION SETUP COMPLETE");
                        System.out.println("[WebSocketSecurityInterceptor]    ├─ userId stored: " + userId);
                        System.out.println("[WebSocketSecurityInterceptor]    ├─ principal name: " + principal.getName());
                        System.out.println("[WebSocketSecurityInterceptor]    └─ Session attributes: " + accessor.getSessionAttributes());
                        log.info("[WS] CONNECT userId={} principal set", userId);
                    } else {
                        System.out.println("[WebSocketSecurityInterceptor] ❌ Token valid but userId extraction failed");
                        log.warn("[WS] Token valid but userId not found");
                    }
                } else {
                    System.out.println("[WebSocketSecurityInterceptor] ❌ Token validation FAILED");
                    System.out.println("[WebSocketSecurityInterceptor]    ├─ token is null: " + (token == null));
                    if (token != null) {
                        System.out.println("[WebSocketSecurityInterceptor]    └─ validateToken returned: false");
                    }
                    log.warn("[WS] No/invalid token found in connection headers");
                }
                System.out.println("[WebSocketSecurityInterceptor] ===== END CONNECT FRAME =====\n");
            } catch (org.springframework.messaging.MessagingException e) {
                throw e; // propagate deliberate CONNECT refusal — do not swallow it below
            } catch (Exception e) {
                System.out.println("[WebSocketSecurityInterceptor] ❌ EXCEPTION in CONNECT processing: " + e.getMessage());
                e.printStackTrace();
                log.error("[WS] Error processing CONNECT", e);
            }
        } else if (accessor.getSessionAttributes() != null) {
            // Phase 5: every frame after CONNECT (SEND, SUBSCRIBE, heartbeats via
            // the broker relay, etc.) is re-checked against the session that was
            // active at connect time — cheap thanks to SessionStatusClient's TTL
            // cache, and this is what makes a mid-session revocation (someone
            // logs into a new browser right now) take effect within seconds
            // instead of only on the next reconnect.
            Object sid = accessor.getSessionAttributes().get("sid");
            if (sid instanceof String sessionToken && !sessionStatusClient.isActive(sessionToken)) {
                System.out.println("[WebSocketSecurityInterceptor] ❌ Session revoked mid-connection, rejecting frame: " + sessionToken);
                log.warn("[WS] Frame rejected — session revoked, sid={}", sessionToken);
                throw new org.springframework.messaging.MessagingException("Session revoked");
            }
        }

        return message;
    }
}
