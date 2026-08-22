package com.socialmedia.auth.service;

import java.time.LocalDateTime;
import java.util.HashSet;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.TimeUnit;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import com.socialmedia.auth.client.SocialServiceClient;
import com.socialmedia.auth.dto.AuthResponse;
import com.socialmedia.auth.dto.LoginRequest;
import com.socialmedia.auth.dto.RegisterRequest;
import com.socialmedia.auth.entity.PasswordResetToken;
import com.socialmedia.auth.entity.PhoneOtpVerification;
import com.socialmedia.auth.entity.User;
import com.socialmedia.auth.exception.AuthApiException;
import com.socialmedia.auth.repository.PasswordResetTokenRepository;
import com.socialmedia.auth.repository.UserRepository;
import com.socialmedia.auth.security.JwtTokenProvider;
import com.socialmedia.auth.service.IdentifierResolver.IdentifierType;
import com.socialmedia.auth.util.PhoneNumberValidator;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.http.HttpStatus;

@Service
public class AuthService {

    private static final Logger logger = LoggerFactory.getLogger(AuthService.class);

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;
    private final JwtTokenProvider tokenProvider;
    private final RedisTemplate<String, Object> redisTemplate;
    private final EmailService emailService;
    private final PasswordResetTokenRepository passwordResetTokenRepository;
    private final SocialServiceClient socialServiceClient;
    private final OtpService otpService;
    private final PhoneOtpService phoneOtpService;
    private final PhoneNumberValidator phoneNumberValidator;
    private final IdentifierResolver identifierResolver;

    public AuthService(UserRepository userRepository,
                       PasswordEncoder passwordEncoder,
                       JwtTokenProvider tokenProvider,
                       RedisTemplate<String, Object> redisTemplate,
                       EmailService emailService,
                       PasswordResetTokenRepository passwordResetTokenRepository,
                       SocialServiceClient socialServiceClient,
                       OtpService otpService,
                       PhoneOtpService phoneOtpService,
                       PhoneNumberValidator phoneNumberValidator,
                       IdentifierResolver identifierResolver) {
        this.userRepository = userRepository;
        this.passwordEncoder = passwordEncoder;
        this.tokenProvider = tokenProvider;
        this.redisTemplate = redisTemplate;
        this.emailService = emailService;
        this.passwordResetTokenRepository = passwordResetTokenRepository;
        this.socialServiceClient = socialServiceClient;
        this.otpService = otpService;
        this.phoneOtpService = phoneOtpService;
        this.phoneNumberValidator = phoneNumberValidator;
        this.identifierResolver = identifierResolver;
    }

    private static final int MAX_FAILED_ATTEMPTS = 5;
    private static final long LOCK_TIME_DURATION = 15;

    @Transactional
    public AuthResponse register(RegisterRequest request) {
        if (userRepository.existsByUsername(request.getUsername())) {
            throw new RuntimeException("Username already exists");
        }

        boolean hasEmail = request.getEmail() != null && !request.getEmail().trim().isEmpty();
        boolean hasPhone = request.getPhoneNumber() != null && !request.getPhoneNumber().trim().isEmpty();

        if (hasEmail == hasPhone) {
            // Both provided or neither provided — signup accepts exactly one identifier.
            throw new AuthApiException(AuthApiException.ErrorCode.INVALID_SIGNUP_IDENTIFIER,
                    "Provide exactly one of email or phoneNumber", HttpStatus.BAD_REQUEST);
        }

        User user = new User();
        user.setUsername(request.getUsername());
        user.setPassword(passwordEncoder.encode(request.getPassword()));
        user.setFullName(request.getFullName());

        String normalizedEmail = null;
        String normalizedPhone = null;

        if (hasEmail) {
            normalizedEmail = request.getEmail().trim().toLowerCase();
            if (userRepository.existsByEmail(normalizedEmail)) {
                throw new RuntimeException("Email already exists");
            }
            if (!otpService.hasRecentVerification(normalizedEmail)) {
                throw new AuthApiException(AuthApiException.ErrorCode.VERIFICATION_REQUIRED,
                        "Email must be verified (send-otp / verify-otp) before registering", HttpStatus.BAD_REQUEST);
            }
            user.setEmail(normalizedEmail);
            user.setEmailVerified(true);
        } else {
            try {
                normalizedPhone = phoneNumberValidator.normalize(request.getPhoneNumber());
            } catch (IllegalArgumentException e) {
                throw new AuthApiException(AuthApiException.ErrorCode.INVALID_PHONE_NUMBER, e.getMessage(), HttpStatus.BAD_REQUEST);
            }
            if (userRepository.existsByPhoneNumber(normalizedPhone)) {
                throw new AuthApiException(AuthApiException.ErrorCode.PHONE_ALREADY_EXISTS,
                        "Phone number already belongs to another account", HttpStatus.CONFLICT);
            }
            if (!phoneOtpService.hasRecentVerification(normalizedPhone, PhoneOtpVerification.Purpose.PHONE_SIGNUP)) {
                throw new AuthApiException(AuthApiException.ErrorCode.VERIFICATION_REQUIRED,
                        "Phone number must be verified (phone/send-otp / phone/verify-otp) before registering", HttpStatus.BAD_REQUEST);
            }
            user.setPhoneNumber(normalizedPhone);
            user.setPhoneVerified(true);
        }

        Set<String> roles = new HashSet<>();
        roles.add("ROLE_USER");
        user.setRoles(roles);

        user.setEnabled(true);
        user.setAccountNonLocked(true);
        user.setFailedLoginAttempts(0);

        User savedUser;
        try {
            savedUser = userRepository.save(user);
        } catch (DataIntegrityViolationException e) {
            // Belt-and-suspenders against a race between the existsBy* check
            // above and this insert — the DB-level unique constraint is the
            // real source of truth.
            if (normalizedPhone != null) {
                throw new AuthApiException(AuthApiException.ErrorCode.PHONE_ALREADY_EXISTS,
                        "Phone number already belongs to another account", HttpStatus.CONFLICT);
            }
            throw new RuntimeException("Email already exists");
        }

        // Create user profile in social service
        try {
            logger.info("=== REGISTRATION PROFILE CREATION ===");
            logger.info("userId: {}", savedUser.getId());
            logger.info("username: {}", savedUser.getUsername());
            logger.info("email: {}", savedUser.getEmail());
            logger.info("fullName: {}", savedUser.getFullName());
            logger.info("Attempting to create profile for userId: {} with username: {}", savedUser.getId(), savedUser.getUsername());
            socialServiceClient.createUserProfile(
                new SocialServiceClient.CreateProfileRequest(
                    savedUser.getId(),
                    savedUser.getUsername(),
                    savedUser.getEmail(),
                    savedUser.getFullName()
                )
            );
            logger.info("Profile created successfully for userId: {}", savedUser.getId());
        } catch (Exception e) {
            logger.error("Failed to create profile in social service for userId: {}", savedUser.getId(), e);
            logger.error("Exception details: ", e);
        }

        if (savedUser.getEmail() != null) {
            emailService.sendWelcomeEmail(savedUser.getEmail(), savedUser.getUsername());
        }

        String accessToken = tokenProvider.generateAccessToken(savedUser.getId(), savedUser.getEmail());
        String refreshToken = tokenProvider.generateRefreshToken(savedUser.getId(), savedUser.getEmail());

        storeRefreshToken(savedUser.getId(), refreshToken);

        return new AuthResponse(
            accessToken,
            refreshToken,
            savedUser.getId(),
            savedUser.getUsername(),
            savedUser.getEmail(),
            savedUser.getFullName()
        );
    }

    @Transactional
    public AuthResponse login(LoginRequest request) {

        User user;

        if (request.getIdentifier() != null && !request.getIdentifier().trim().isEmpty()) {
            // New identifier-based path — resolves to email or phone (never
            // username), and requires that identifier to be verified.
            user = resolveByIdentifier(request.getIdentifier().trim());
        } else {
            // Existing path, completely unchanged — email with fallback to
            // username. Old clients that only ever send {email,password} or
            // {username,password} hit exactly this branch, unaffected by
            // anything below.
            if (request.getEmail() != null && !request.getEmail().isEmpty()) {
                user = userRepository.findByEmail(request.getEmail())
                    .orElse(null);
            } else {
                user = null;
            }

            // If email not found or not provided, try username
            if (user == null && request.getUsername() != null && !request.getUsername().isEmpty()) {
                user = userRepository.findByUsername(request.getUsername())
                    .orElse(null);
            }
        }

        // If still not found, throw error
        if (user == null) {
            throw new BadCredentialsException("Invalid credentials");
        }

        if (!user.getAccountNonLocked()) {
            if (isAccountUnlockTime(user)) {
                unlockAccount(user);
            } else {
                throw new RuntimeException("Account is locked due to multiple failed login attempts");
            }
        }

        if (!passwordEncoder.matches(request.getPassword(), user.getPassword())) {
            handleFailedLogin(user);
            throw new BadCredentialsException("Invalid credentials");
        }

        if (user.getFailedLoginAttempts() > 0) {
            user.setFailedLoginAttempts(0);
            userRepository.save(user);
        }

        user.setLastLogin(LocalDateTime.now());
        userRepository.save(user);

        String accessToken = tokenProvider.generateAccessToken(user.getId(), user.getEmail());
        String refreshToken = tokenProvider.generateRefreshToken(user.getId(), user.getEmail());

        storeRefreshToken(user.getId(), refreshToken);
        // Sync profile on login to ensure placeholders are replaced with real data
        try {
            logger.info("=== LOGIN PROFILE SYNC ===");
            logger.info("userId: {}", user.getId());
            logger.info("username: {}", user.getUsername());
            logger.info("email: {}", user.getEmail());
            logger.info("fullName: {}", user.getFullName());

            socialServiceClient.createUserProfile(
                new SocialServiceClient.CreateProfileRequest(
                    user.getId(),
                    user.getUsername(),
                    user.getEmail(),
                    user.getFullName()
                )
            );
            logger.info("Profile synced/created for userId: {}", user.getId());
        } catch (Exception e) {
            logger.error("Failed to sync profile during login for userId: {}", user.getId(), e);
        }

        return new AuthResponse(
            accessToken,
            refreshToken,
            user.getId(),
            user.getUsername(),
            user.getEmail(),
            user.getFullName()
        );
    }

    @Transactional
    public void logout(Long userId) {
        // 1. Delete Refresh Token from Redis
        redisTemplate.delete("refresh_token:" + userId);
        
        // 2. Clear FCM Token from Database to stop notifications to this device for this user
        try {
            User user = userRepository.findById(userId).orElse(null);
            if (user != null) {
                user.setFcmToken(null);
                userRepository.save(user);
                logger.info("Cleared FCM token for user ID: {} on logout", userId);
            }
        } catch (Exception e) {
            logger.error("Failed to clear FCM token during logout for user {}: {}", userId, e.getMessage());
        }
    }

    public AuthResponse refreshToken(String refreshToken) {
        if (!tokenProvider.validateToken(refreshToken)) {
            throw new RuntimeException("Invalid refresh token");
        }

        Long userId = tokenProvider.getUserIdFromToken(refreshToken);
        
        try {
            String storedToken = (String) redisTemplate.opsForValue().get("refresh_token:" + userId);
            if (storedToken == null || !storedToken.equals(refreshToken)) {
                throw new RuntimeException("Invalid refresh token");
            }
        } catch (Exception e) {
            // Redis unavailable in local/dev; proceed without strict validation
            // log.warn("Skipping refresh token validation due to cache error", e);
        }

        User user = userRepository.findById(userId)
            .orElseThrow(() -> new RuntimeException("User not found"));

        String newAccessToken = tokenProvider.generateAccessToken(user.getId(), user.getEmail());
        String newRefreshToken = tokenProvider.generateRefreshToken(user.getId(), user.getEmail());

        storeRefreshToken(user.getId(), newRefreshToken);

        return new AuthResponse(
            newAccessToken,
            newRefreshToken,
            user.getId(),
            user.getUsername(),
            user.getEmail(),
            user.getFullName()
        );
    }

    /**
     * Resolves a login "identifier" to a User, enforcing that whichever
     * identifier matched is actually verified. Returns null (not found) —
     * not a thrown exception — when there's no matching user at all, so the
     * caller's existing generic BadCredentialsException path handles it
     * identically to today's "email/username not found" case, avoiding
     * account-existence enumeration. An identifier that resolves to a real,
     * existing-but-unverified account gets its own explicit error instead
     * (matches the spec's own worked example: "Phone number is not
     * verified" is a distinct, expected message, not something to hide).
     */
    private User resolveByIdentifier(String identifier) {
        IdentifierType type = identifierResolver.resolve(identifier);

        if (type == IdentifierType.EMAIL) {
            String normalized = identifier.toLowerCase();
            User user = userRepository.findByEmail(normalized).orElse(null);
            if (user == null) return null;
            if (!Boolean.TRUE.equals(user.getEmailVerified())) {
                throw new AuthApiException(AuthApiException.ErrorCode.EMAIL_NOT_VERIFIED,
                        "Email is not verified.", HttpStatus.FORBIDDEN);
            }
            return user;
        }

        if (type == IdentifierType.PHONE) {
            String normalized;
            try {
                normalized = phoneNumberValidator.normalize(identifier);
            } catch (IllegalArgumentException e) {
                return null;
            }
            User user = userRepository.findByPhoneNumber(normalized).orElse(null);
            if (user == null) return null;
            if (!Boolean.TRUE.equals(user.getPhoneVerified())) {
                throw new AuthApiException(AuthApiException.ErrorCode.PHONE_NOT_VERIFIED,
                        "Phone number is not verified.", HttpStatus.FORBIDDEN);
            }
            return user;
        }

        return null;
    }

    private void handleFailedLogin(User user) {
        int attempts = user.getFailedLoginAttempts() + 1;
        user.setFailedLoginAttempts(attempts);
        
        if (attempts >= MAX_FAILED_ATTEMPTS) {
            user.setAccountNonLocked(false);
            user.setLastLogin(LocalDateTime.now());
        }
        
        userRepository.save(user);
    }

    private boolean isAccountUnlockTime(User user) {
        if (user.getLastLogin() == null) {
            return true;
        }
        LocalDateTime lockTime = user.getLastLogin();
        LocalDateTime unlockTime = lockTime.plusMinutes(LOCK_TIME_DURATION);
        return LocalDateTime.now().isAfter(unlockTime);
    }

    private void unlockAccount(User user) {
        user.setAccountNonLocked(true);
        user.setFailedLoginAttempts(0);
        userRepository.save(user);
    }

    private void storeRefreshToken(Long userId, String refreshToken) {
        try {
            redisTemplate.opsForValue().set(
                "refresh_token:" + userId,
                refreshToken,
                7,
                TimeUnit.DAYS
            );
        } catch (Exception e) {
            // Redis optional in local/dev; skip storing if cache unavailable
            // log.warn("Skipping refresh token cache store", e);
        }
    }
    
    @Transactional
    public void initiatePasswordReset(String email) {
        User user = userRepository.findByEmail(email)
                .orElseThrow(() -> new RuntimeException("User not found with email: " + email));
        
        passwordResetTokenRepository.deleteByUser(user);
        
        String token = UUID.randomUUID().toString();
        
        PasswordResetToken resetToken = new PasswordResetToken();
        resetToken.setToken(token);
        resetToken.setUser(user);
        resetToken.setExpiryDate(LocalDateTime.now().plusHours(1));
        resetToken.setUsed(false);
        
        passwordResetTokenRepository.save(resetToken);
        
        emailService.sendPasswordResetEmail(user.getEmail(), user.getUsername(), token);
    }
    
    @Transactional
    public void resetPassword(String token, String newPassword) {
        PasswordResetToken resetToken = passwordResetTokenRepository.findByToken(token)
                .orElseThrow(() -> new RuntimeException("Invalid password reset token"));
        
        if (resetToken.getUsed()) {
            throw new RuntimeException("Password reset token has already been used");
        }
        
        if (resetToken.isExpired()) {
            throw new RuntimeException("Password reset token has expired");
        }
        
        User user = resetToken.getUser();
        user.setPassword(passwordEncoder.encode(newPassword));
        userRepository.save(user);
        
        resetToken.setUsed(true);
        passwordResetTokenRepository.save(resetToken);
        
        emailService.sendPasswordChangedEmail(user.getEmail(), user.getUsername());
    }
    
    /**
     * Send OTP for password reset
     */
    @Transactional
    public void sendPasswordResetOtp(String email) {
        User user = userRepository.findByEmail(email)
                .orElseThrow(() -> new RuntimeException("User not found with email: " + email));
        
        // Use OtpService to generate and send OTP
        otpService.sendPasswordResetOtp(email);
        
        // Send notification email about password reset request
        emailService.sendPasswordResetOtpEmail(user.getEmail(), user.getUsername());
    }
    
    /**
     * Reset password after OTP verification
     */
    @Transactional
    public void resetPasswordWithEmail(String email, String newPassword) {
        User user = userRepository.findByEmail(email)
                .orElseThrow(() -> new RuntimeException("User not found with email: " + email));
        
        user.setPassword(passwordEncoder.encode(newPassword));
        userRepository.save(user);
        
        emailService.sendPasswordChangedEmail(user.getEmail(), user.getUsername());
    }
    
    /**
     * Check if email exists
     */
    public boolean emailExists(String email) {
        return userRepository.existsByEmail(email);
    }
    
    /**
     * Check if username exists
     */
    public boolean usernameExists(String username) {
        return userRepository.existsByUsername(username);
    }

    /**
     * Check if a (normalized, E.164) phone number is already taken.
     */
    public boolean phoneNumberTaken(String normalizedPhone) {
        return userRepository.existsByPhoneNumber(normalizedPhone);
    }

    /**
     * Links a verified phone number to an already-existing (email- or
     * username-registered) account. Called by PhoneAuthController after a
     * PHONE_VERIFICATION-purpose OTP succeeds. No phone-number-change API
     * exists — this only ever sets phoneNumber when the user doesn't
     * already have one verified.
     */
    @Transactional
    public void linkVerifiedPhone(Long userId, String normalizedPhone) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new RuntimeException("User not found"));

        if (Boolean.TRUE.equals(user.getPhoneVerified())) {
            throw new AuthApiException(AuthApiException.ErrorCode.PHONE_ALREADY_EXISTS,
                    "This account already has a verified phone number", HttpStatus.CONFLICT);
        }
        if (userRepository.existsByPhoneNumber(normalizedPhone)) {
            throw new AuthApiException(AuthApiException.ErrorCode.PHONE_ALREADY_EXISTS,
                    "Phone number already belongs to another account", HttpStatus.CONFLICT);
        }

        user.setPhoneNumber(normalizedPhone);
        user.setPhoneVerified(true);
        try {
            userRepository.save(user);
        } catch (DataIntegrityViolationException e) {
            throw new AuthApiException(AuthApiException.ErrorCode.PHONE_ALREADY_EXISTS,
                    "Phone number already belongs to another account", HttpStatus.CONFLICT);
        }
    }

    /**
     * Links a verified email address to an already-existing (phone-registered)
     * account. Called by AccountLinkingController after OtpService.verifyOtp
     * succeeds for the given email.
     */
    @Transactional
    public void linkVerifiedEmail(Long userId, String normalizedEmail) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new RuntimeException("User not found"));

        if (Boolean.TRUE.equals(user.getEmailVerified())) {
            throw new AuthApiException(AuthApiException.ErrorCode.EMAIL_ALREADY_EXISTS,
                    "This account already has a verified email address", HttpStatus.CONFLICT);
        }
        if (userRepository.existsByEmail(normalizedEmail)) {
            throw new AuthApiException(AuthApiException.ErrorCode.EMAIL_ALREADY_EXISTS,
                    "Email already belongs to another account", HttpStatus.CONFLICT);
        }

        user.setEmail(normalizedEmail);
        user.setEmailVerified(true);
        try {
            userRepository.save(user);
        } catch (DataIntegrityViolationException e) {
            throw new AuthApiException(AuthApiException.ErrorCode.EMAIL_ALREADY_EXISTS,
                    "Email already belongs to another account", HttpStatus.CONFLICT);
        }
    }

    /**
     * Delete user account
     */
    @Transactional
    public void deleteAccount(Long userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new RuntimeException("User not found"));
        
        logger.info("Deleting account for user ID: {}", userId);
        
        // Delete user data from social service
        try {
            socialServiceClient.deleteUserProfile(userId);
            logger.info("Deleted user profile from social service for user ID: {}", userId);
        } catch (Exception e) {
            logger.warn("Failed to delete user profile from social service: {}", e.getMessage());
            // Continue with auth service deletion even if social service fails
        }

        // Cleanup auth-side dependent rows first.
        // In production, password_reset_tokens.user_id uses NO ACTION and can block user delete.
        passwordResetTokenRepository.deleteByUser(user);
        
        // Delete user from auth database
        userRepository.delete(user);
        
        // Clear refresh tokens from Redis
        String refreshTokenKey = "refresh_token:" + userId;
        redisTemplate.delete(refreshTokenKey);
        
        logger.info("Successfully deleted account for user ID: {}", userId);
    }
}