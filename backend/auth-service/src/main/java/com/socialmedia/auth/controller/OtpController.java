package com.socialmedia.auth.controller;

import com.socialmedia.auth.dto.OtpRequest;
import com.socialmedia.auth.dto.OtpVerifyRequest;
import com.socialmedia.auth.entity.OtpVerification.Purpose;
import com.socialmedia.auth.service.OtpService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/")
@Tag(name = "OTP Verification", description = "OTP generation, verification and resend endpoints")
public class OtpController {
    
    private final OtpService otpService;
    
    public OtpController(OtpService otpService) {
        this.otpService = otpService;
    }
    
    @Operation(summary = "Send OTP to email", description = "Generate and send a 4-digit OTP to the provided email address")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "OTP sent successfully"),
        @ApiResponse(responseCode = "400", description = "Invalid email address")
    })
    @PostMapping("/send-otp")
    public ResponseEntity<?> sendOtp(@Valid @RequestBody OtpRequest request) {
        try {
            System.out.println("[OTP] Received send-otp request for email: " + request.getEmail());
            otpService.sendOtp(request.getEmail(), Purpose.EMAIL_VERIFICATION);
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "OTP sent successfully to your email");
            System.out.println("[OTP] Successfully processed OTP request for: " + request.getEmail());
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            System.err.println("[OTP] Error sending OTP: " + e.getMessage());
            e.printStackTrace();
            Map<String, Object> error = new HashMap<>();
            error.put("success", false);
            error.put("message", e.getMessage());
            return ResponseEntity.badRequest().body(error);
        }
    }
    
    @Operation(summary = "Verify OTP code", description = "Verify the 4-digit OTP code sent to the email")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "OTP verified successfully"),
        @ApiResponse(responseCode = "400", description = "Invalid or expired OTP")
    })
    @PostMapping("/verify-otp")
    public ResponseEntity<?> verifyOtp(@Valid @RequestBody OtpVerifyRequest request) {
        try {
            boolean isValid = otpService.verifyOtp(request.getEmail(), request.getOtp(), Purpose.EMAIL_VERIFICATION);
            
            Map<String, Object> response = new HashMap<>();
            if (isValid) {
                response.put("success", true);
                response.put("message", "OTP verified successfully");
                return ResponseEntity.ok(response);
            } else {
                response.put("success", false);
                response.put("message", "Invalid or expired OTP");
                return ResponseEntity.badRequest().body(response);
            }
        } catch (Exception e) {
            Map<String, Object> error = new HashMap<>();
            error.put("success", false);
            error.put("message", e.getMessage());
            return ResponseEntity.badRequest().body(error);
        }
    }
    
    @Operation(summary = "Resend OTP to email", description = "Resend OTP code to the email (max 5 attempts)")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "OTP resent successfully"),
        @ApiResponse(responseCode = "400", description = "Max resend attempts exceeded or no OTP request found")
    })
    @PostMapping("/resend-otp")
    public ResponseEntity<?> resendOtp(@Valid @RequestBody OtpRequest request) {
        try {
            otpService.resendOtp(request.getEmail(), Purpose.EMAIL_VERIFICATION);
            Map<String, Object> response = new HashMap<>();
            response.put("success", true);
            response.put("message", "OTP resent successfully to your email");
            return ResponseEntity.ok(response);
        } catch (Exception e) {
            Map<String, Object> error = new HashMap<>();
            error.put("success", false);
            error.put("message", e.getMessage());
            int statusCode = e.getMessage().contains("Maximum resend attempts") ? 429 : 400;
            return ResponseEntity.status(statusCode).body(error);
        }
    }
}
