package com.socialmedia.auth.controller;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.socialmedia.auth.dto.AuthResponse;
import com.socialmedia.auth.dto.LoginRequest;
import com.socialmedia.auth.dto.RegisterRequest;
import com.socialmedia.auth.entity.User;
import com.socialmedia.auth.repository.UserRepository;
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
    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;

    public AuthController(AuthService authService, UserRepository userRepository, PasswordEncoder passwordEncoder) {
        this.authService = authService;
        this.userRepository = userRepository;
        this.passwordEncoder = passwordEncoder;
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
    public ResponseEntity<?> register(@Valid @RequestBody RegisterRequest request) {
        try {
            AuthResponse response = authService.register(request);
            return ResponseEntity.ok(response);
        } catch (com.socialmedia.auth.exception.AuthApiException e) {
            // New, standardized error codes (verification-required, invalid
            // signup identifier, phone-already-exists, etc.) — let
            // GlobalExceptionHandler format the {errorCode, message} body.
            throw e;
        } catch (RuntimeException e) {
            String errorMsg = e.getMessage();
            if (errorMsg != null && (errorMsg.contains("already exists") || errorMsg.contains("Already exists"))) {
                return ResponseEntity.status(409).body(java.util.Map.of("message", errorMsg));
            }
            return ResponseEntity.badRequest().body(java.util.Map.of("message", errorMsg != null ? errorMsg : "Invalid signup details"));
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
    public ResponseEntity<?> login(@Valid @RequestBody LoginRequest request) {
        try {
            AuthResponse response = authService.login(request);
            return ResponseEntity.ok(response);
        } catch (com.socialmedia.auth.exception.AuthApiException e) {
            // Explicit "not verified" errors (spec: this message must be
            // surfaced, unlike a generic invalid-credentials case) — let
            // GlobalExceptionHandler format the {errorCode, message} body.
            throw e;
        } catch (Exception e) {
            return ResponseEntity.status(401).build();
        }
    }

    @Operation(summary = "User logout", description = "Logout user and invalidate refresh token")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Logout successful")
    })
    @PostMapping("/logout")
    public ResponseEntity<Void> logout(@RequestHeader("X-User-Id") Long userId) {
        authService.logout(userId);
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

    @Operation(summary = "Delete user account", description = "Delete the user's account with email and password verification")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Account deleted successfully"),
        @ApiResponse(responseCode = "401", description = "Invalid credentials"),
        @ApiResponse(responseCode = "404", description = "User not found")
    })
    @DeleteMapping("/account")
    public ResponseEntity<?> deleteAccount(@RequestBody Map<String, String> request) {
        try {
            String email = request.get("email");
            String password = request.get("password");
            
            if (email == null || password == null) {
                return ResponseEntity.badRequest()
                        .body(Map.of("error", "Email and password are required"));
            }
            
            // Verify user credentials before deletion
            User user = userRepository.findByEmail(email)
                    .orElseThrow(() -> new RuntimeException("User not found"));
            
            if (!passwordEncoder.matches(password, user.getPassword())) {
                return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                        .body(Map.of("error", "Invalid password"));
            }
            
            authService.deleteAccount(user.getId());
            return ResponseEntity.ok(Map.of("message", "Account deleted successfully"));
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", "Failed to delete account: " + e.getMessage()));
        }
    }
}