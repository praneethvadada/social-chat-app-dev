package com.socialmedia.auth.config;

import com.socialmedia.auth.security.JwtTokenProvider;
import com.socialmedia.auth.service.DeviceSessionService;
import com.socialmedia.auth.service.DeviceSessionService.SessionCheckResult;
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
 *
 * Phase 1 addition: a valid, unexpired JWT is no longer sufficient on its
 * own — if it carries a "sid" claim, that session must still be ACTIVE in
 * user_sessions (a direct DB lookup, not Redis — see DeviceSessionService's
 * doc comment for why). This is what makes "log out this device" and a
 * future "session replaced" actually take effect on the device's very next
 * request, rather than only at the token's natural 24h expiry. A REVOKED
 * result is treated exactly like an invalid/expired token always was here:
 * the filter still doesn't reject the request itself, it just leaves the
 * SecurityContext unauthenticated, so anyRequest().authenticated() 401s any
 * protected route and permitAll routes proceed anonymously as before.
 */
@Component
public class JwtAuthenticationFilter extends OncePerRequestFilter {

    private final JwtTokenProvider tokenProvider;
    private final DeviceSessionService deviceSessionService;

    public JwtAuthenticationFilter(JwtTokenProvider tokenProvider, DeviceSessionService deviceSessionService) {
        this.tokenProvider = tokenProvider;
        this.deviceSessionService = deviceSessionService;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {
        try {
            String jwt = getJwtFromRequest(request);
            // Phase 7: a 2FA challenge token (generateTwoFactorChallengeToken)
            // has a valid signature and subject like any other token — without
            // this check it would authenticate here exactly like a real access
            // token, letting the OTP step be skipped entirely by just using the
            // challenge token as a Bearer token against any protected endpoint.
            // Post-Phase-10: the web-session-confirm challenge token
            // (generateWebSessionConfirmToken) is the exact same shape and
            // needs the exact same guard, for the exact same reason — see
            // isWebSessionConfirmToken's own doc comment.
            if (StringUtils.hasText(jwt) && tokenProvider.validateToken(jwt)
                    && !tokenProvider.isTwoFactorChallengeToken(jwt) && !tokenProvider.isWebSessionConfirmToken(jwt)) {
                String sessionToken = tokenProvider.getSessionIdFromToken(jwt);
                SessionCheckResult sessionCheck = deviceSessionService.checkAndTouch(sessionToken);

                if (sessionCheck != SessionCheckResult.REVOKED) {
                    Long userId = tokenProvider.getUserIdFromToken(jwt);
                    UsernamePasswordAuthenticationToken authentication = new UsernamePasswordAuthenticationToken(
                            userId, null, Collections.singletonList(new SimpleGrantedAuthority("ROLE_USER")));
                    SecurityContextHolder.getContext().setAuthentication(authentication);
                    request.setAttribute("userId", userId);
                    if (sessionToken != null) {
                        request.setAttribute("sid", sessionToken);
                    }
                    Long deviceId = tokenProvider.getDeviceIdFromToken(jwt);
                    if (deviceId != null) {
                        request.setAttribute("deviceId", deviceId);
                    }
                }
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
