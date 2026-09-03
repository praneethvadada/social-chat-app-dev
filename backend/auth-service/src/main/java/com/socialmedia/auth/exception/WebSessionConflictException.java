package com.socialmedia.auth.exception;

import com.socialmedia.auth.dto.WebSessionConflictResponse;

/**
 * Thrown by AuthService.finishLogin() instead of proceeding normally when a
 * WEB login would take over the account's single active web session from a
 * DIFFERENT device — mirrors TwoFactorRequiredException exactly (same
 * "not an error, a pause" reasoning, same caught-explicitly-in-
 * AuthController-not-GlobalExceptionHandler treatment). Post-Phase-10 UX
 * change: previously ActiveWebSessionService.claimOrReplace() ran
 * automatically and silently on every WEB login, immediately revoking
 * whichever device held the session before — now it only runs after this
 * exception's challenge is explicitly confirmed via
 * POST /login/web-session/confirm.
 */
public class WebSessionConflictException extends RuntimeException {

    private final WebSessionConflictResponse conflict;

    public WebSessionConflictException(WebSessionConflictResponse conflict) {
        super("Account is already active on another web device");
        this.conflict = conflict;
    }

    public WebSessionConflictResponse getConflict() {
        return conflict;
    }
}
