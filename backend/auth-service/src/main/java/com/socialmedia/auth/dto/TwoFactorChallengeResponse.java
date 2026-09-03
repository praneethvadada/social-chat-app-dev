package com.socialmedia.auth.dto;

/**
 * Phase 7: what /login returns instead of the normal AuthResponse when the
 * account has 2FA enabled. No access/refresh token here — nothing is
 * trusted yet until POST /login/2fa/verify also succeeds.
 */
public class TwoFactorChallengeResponse {

    private final boolean twoFactorRequired = true;
    private String method; // "PHONE" | "EMAIL" — which channel the OTP was just sent to
    private String challengeToken;

    public TwoFactorChallengeResponse() {
    }

    public TwoFactorChallengeResponse(String method, String challengeToken) {
        this.method = method;
        this.challengeToken = challengeToken;
    }

    public boolean isTwoFactorRequired() { return twoFactorRequired; }

    public String getMethod() { return method; }
    public void setMethod(String method) { this.method = method; }

    public String getChallengeToken() { return challengeToken; }
    public void setChallengeToken(String challengeToken) { this.challengeToken = challengeToken; }
}
