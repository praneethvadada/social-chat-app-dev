package com.socialmedia.chats.security;

import io.jsonwebtoken.*;
import io.jsonwebtoken.security.Keys;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;

@Component
public class JwtTokenProvider {

    @Value("${jwt.secret}")
    private String jwtSecret;

    private SecretKey getSigningKey() {
        return Keys.hmacShaKeyFor(jwtSecret.getBytes(StandardCharsets.UTF_8));
    }

    public Long getUserIdFromToken(String token) {
        Claims claims = Jwts.parser()
                .verifyWith(getSigningKey())
                .build()
                .parseSignedClaims(token)
                .getPayload();

        return Long.parseLong(claims.getSubject());
    }

    /**
     * Phase 7: true for a 2FA login-challenge token (auth-service's
     * generateTwoFactorChallengeToken) - these carry a valid signature and
     * subject like any real token, so without this check one could
     * authenticate here exactly like a real access token, letting the OTP
     * step be skipped by using the challenge token as a Bearer token
     * against this service directly instead of only against
     * /login/2fa/verify.
     */
    public boolean isTwoFactorChallengeToken(String token) {
        try {
            Claims claims = Jwts.parser().verifyWith(getSigningKey()).build().parseSignedClaims(token).getPayload();
            return "2fa_challenge".equals(claims.get("purpose", String.class));
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * Post-Phase-10: true for a web-session-confirm challenge token
     * (auth-service's generateWebSessionConfirmToken) - same shape/risk as
     * the 2FA challenge token above, same guard needed for the same reason.
     */
    public boolean isWebSessionConfirmToken(String token) {
        try {
            Claims claims = Jwts.parser().verifyWith(getSigningKey()).build().parseSignedClaims(token).getPayload();
            return "web_session_confirm".equals(claims.get("purpose", String.class));
        } catch (Exception e) {
            return false;
        }
    }

    /** Phase 5: null if the token predates session tracking (no "sid" claim) - mirrors auth-service's own extraction. */
    public String getSessionIdFromToken(String token) {
        Claims claims = Jwts.parser()
                .verifyWith(getSigningKey())
                .build()
                .parseSignedClaims(token)
                .getPayload();

        return claims.get("sid", String.class);
    }

    public boolean validateToken(String token) {
        try {
            Jwts.parser()
                .verifyWith(getSigningKey())
                .build()
                .parseSignedClaims(token);
            return true;
        } catch (MalformedJwtException ex) {
            System.err.println("Invalid JWT token");
        } catch (ExpiredJwtException ex) {
            System.err.println("Expired JWT token");
        } catch (UnsupportedJwtException ex) {
            System.err.println("Unsupported JWT token");
        } catch (IllegalArgumentException ex) {
            System.err.println("JWT claims string is empty");
        }
        return false;
    }
}
