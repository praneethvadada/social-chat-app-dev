package com.socialmedia.auth.dto;

import jakarta.validation.constraints.NotBlank;

/** POST /login/2fa/resend body. */
public class TwoFactorLoginResendRequest {

    @NotBlank(message = "challengeToken is required")
    private String challengeToken;

    public String getChallengeToken() { return challengeToken; }
    public void setChallengeToken(String challengeToken) { this.challengeToken = challengeToken; }
}
