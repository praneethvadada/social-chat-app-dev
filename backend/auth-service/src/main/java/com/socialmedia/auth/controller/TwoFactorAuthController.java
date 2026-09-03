package com.socialmedia.auth.controller;

import com.socialmedia.auth.dto.TwoFactorDisableRequest;
import com.socialmedia.auth.dto.TwoFactorEnableRequest;
import com.socialmedia.auth.dto.TwoFactorMethodRequest;
import com.socialmedia.auth.dto.TwoFactorStatusResponse;
import com.socialmedia.auth.service.TwoFactorAuthService;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestAttribute;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 2FA configuration (spec Phase 6). Requires authentication — none of these
 * paths are in SecurityConfig's permitAll list. The login-time CHALLENGE
 * (presenting/verifying the OTP when 2FA is enabled) is Phase 7, not here.
 */
@RestController
@RequestMapping("/security/2fa")
@Tag(name = "Two-Factor Authentication", description = "Enable, disable, and change 2FA method")
public class TwoFactorAuthController {

    private final TwoFactorAuthService twoFactorAuthService;

    public TwoFactorAuthController(TwoFactorAuthService twoFactorAuthService) {
        this.twoFactorAuthService = twoFactorAuthService;
    }

    @Operation(summary = "My 2FA status", description = "Whether 2FA is enabled, and which method (PHONE/EMAIL) if so.")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Status returned"),
        @ApiResponse(responseCode = "401", description = "Not authenticated")
    })
    @GetMapping
    public ResponseEntity<TwoFactorStatusResponse> status(
            @RequestAttribute(value = "userId", required = false) Long userId) {
        if (userId == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        return ResponseEntity.ok(twoFactorAuthService.getStatus(userId));
    }

    @Operation(summary = "Send a 2FA setup OTP", description = "Sends an OTP to the account's already-verified phone or email, to prove control before enabling/switching to it.")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "OTP sent"),
        @ApiResponse(responseCode = "400", description = "That method isn't verified on this account, or method is invalid"),
        @ApiResponse(responseCode = "401", description = "Not authenticated")
    })
    @PostMapping("/send-otp")
    public ResponseEntity<?> sendOtp(
            @Valid @RequestBody TwoFactorMethodRequest request,
            @RequestAttribute(value = "userId", required = false) Long userId) {
        if (userId == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        twoFactorAuthService.sendConfigOtp(userId, request.getMethod());
        return ResponseEntity.ok().build();
    }

    @Operation(summary = "Enable 2FA", description = "Enables 2FA using the given method, proven via a fresh OTP (see /send-otp). Also works to switch method if already enabled.")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "2FA enabled"),
        @ApiResponse(responseCode = "400", description = "Invalid/expired OTP, or that method isn't verified"),
        @ApiResponse(responseCode = "401", description = "Not authenticated")
    })
    @PostMapping("/enable")
    public ResponseEntity<?> enable(
            @Valid @RequestBody TwoFactorEnableRequest request,
            @RequestAttribute(value = "userId", required = false) Long userId) {
        if (userId == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        return ResponseEntity.ok(twoFactorAuthService.enableOrChangeMethod(userId, request.getMethod(), request.getOtp()));
    }

    @Operation(summary = "Switch 2FA method", description = "Same as /enable — proves control of the new method via a fresh OTP, then switches to it. Distinct endpoint for a clearer client-facing action name.")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "2FA method changed"),
        @ApiResponse(responseCode = "400", description = "Invalid/expired OTP, or that method isn't verified"),
        @ApiResponse(responseCode = "401", description = "Not authenticated")
    })
    @PostMapping("/change-method")
    public ResponseEntity<?> changeMethod(
            @Valid @RequestBody TwoFactorEnableRequest request,
            @RequestAttribute(value = "userId", required = false) Long userId) {
        if (userId == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        return ResponseEntity.ok(twoFactorAuthService.enableOrChangeMethod(userId, request.getMethod(), request.getOtp()));
    }

    @Operation(summary = "Disable 2FA", description = "Requires the current password, not an OTP — disabling weakens the account, so it's gated by re-proving ownership, not channel control.")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "2FA disabled"),
        @ApiResponse(responseCode = "400", description = "Incorrect password, or 2FA wasn't enabled"),
        @ApiResponse(responseCode = "401", description = "Not authenticated")
    })
    @PostMapping("/disable")
    public ResponseEntity<?> disable(
            @Valid @RequestBody TwoFactorDisableRequest request,
            @RequestAttribute(value = "userId", required = false) Long userId) {
        if (userId == null) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED).build();
        }
        twoFactorAuthService.disable(userId, request.getPassword());
        return ResponseEntity.ok().build();
    }
}
