package com.socialmedia.auth.controller;

import com.socialmedia.auth.dto.PhoneOtpRequest;
import com.socialmedia.auth.dto.PhoneOtpVerifyRequest;
import com.socialmedia.auth.entity.PhoneOtpVerification;
import com.socialmedia.auth.exception.AuthApiException;
import com.socialmedia.auth.security.IpRateLimiter;
import com.socialmedia.auth.service.AuthService;
import com.socialmedia.auth.service.PhoneOtpService;
import com.socialmedia.auth.util.PhoneNumberValidator;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.servlet.http.HttpServletRequest;
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
 * Phone-number OTP endpoints. Each endpoint is shared between two purposes:
 * PHONE_SIGNUP (unauthenticated, pre-registration — no User row exists yet,
 * the actual account is created afterward by POST /auth/register) and
 * PHONE_VERIFICATION (authenticated — linking a phone number to an already
 * existing email/username account). Both purposes share the same URL paths
 * (Spring Security can't branch permitAll on request body), so
 * PHONE_VERIFICATION explicitly requires a populated "userId" request
 * attribute (set by JwtAuthenticationFilter when a valid Bearer token is
 * present) — see SecurityConfig for the routing rationale.
 */
@RestController
@RequestMapping("/auth/phone")
@Tag(name = "Phone Authentication", description = "Phone-number OTP send/verify/resend for signup and account linking")
public class PhoneAuthController {

    private final PhoneOtpService phoneOtpService;
    private final PhoneNumberValidator phoneNumberValidator;
    private final AuthService authService;
    private final IpRateLimiter ipRateLimiter;

    public PhoneAuthController(PhoneOtpService phoneOtpService,
                                PhoneNumberValidator phoneNumberValidator,
                                AuthService authService,
                                IpRateLimiter ipRateLimiter) {
        this.phoneOtpService = phoneOtpService;
        this.phoneNumberValidator = phoneNumberValidator;
        this.authService = authService;
        this.ipRateLimiter = ipRateLimiter;
    }

    @Operation(summary = "Send phone OTP", description = "Generate and SMS a 6-digit OTP to the given phone number. purpose=PHONE_SIGNUP is unauthenticated (pre-registration); purpose=PHONE_VERIFICATION requires a Bearer token and links to the caller's account once verified.")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "OTP sent successfully"),
        @ApiResponse(responseCode = "400", description = "Invalid phone number or purpose"),
        @ApiResponse(responseCode = "401", description = "PHONE_VERIFICATION requested without authentication"),
        @ApiResponse(responseCode = "429", description = "Rate limit or resend cooldown exceeded")
    })
    @PostMapping("/send-otp")
    public ResponseEntity<?> sendOtp(@Valid @RequestBody PhoneOtpRequest request,
                                      @RequestAttribute(value = "userId", required = false) Long userId,
                                      HttpServletRequest httpRequest) {
        PhoneOtpVerification.Purpose purpose = parsePurpose(request.getPurpose());
        requireAuthForLinking(purpose, userId);
        enforceIpRateLimit(httpRequest);

        String normalized = normalizeOrThrow(request.getPhoneNumber());

        if (purpose == PhoneOtpVerification.Purpose.PHONE_SIGNUP && phoneNumberBelongsToVerifiedUser(normalized)) {
            throw new AuthApiException(AuthApiException.ErrorCode.PHONE_ALREADY_EXISTS,
                    "Phone number already belongs to another account", HttpStatus.CONFLICT);
        }

        phoneOtpService.sendOtp(normalized, purpose);
        return ResponseEntity.ok(Map.of("message", "OTP sent successfully"));
    }

    @Operation(summary = "Verify phone OTP", description = "Verify the 6-digit OTP for the given phone number and purpose. For PHONE_VERIFICATION, success immediately links the phone number to the authenticated account.")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Phone number verified successfully"),
        @ApiResponse(responseCode = "400", description = "Invalid, expired, or already-used OTP")
    })
    @PostMapping("/verify-otp")
    public ResponseEntity<?> verifyOtp(@Valid @RequestBody PhoneOtpVerifyRequest request,
                                        @RequestAttribute(value = "userId", required = false) Long userId) {
        PhoneOtpVerification.Purpose purpose = parsePurpose(request.getPurpose());
        requireAuthForLinking(purpose, userId);

        String normalized = normalizeOrThrow(request.getPhoneNumber());
        phoneOtpService.verifyOtp(normalized, request.getOtp(), purpose);

        if (purpose == PhoneOtpVerification.Purpose.PHONE_VERIFICATION) {
            authService.linkVerifiedPhone(userId, normalized);
        }
        // PHONE_SIGNUP: no User row exists yet — POST /auth/register creates
        // the account afterward, checking hasRecentVerification() as proof.

        return ResponseEntity.ok(Map.of("verified", true, "message", "Phone number verified successfully"));
    }

    @Operation(summary = "Resend phone OTP", description = "Invalidate the previous OTP and send a new one, subject to cooldown and hourly rate limiting.")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "OTP resent successfully"),
        @ApiResponse(responseCode = "400", description = "No prior OTP request found for this phone number"),
        @ApiResponse(responseCode = "429", description = "Resend cooldown or rate limit exceeded")
    })
    @PostMapping("/resend-otp")
    public ResponseEntity<?> resendOtp(@Valid @RequestBody PhoneOtpRequest request,
                                        @RequestAttribute(value = "userId", required = false) Long userId,
                                        HttpServletRequest httpRequest) {
        PhoneOtpVerification.Purpose purpose = parsePurpose(request.getPurpose());
        requireAuthForLinking(purpose, userId);
        enforceIpRateLimit(httpRequest);

        String normalized = normalizeOrThrow(request.getPhoneNumber());
        phoneOtpService.resendOtp(normalized, purpose);
        return ResponseEntity.ok(Map.of("message", "OTP resent successfully"));
    }

    private PhoneOtpVerification.Purpose parsePurpose(String raw) {
        try {
            return PhoneOtpVerification.Purpose.valueOf(raw.trim().toUpperCase());
        } catch (Exception e) {
            throw new AuthApiException(AuthApiException.ErrorCode.INVALID_SIGNUP_IDENTIFIER,
                    "purpose must be one of PHONE_SIGNUP, PHONE_VERIFICATION", HttpStatus.BAD_REQUEST);
        }
    }

    private void requireAuthForLinking(PhoneOtpVerification.Purpose purpose, Long userId) {
        if (purpose == PhoneOtpVerification.Purpose.PHONE_VERIFICATION && userId == null) {
            throw new AuthApiException(AuthApiException.ErrorCode.USER_NOT_FOUND,
                    "PHONE_VERIFICATION requires authentication", HttpStatus.UNAUTHORIZED);
        }
    }

    private String normalizeOrThrow(String rawPhoneNumber) {
        try {
            return phoneNumberValidator.normalize(rawPhoneNumber);
        } catch (IllegalArgumentException e) {
            throw new AuthApiException(AuthApiException.ErrorCode.INVALID_PHONE_NUMBER, e.getMessage(), HttpStatus.BAD_REQUEST);
        }
    }

    private boolean phoneNumberBelongsToVerifiedUser(String normalizedPhone) {
        return authService.phoneNumberTaken(normalizedPhone);
    }

    private void enforceIpRateLimit(HttpServletRequest request) {
        String ip = request.getHeader("X-Forwarded-For");
        if (ip == null || ip.isBlank()) {
            ip = request.getRemoteAddr();
        } else {
            ip = ip.split(",")[0].trim(); // first hop is the original client
        }
        if (!ipRateLimiter.allow(ip)) {
            throw new AuthApiException(AuthApiException.ErrorCode.OTP_RATE_LIMIT_EXCEEDED,
                    "Too many requests from this network. Please try again later.", HttpStatus.TOO_MANY_REQUESTS);
        }
    }
}
