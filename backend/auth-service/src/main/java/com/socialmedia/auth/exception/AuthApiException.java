package com.socialmedia.auth.exception;

import org.springframework.http.HttpStatus;

/**
 * Standardized error type for the new phone/email-verification code paths.
 * Carries an explicit machine-readable error code (see section 33 of the
 * feature spec) alongside a human-readable message and the HTTP status to
 * respond with. Existing register()/login() error paths (duplicate
 * username, invalid credentials) keep their pre-existing ad-hoc
 * RuntimeException-message-matching behavior — this type is only used by
 * new code, not retrofitted onto old call sites.
 */
public class AuthApiException extends RuntimeException {

    public enum ErrorCode {
        INVALID_PHONE_NUMBER,
        INVALID_EMAIL,
        PHONE_ALREADY_EXISTS,
        EMAIL_ALREADY_EXISTS,
        PHONE_NOT_VERIFIED,
        EMAIL_NOT_VERIFIED,
        OTP_EXPIRED,
        OTP_INVALID,
        OTP_MAX_ATTEMPTS,
        OTP_RESEND_TOO_SOON,
        OTP_RATE_LIMIT_EXCEEDED,
        USER_NOT_FOUND,
        INVALID_CREDENTIALS,
        ACCOUNT_DISABLED,
        ACCOUNT_LOCKED,
        VERIFICATION_REQUIRED,
        INVALID_SIGNUP_IDENTIFIER,
        MOBILE_ONLY_FEATURE,
        DEVICE_UNKNOWN,
        TWO_FA_NOT_ENABLED,
        INVALID_PASSWORD,
        INVALID_2FA_METHOD
    }

    private final ErrorCode errorCode;
    private final HttpStatus status;

    public AuthApiException(ErrorCode errorCode, String message, HttpStatus status) {
        super(message);
        this.errorCode = errorCode;
        this.status = status;
    }

    public ErrorCode getErrorCode() {
        return errorCode;
    }

    public HttpStatus getStatus() {
        return status;
    }
}
