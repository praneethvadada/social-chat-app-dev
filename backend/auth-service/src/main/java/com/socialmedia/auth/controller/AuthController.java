package com.socialmedia.auth.controller;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestAttribute;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import jakarta.servlet.http.HttpServletRequest;

import com.socialmedia.auth.dto.AuthResponse;
import com.socialmedia.auth.dto.LoginRequest;
import com.socialmedia.auth.dto.RegisterRequest;
import com.socialmedia.auth.dto.TwoFactorLoginResendRequest;
import com.socialmedia.auth.dto.TwoFactorLoginVerifyRequest;
import com.socialmedia.auth.exception.AuthApiException;
import com.socialmedia.auth.exception.TwoFactorRequiredException;
import com.socialmedia.auth.security.IpRateLimiter;
import com.socialmedia.auth.service.AuthService;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.media.Content;
import io.swagger.v3.oas.annotations.media.Schema;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import java.util.Map;

@RestController
@RequestMapping("/")
@Tag(name = "Authentication", description = "User authentication and registration endpoints")
public class AuthController {

    private final AuthService authService;
    private final IpRateLimiter ipRateLimiter;

    public AuthController(AuthService authService, IpRateLimiter ipRateLimiter) {
        this.authService = authService;
        this.ipRateLimiter = ipRateLimiter;
    }

    @Operation(summary = "Register new user",
        description = "Create a new user account and receive JWT tokens. Provide exactly one of `email` or `phoneNumber` (never both, never neither) — whichever you choose must already be verified via /auth/send-otp+/auth/verify-otp (email) or /auth/phone/send-otp+/auth/phone/verify-otp (phone, purpose=PHONE_SIGNUP) before calling this. The other identifier can be added later via POST /auth/phone/send-otp (purpose=PHONE_VERIFICATION, authenticated) or POST /auth/email/link (authenticated).",
        requestBody = @io.swagger.v3.oas.annotations.parameters.RequestBody(content = @Content(examples = {
            @io.swagger.v3.oas.annotations.media.ExampleObject(name = "Email signup", value = "{\"username\":\"praneeth\",\"password\":\"Password@123\",\"email\":\"user@example.com\",\"fullName\":\"Praneeth Vadada\"}"),
            @io.swagger.v3.oas.annotations.media.ExampleObject(name = "Phone signup", value = "{\"username\":\"praneeth\",\"password\":\"Password@123\",\"phoneNumber\":\"+919876543210\",\"fullName\":\"Praneeth Vadada\"}")
        })))
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "User registered successfully",
            content = @Content(schema = @Schema(implementation = AuthResponse.class))),
        @ApiResponse(responseCode = "400", description = "Invalid input, VERIFICATION_REQUIRED (identifier not yet OTP-verified), or INVALID_SIGNUP_IDENTIFIER (both or neither of email/phoneNumber provided)"),
        @ApiResponse(responseCode = "409", description = "Username, email, or phone number already exists")
    })
    @PostMapping("/register")
    public ResponseEntity<?> register(@Valid @RequestBody RegisterRequest request, HttpServletRequest httpRequest) {
        try {
            AuthResponse response = authService.register(request, clientIp(httpRequest));
            return ResponseEntity.ok(response);
        } catch (com.socialmedia.auth.exception.AuthApiException e) {
            // New, standardized error codes (verification-required, invalid
            // signup identifier, phone-already-exists, etc.) — let
            // GlobalExceptionHandler format the {errorCode, message} body.
            throw e;
        } catch (RuntimeException e) {
            // As in login() below: only the one genuinely-expected plain-
            // RuntimeException shape from AuthService.register() (a
            // duplicate-username/email message) is special-cased here.
            // Anything else rethrows to a real 500 instead of being
            // misreported as "Invalid signup details" — the same masking
            // that hid a real device-registration bug in login() during
            // Phase 1 testing applied equally here.
            String errorMsg = e.getMessage();
            if (errorMsg != null && (errorMsg.contains("already exists") || errorMsg.contains("Already exists"))) {
                return ResponseEntity.status(409).body(java.util.Map.of("message", errorMsg));
            }
            throw e;
        }
    }

    @Operation(summary = "User login",
        description = "Authenticate and receive JWT tokens. Either send `identifier` (an email address or E.164 phone number — resolved automatically, requires that identifier to be verified) with `password`, or use the pre-existing `email`/`username` fields exactly as before (unaffected by `identifier`).",
        requestBody = @io.swagger.v3.oas.annotations.parameters.RequestBody(content = @Content(examples = {
            @io.swagger.v3.oas.annotations.media.ExampleObject(name = "Email login (identifier)", value = "{\"identifier\":\"user@example.com\",\"password\":\"Password@123\"}"),
            @io.swagger.v3.oas.annotations.media.ExampleObject(name = "Phone login (identifier)", value = "{\"identifier\":\"+919876543210\",\"password\":\"Password@123\"}"),
            @io.swagger.v3.oas.annotations.media.ExampleObject(name = "Username login (unchanged)", value = "{\"username\":\"praneeth\",\"password\":\"Password@123\"}")
        })))
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Login successful",
            content = @Content(schema = @Schema(implementation = AuthResponse.class))),
        @ApiResponse(responseCode = "401", description = "Invalid credentials or account locked"),
        @ApiResponse(responseCode = "403", description = "EMAIL_NOT_VERIFIED or PHONE_NOT_VERIFIED — the resolved identifier exists but hasn't been OTP-verified yet")
    })
    @PostMapping("/login")
    public ResponseEntity<?> login(@Valid @RequestBody LoginRequest request, HttpServletRequest httpRequest) {
        // Phase 10 hardening: per-account failed-attempt lockout (below,
        // MAX_FAILED_ATTEMPTS in AuthService) already guards a single
        // account against password brute-forcing, but does nothing against
        // a distributed attack trying many DIFFERENT accounts from one
        // source, or one IP hammering /login purely to keep re-minting
        // fresh 2FA challenge tokens (each one resets the OTP guess budget
        // — see OtpService.MAX_VERIFY_ATTEMPTS). IP throttling here closes
        // that gap; reuses the same component/style as PhoneAuthController's
        // enforceIpRateLimit, keyed separately so it doesn't share a bucket
        // with unrelated phone-OTP-send traffic from the same IP.
        if (!ipRateLimiter.allow("login:" + clientIp(httpRequest))) {
            throw new AuthApiException(AuthApiException.ErrorCode.OTP_RATE_LIMIT_EXCEEDED,
                    "Too many login attempts from this network. Please try again later.", HttpStatus.TOO_MANY_REQUESTS);
        }
        try {
            AuthResponse response = authService.login(request, clientIp(httpRequest));
            return ResponseEntity.ok(response);
        } catch (TwoFactorRequiredException e) {
            // Not an error — correct credentials, but 2FA must also pass.
            // No token here at all yet; see completeTwoFactorLogin.
            return ResponseEntity.ok(e.getChallenge());
        } catch (com.socialmedia.auth.exception.WebSessionConflictException e) {
            // Not an error — correct credentials (and 2FA, if it applied),
            // but the account is already active on a different web device.
            // No token here at all yet; see confirmWebSessionTakeover.
            return ResponseEntity.ok(e.getConflict());
        } catch (com.socialmedia.auth.exception.AuthApiException e) {
            // Explicit "not verified" errors (spec: this message must be
            // surfaced, unlike a generic invalid-credentials case) — let
            // GlobalExceptionHandler format the {errorCode, message} body.
            throw e;
        } catch (org.springframework.security.authentication.BadCredentialsException e) {
            return ResponseEntity.status(401).build();
        } catch (RuntimeException e) {
            // Previously this was a blanket `catch (Exception e) { return
            // 401 }` — which meant ANY bug in login() (including, during
            // Phase 1 testing, an unrelated DB column-width overflow in the
            // new device-registration path) silently presented to the
            // client as "invalid credentials", making it look like a
            // credentials problem when it was actually a server bug. Only
            // the one other genuinely-expected failure mode (account
            // locked) is special-cased here; anything else rethrows so it
            // surfaces as a real 500, visible in logs/monitoring instead of
            // being misdiagnosed as a wrong password.
            if (e.getMessage() != null && e.getMessage().contains("Account is locked")) {
                return ResponseEntity.status(401).body(Map.of("message", e.getMessage()));
            }
            throw e;
        }
    }

    @Operation(summary = "Complete 2FA login challenge", description = "Verifies the OTP from the /login challenge and, on success, finishes login exactly like a non-2FA /login call would (creates device/session, issues real tokens) — unless the account is ALSO already active on a different web device, in which case this returns a web-session-conflict challenge instead (see /login/web-session/confirm).")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Login completed, or a web-session-conflict challenge (see WebSessionConflictResponse)", content = @Content(schema = @Schema(implementation = AuthResponse.class))),
        @ApiResponse(responseCode = "400", description = "Invalid/expired challenge or OTP")
    })
    @PostMapping("/login/2fa/verify")
    public ResponseEntity<?> verifyTwoFactorLogin(@Valid @RequestBody TwoFactorLoginVerifyRequest request, HttpServletRequest httpRequest) {
        // Phase 10 hardening: defense-in-depth alongside OtpService's own
        // per-code guess cap — without this, an attacker who already has a
        // stolen-but-correct password could keep calling /login to mint a
        // fresh challengeToken (and fresh 5-guess OTP budget) indefinitely.
        if (!ipRateLimiter.allow("2fa-verify:" + clientIp(httpRequest))) {
            throw new AuthApiException(AuthApiException.ErrorCode.OTP_RATE_LIMIT_EXCEEDED,
                    "Too many attempts from this network. Please try again later.", HttpStatus.TOO_MANY_REQUESTS);
        }
        try {
            AuthResponse response = authService.completeTwoFactorLogin(
                    request.getChallengeToken(), request.getOtp(), request.getDeviceInfo(), clientIp(httpRequest));
            return ResponseEntity.ok(response);
        } catch (com.socialmedia.auth.exception.WebSessionConflictException e) {
            return ResponseEntity.ok(e.getConflict());
        }
    }

    @Operation(summary = "Confirm web-session takeover", description = "Completes a login that was paused by a web-session-conflict challenge (from /login or /login/2fa/verify) — logs out the other web device and finishes this login (creates device/session, issues real tokens). deviceInfo must be the SAME device info the original /login call sent.")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Login completed, other device logged out", content = @Content(schema = @Schema(implementation = AuthResponse.class))),
        @ApiResponse(responseCode = "400", description = "Invalid/expired challenge")
    })
    @PostMapping("/login/web-session/confirm")
    public ResponseEntity<AuthResponse> confirmWebSessionTakeover(@Valid @RequestBody com.socialmedia.auth.dto.WebSessionConfirmRequest request,
                                                                    HttpServletRequest httpRequest) {
        // Same reasoning as the 2FA-verify rate limit above — this is the
        // other endpoint a stolen challengeToken could be hammered against.
        if (!ipRateLimiter.allow("web-session-confirm:" + clientIp(httpRequest))) {
            throw new AuthApiException(AuthApiException.ErrorCode.OTP_RATE_LIMIT_EXCEEDED,
                    "Too many attempts from this network. Please try again later.", HttpStatus.TOO_MANY_REQUESTS);
        }
        AuthResponse response = authService.confirmWebSessionTakeover(
                request.getChallengeToken(), request.getDeviceInfo(), clientIp(httpRequest));
        return ResponseEntity.ok(response);
    }

    @Operation(summary = "Resend 2FA login OTP", description = "Resends the OTP for an in-progress 2FA login challenge.")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "OTP resent"),
        @ApiResponse(responseCode = "400", description = "Invalid/expired challenge, or resend too soon")
    })
    @PostMapping("/login/2fa/resend")
    public ResponseEntity<Void> resendTwoFactorLogin(@Valid @RequestBody TwoFactorLoginResendRequest request) {
        authService.resendTwoFactorLoginOtp(request.getChallengeToken());
        return ResponseEntity.ok().build();
    }

    @Operation(summary = "User logout", description = "Logout user, invalidate refresh token, and revoke the current session.")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Logout successful"),
        @ApiResponse(responseCode = "401", description = "Not authenticated")
    })
    @PostMapping("/logout")
    public ResponseEntity<Void> logout(@RequestAttribute(value = "userId", required = false) Long userId,
                                        @RequestAttribute(value = "sid", required = false) String sessionToken) {
        // Previously trusted a client-supplied X-User-Id header for this —
        // spoofable by any caller. Now derived from the validated JWT the
        // same way every other authenticated endpoint in this service does.
        if (userId == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        authService.logout(userId, sessionToken);
        return ResponseEntity.ok().build();
    }

    @Operation(summary = "Refresh access token", description = "Get new access token using refresh token")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Token refreshed successfully",
            content = @Content(schema = @Schema(implementation = AuthResponse.class))),
        @ApiResponse(responseCode = "401", description = "Invalid or expired refresh token")
    })
    @PostMapping("/refresh")
    public ResponseEntity<AuthResponse> refreshToken(@RequestParam String refreshToken) {
        try {
            AuthResponse response = authService.refreshToken(refreshToken);
            return ResponseEntity.ok(response);
        } catch (RuntimeException e) {
            return ResponseEntity.status(401).build();
        }
    }

    @Operation(summary = "Health check", description = "Check if the service is running")
    @ApiResponse(responseCode = "200", description = "Service is healthy")
    @GetMapping("/health")
    public ResponseEntity<String> health() {
        return ResponseEntity.ok("Auth Service is running");
    }

    @Operation(summary = "Check availability", description = "Check if email or username is available")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Availability check completed")
    })
    @GetMapping("/check-availability")
    public ResponseEntity<?> checkAvailability(
            @RequestParam(required = false) String email,
            @RequestParam(required = false) String username) {
        java.util.Map<String, Boolean> result = new java.util.HashMap<>();
        
        if (email != null && !email.trim().isEmpty()) {
            result.put("emailExists", authService.emailExists(email));
        }
        
        if (username != null && !username.trim().isEmpty()) {
            result.put("usernameExists", authService.usernameExists(username));
        }
        
        return ResponseEntity.ok(result);
    }

    @Operation(summary = "Delete my account", description = "Requires the current password, and an OTP too if 2FA is enabled (see AuthService.deleteAccount's own doc comment for why this changed).")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Account deleted"),
        @ApiResponse(responseCode = "400", description = "Incorrect password, or missing/invalid OTP when 2FA is enabled"),
        @ApiResponse(responseCode = "401", description = "Not authenticated")
    })
    @DeleteMapping("/account")
    public ResponseEntity<?> deleteAccount(
            @RequestBody Map<String, String> request,
            @RequestAttribute(value = "userId", required = false) Long userId) {
        if (userId == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        String password = request.get("password");
        String otp = request.get("otp");
        authService.deleteAccount(userId, password, otp);
        return ResponseEntity.ok(Map.of("message", "Account deleted successfully"));
    }

    // Mirrors PhoneAuthController.enforceIpRateLimit's own X-Forwarded-For handling.
    private String clientIp(HttpServletRequest request) {
        String ip = request.getHeader("X-Forwarded-For");
        if (ip == null || ip.isBlank()) {
            return request.getRemoteAddr();
        }
        return ip.split(",")[0].trim();
    }
}