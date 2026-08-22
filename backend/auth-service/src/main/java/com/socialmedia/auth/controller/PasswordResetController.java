package com.socialmedia.auth.controller;

import com.socialmedia.auth.dto.OtpVerifyRequest;
import com.socialmedia.auth.dto.PasswordResetRequest;
import com.socialmedia.auth.service.AuthService;
import com.socialmedia.auth.service.OtpService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/password-reset")
@Tag(name = "Password Reset", description = "Password reset and recovery endpoints using OTP")
public class PasswordResetController {
    
    private final AuthService authService;
    private final OtpService otpService;

    public PasswordResetController(AuthService authService, OtpService otpService) {
        this.authService = authService;
        this.otpService = otpService;
    }
    
    @PostMapping("/request")
    @Operation(summary = "Request password reset OTP", description = "Send OTP to user's email for password reset")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "OTP sent successfully"),
        @ApiResponse(responseCode = "404", description = "User not found with the provided email")
    })
    public ResponseEntity<Map<String, String>> requestPasswordReset(
            @Valid @RequestBody PasswordResetRequest request) {
        try {
            authService.sendPasswordResetOtp(request.getEmail());
            return ResponseEntity.ok(Map.of(
                "message", "If the email exists in our system, an OTP has been sent"
            ));
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(Map.of(
                "message", "Failed to send OTP: " + e.getMessage()
            ));
        }
    }
    
    @PostMapping("/verify-otp")
    @Operation(summary = "Verify OTP for password reset", description = "Verify the OTP sent to user's email")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "OTP verified successfully"),
        @ApiResponse(responseCode = "400", description = "Invalid or expired OTP")
    })
    public ResponseEntity<Map<String, String>> verifyOtp(
            @Valid @RequestBody OtpVerifyRequest request) {
        try {
            boolean isValid = otpService.verifyOtp(request.getEmail(), request.getOtp());
            if (isValid) {
                return ResponseEntity.ok(Map.of(
                    "message", "OTP verified successfully. You can now reset your password."
                ));
            } else {
                return ResponseEntity.badRequest().body(Map.of(
                    "message", "Invalid or expired OTP"
                ));
            }
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(Map.of(
                "message", "OTP verification failed: " + e.getMessage()
            ));
        }
    }
    
    @PostMapping("/reset")
    @Operation(summary = "Reset password", description = "Reset password after OTP verification")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Password reset successfully"),
        @ApiResponse(responseCode = "400", description = "Invalid request or user not found")
    })
    public ResponseEntity<Map<String, String>> resetPassword(
            @Valid @RequestBody PasswordResetRequest request) {
        try {
            authService.resetPasswordWithEmail(request.getEmail(), request.getNewPassword());
            return ResponseEntity.ok(Map.of(
                "message", "Password has been reset successfully"
            ));
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(Map.of(
                "message", "Failed to reset password: " + e.getMessage()
            ));
        }
    }
    
    @PostMapping("/resend-otp")
    @Operation(summary = "Resend OTP", description = "Resend OTP for password reset")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "OTP resent successfully"),
        @ApiResponse(responseCode = "400", description = "Failed to resend OTP")
    })
    public ResponseEntity<Map<String, String>> resendOtp(
            @Valid @RequestBody PasswordResetRequest request) {
        try {
            otpService.resendOtp(request.getEmail());
            return ResponseEntity.ok(Map.of(
                "message", "OTP has been resent to your email"
            ));
        } catch (Exception e) {
            return ResponseEntity.badRequest().body(Map.of(
                "message", "Failed to resend OTP: " + e.getMessage()
            ));
        }
    }
}
