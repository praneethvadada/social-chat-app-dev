package com.socialmedia.auth.security;

import io.jsonwebtoken.*;
import io.jsonwebtoken.security.Keys;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.util.Date;
import java.util.HashMap;
import java.util.Map;

@Component
public class JwtTokenProvider {

    @Value("${jwt.secret}")
    private String jwtSecret;

    @Value("${jwt.expiration}")
    private long jwtExpirationMs;

    @Value("${jwt.refresh-expiration}")
    private long jwtRefreshExpirationMs;

    private SecretKey getSigningKey() {
        return Keys.hmacShaKeyFor(jwtSecret.getBytes(StandardCharsets.UTF_8));
    }

    // sessionToken/deviceId are nullable — a legacy/device-info-less caller
    // (e.g. an existing test, or a not-yet-updated client) gets a token
    // without a "sid" claim, which JwtAuthenticationFilter treats as an
    // untracked, implicitly-trusted legacy session rather than rejecting it.
    public String generateAccessToken(Long userId, String email, String sessionToken, Long deviceId) {
        return generateToken(userId, email, sessionToken, deviceId, jwtExpirationMs);
    }

    public String generateRefreshToken(Long userId, String email, String sessionToken, Long deviceId) {
        return generateToken(userId, email, sessionToken, deviceId, jwtRefreshExpirationMs);
    }

    private String generateToken(Long userId, String email, String sessionToken, Long deviceId, long expirationTime) {
        Date now = new Date();
        Date expiryDate = new Date(now.getTime() + expirationTime);

        Map<String, Object> claims = new HashMap<>();
        claims.put("userId", userId);
        claims.put("email", email);
        if (sessionToken != null) {
            claims.put("sid", sessionToken);
        }
        if (deviceId != null) {
            claims.put("deviceId", deviceId);
        }

        return Jwts.builder()
                .subject(String.valueOf(userId))
                .claims(claims)
                .issuedAt(now)
                .expiration(expiryDate)
                .signWith(getSigningKey())
                .compact();
    }

    // Phase 7: a short-lived, purpose-tagged token proving "this device just
    // passed the password check for this user" — issued instead of real
    // access/refresh tokens when 2FA is enabled, so no session/device row
    // exists yet and nothing is trusted until the OTP challenge also
    // passes. Deliberately NOT reused from generateAccessToken (no sid/
    // deviceId claims, much shorter TTL, and the "purpose" claim stops it
    // from being accepted anywhere a real access token is expected).
    private static final long TWO_FACTOR_CHALLENGE_EXPIRATION_MS = 5 * 60 * 1000;
    private static final String TWO_FACTOR_CHALLENGE_PURPOSE = "2fa_challenge";
    private static final long WEB_SESSION_CONFIRM_EXPIRATION_MS = 5 * 60 * 1000;
    private static final String WEB_SESSION_CONFIRM_PURPOSE = "web_session_confirm";

    public String generateTwoFactorChallengeToken(Long userId) {
        Date now = new Date();
        Date expiryDate = new Date(now.getTime() + TWO_FACTOR_CHALLENGE_EXPIRATION_MS);
        return Jwts.builder()
                .subject(String.valueOf(userId))
                .claim("purpose", TWO_FACTOR_CHALLENGE_PURPOSE)
                .issuedAt(now)
                .expiration(expiryDate)
                .signWith(getSigningKey())
                .compact();
    }

    /** True only for a token from generateTwoFactorChallengeToken - guards against a real access/refresh token being replayed here instead. */
    public boolean isTwoFactorChallengeToken(String token) {
        try {
            Claims claims = Jwts.parser().verifyWith(getSigningKey()).build().parseSignedClaims(token).getPayload();
            return TWO_FACTOR_CHALLENGE_PURPOSE.equals(claims.get("purpose", String.class));
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * Confirm-before-kick web-session-takeover challenge (post-Phase-10 UX
     * change): logging in on a WEB device while the account is already
     * active on a DIFFERENT web device now pauses with this token instead
     * of silently kicking the old session (see AuthService.finishLogin's
     * own doc comment). Same shape/TTL as the 2FA challenge token, and MUST
     * be rejected as a real Bearer token the exact same way — see
     * isWebSessionConfirmToken's own doc comment.
     */
    public String generateWebSessionConfirmToken(Long userId) {
        Date now = new Date();
        Date expiryDate = new Date(now.getTime() + WEB_SESSION_CONFIRM_EXPIRATION_MS);
        return Jwts.builder()
                .subject(String.valueOf(userId))
                .claim("purpose", WEB_SESSION_CONFIRM_PURPOSE)
                .issuedAt(now)
                .expiration(expiryDate)
                .signWith(getSigningKey())
                .compact();
    }

    /**
     * True only for a token from generateWebSessionConfirmToken. Critical:
     * without this guard being wired into every JwtAuthenticationFilter
     * (see AuthService/SecurityConfig), this token — a validly-signed JWT
     * with a real userId subject claim — could authenticate as a normal
     * Bearer token against ANY endpoint, completely bypassing the
     * confirm-before-kick step. This is the exact same bug class Phase 7
     * found and fixed for the 2FA challenge token; mirrored here.
     */
    public boolean isWebSessionConfirmToken(String token) {
        try {
            Claims claims = Jwts.parser().verifyWith(getSigningKey()).build().parseSignedClaims(token).getPayload();
            return WEB_SESSION_CONFIRM_PURPOSE.equals(claims.get("purpose", String.class));
        } catch (Exception e) {
            return false;
        }
    }

    public Long getUserIdFromToken(String token) {
        Claims claims = Jwts.parser()
                .verifyWith(getSigningKey())
                .build()
                .parseSignedClaims(token)
                .getPayload();

        return Long.parseLong(claims.getSubject());
    }

    /** Null if the token predates session tracking (no "sid" claim). */
    public String getSessionIdFromToken(String token) {
        Claims claims = Jwts.parser()
                .verifyWith(getSigningKey())
                .build()
                .parseSignedClaims(token)
                .getPayload();
        return claims.get("sid", String.class);
    }

    /** Null if the token predates device tracking (no "deviceId" claim). */
    public Long getDeviceIdFromToken(String token) {
        Claims claims = Jwts.parser()
                .verifyWith(getSigningKey())
                .build()
                .parseSignedClaims(token)
                .getPayload();
        Number deviceId = claims.get("deviceId", Number.class);
        return deviceId == null ? null : deviceId.longValue();
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
