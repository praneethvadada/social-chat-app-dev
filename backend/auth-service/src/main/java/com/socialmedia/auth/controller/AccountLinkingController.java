package com.socialmedia.auth.controller;

import com.socialmedia.auth.dto.OtpVerifyRequest;
import com.socialmedia.auth.entity.OtpVerification.Purpose;
import com.socialmedia.auth.exception.AuthApiException;
import com.socialmedia.auth.service.AuthService;
import com.socialmedia.auth.service.OtpService;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestAttribute;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/**
 * Adds a secondary identifier (email) to an already-existing phone-only
 * account. The phone-side equivalent lives in PhoneAuthController
 * (purpose=PHONE_VERIFICATION on the same send-otp/verify-otp endpoints)
 * — email reuses the *existing*, unchanged /auth/send-otp + /auth/verify-otp
 * (see OtpController) for actually dispatching/checking the code; this
 * controller only adds the "link it to my account" step on top.
 */
@RestController
@RequestMapping("/auth/email")
@Tag(name = "Account Linking", description = "Add a verified email to an existing phone-registered account")
public class AccountLinkingController {

    private final OtpService otpService;
    private final AuthService authService;

    public AccountLinkingController(OtpService otpService, AuthService authService) {
        this.otpService = otpService;
        this.authService = authService;
    }

    @Operation(summary = "Link a verified email to my account",
            description = "Call POST /auth/send-otp {email} first to get a code emailed, then call this with {email, otp}. On success, sets email/emailVerified=true on the authenticated account. Requires a Bearer token.")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Email linked successfully"),
        @ApiResponse(responseCode = "400", description = "Invalid or expired OTP"),
        @ApiResponse(responseCode = "401", description = "Missing/invalid Bearer token"),
        @ApiResponse(responseCode = "409", description = "Email already belongs to another account, or this account already has a verified email")
    })
    @PostMapping("/link")
    public ResponseEntity<?> linkEmail(@Valid @RequestBody OtpVerifyRequest request,
                                        @RequestAttribute(value = "userId", required = false) Long userId) {
        if (userId == null) {
            throw new AuthApiException(AuthApiException.ErrorCode.USER_NOT_FOUND,
                    "Authentication required", HttpStatus.UNAUTHORIZED);
        }

        boolean verified = otpService.verifyOtp(request.getEmail(), request.getOtp(), Purpose.EMAIL_VERIFICATION);
        if (!verified) {
            throw new AuthApiException(AuthApiException.ErrorCode.OTP_INVALID,
                    "Invalid or expired OTP", HttpStatus.BAD_REQUEST);
        }

        authService.linkVerifiedEmail(userId, request.getEmail().trim().toLowerCase());
        return ResponseEntity.ok(Map.of("verified", true, "message", "Email linked successfully"));
    }
}
