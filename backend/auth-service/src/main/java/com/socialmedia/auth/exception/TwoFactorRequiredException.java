package com.socialmedia.auth.exception;

import com.socialmedia.auth.dto.TwoFactorChallengeResponse;

/**
 * Thrown by AuthService.login() instead of returning normally when the
 * account has 2FA enabled — credentials were correct, but no session/device
 * exists yet and nothing is trusted until POST /login/2fa/verify also
 * succeeds. Caught explicitly in AuthController.login() and turned into the
 * challenge response body; deliberately NOT routed through
 * GlobalExceptionHandler's {errorCode, message} shape, since this isn't an
 * error — existing tests that exercise the ordinary (non-2FA) login path
 * never hit this branch and are unaffected by it.
 */
public class TwoFactorRequiredException extends RuntimeException {

    private final TwoFactorChallengeResponse challenge;

    public TwoFactorRequiredException(TwoFactorChallengeResponse challenge) {
        super("Two-factor authentication required");
        this.challenge = challenge;
    }

    public TwoFactorChallengeResponse getChallenge() {
        return challenge;
    }
}
