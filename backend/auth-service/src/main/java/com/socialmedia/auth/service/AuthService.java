package com.socialmedia.auth.service;

import java.time.LocalDateTime;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
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
import com.socialmedia.auth.entity.PhoneOtpVerification;
import com.socialmedia.auth.entity.SecurityEvent;
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
    private final DeviceSessionService deviceSessionService;
    private final ActiveWebSessionService activeWebSessionService;
    private final TwoFactorAuthService twoFactorAuthService;
    private final SecurityEventService securityEventService;

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
                       IdentifierResolver identifierResolver,
                       DeviceSessionService deviceSessionService,
                       ActiveWebSessionService activeWebSessionService,
                       TwoFactorAuthService twoFactorAuthService,
                       SecurityEventService securityEventService) {
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
        this.deviceSessionService = deviceSessionService;
        this.activeWebSessionService = activeWebSessionService;
        this.twoFactorAuthService = twoFactorAuthService;
        this.securityEventService = securityEventService;
    }

    private static final int MAX_FAILED_ATTEMPTS = 5;
    private static final long LOCK_TIME_DURATION = 15;

    @Transactional
    public AuthResponse register(RegisterRequest request) {
        return register(request, null);
    }

    @Transactional
    public AuthResponse register(RegisterRequest request, String ipAddress) {
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
            if (!otpService.hasRecentVerification(normalizedEmail, com.socialmedia.auth.entity.OtpVerification.Purpose.EMAIL_VERIFICATION)) {
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

        var device = deviceSessionService.registerDevice(savedUser.getId(), request.getDeviceInfo());
        var session = device == null ? null : deviceSessionService.createSession(savedUser.getId(), device.getId(), ipAddress);
        String sessionToken = session == null ? null : session.getSessionToken();
        Long deviceId = device == null ? null : device.getId();
        if (device != null && session != null && "WEB".equals(device.getPlatform())) {
            activeWebSessionService.claimOrReplace(savedUser.getId(), deviceId, session);
        }

        String accessToken = tokenProvider.generateAccessToken(savedUser.getId(), savedUser.getEmail(), sessionToken, deviceId);
        String refreshToken = tokenProvider.generateRefreshToken(savedUser.getId(), savedUser.getEmail(), sessionToken, deviceId);

        storeRefreshToken(savedUser.getId(), refreshToken);

        AuthResponse response = new AuthResponse(
            accessToken,
            refreshToken,
            savedUser.getId(),
            savedUser.getUsername(),
            savedUser.getEmail(),
            savedUser.getFullName()
        );
        response.setDeviceId(deviceId);
        return response;
    }

    @Transactional
    public AuthResponse login(LoginRequest request) {
        return login(request, null);
    }

    // Phase 7: noRollbackFor is required here — throwing
    // TwoFactorRequiredException to signal the challenge flow is normal
    // control flow, not a failure, but Spring's default behavior for any
    // unchecked exception is to roll back the whole transaction. Without
    // this, the OTP row sendLoginChallengeOtp() just saved (moments earlier,
    // in this same transaction) would be silently undone the instant the
    // exception propagates — the client would get a challengeToken for an
    // OTP that was never actually persisted. Post-Phase-10: WebSessionConflictException
    // (thrown from finishLogin(), called at the bottom of this method) added
    // defensively for the same class of reason — nothing critical is written
    // before that throw point today, but relying on that staying true forever
    // is more fragile than just declaring the same guard TwoFactorRequiredException
    // already needed.
    //
    // SEVERE PRE-EXISTING BUG found+fixed while live-testing the new
    // LOGIN_FAILED push-notification feature: BadCredentialsException was
    // NOT in this list, despite being thrown on every wrong-password
    // attempt right after handleFailedLogin(user) — a real DB write
    // (userRepository.save(user), incrementing failedLoginAttempts, the
    // actual MAX_FAILED_ATTEMPTS lockout counter). That write was being
    // silently rolled back on EVERY SINGLE wrong-password attempt this
    // entire time, meaning the account-lockout brute-force protection has
    // never actually worked — failed_login_attempts stayed at 0 forever,
    // confirmed empirically (3 wrong passwords in a row against a live
    // test account, checked the DB directly: still 0 after). Only the
    // separate, much weaker Phase 10 IP-based rate limiter (20/hour,
    // trivially bypassed by rotating IPs) was ever actually protecting
    // this endpoint. Fixed by adding BadCredentialsException here too.
    @Transactional(noRollbackFor = {
            com.socialmedia.auth.exception.TwoFactorRequiredException.class,
            com.socialmedia.auth.exception.WebSessionConflictException.class,
            org.springframework.security.authentication.BadCredentialsException.class})
    public AuthResponse login(LoginRequest request, String ipAddress) {

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
                // Post-Phase-10, user-requested: notify on every unsuccessful
                // attempt too, not just successful logins — someone is still
                // trying to get into a locked account, worth knowing about.
                securityEventService.record(user.getId(), SecurityEvent.EventType.LOGIN_FAILED, null, null,
                        ipAddress, null, Map.of("reason", "account_locked"));
                throw new RuntimeException("Account is locked due to multiple failed login attempts");
            }
        }

        if (!passwordEncoder.matches(request.getPassword(), user.getPassword())) {
            handleFailedLogin(user);
            // Same reasoning as the locked-account case above — a wrong
            // password against a real, resolvable account (whichever
            // identifier type was used: email, username, or phone) is
            // exactly the "someone's trying my account" signal worth a push.
            securityEventService.record(user.getId(), SecurityEvent.EventType.LOGIN_FAILED, null, null,
                    ipAddress, null, Map.of("reason", "wrong_password"));
            throw new BadCredentialsException("Invalid credentials");
        }

        if (user.getFailedLoginAttempts() > 0) {
            user.setFailedLoginAttempts(0);
            userRepository.save(user);
        }

        user.setLastLogin(LocalDateTime.now());
        userRepository.save(user);

        // Phase 7: credentials are correct, but 2FA still needs to pass
        // before any session/device is created or a real token is issued.
        if (Boolean.TRUE.equals(user.getTwoFactorEnabled())) {
            twoFactorAuthService.sendLoginChallengeOtp(user);
            String challengeToken = tokenProvider.generateTwoFactorChallengeToken(user.getId());
            throw new com.socialmedia.auth.exception.TwoFactorRequiredException(
                    new com.socialmedia.auth.dto.TwoFactorChallengeResponse(user.getTwoFactorMethod(), challengeToken));
        }

        checkWebSessionConflict(user, request.getDeviceInfo());
        return finishLogin(user, request.getDeviceInfo(), ipAddress);
    }

    /**
     * Post-Phase-10 UX change: previously a WEB login called
     * activeWebSessionService.claimOrReplace() unconditionally inside
     * finishLogin(), silently kicking whichever device already held the
     * account's single active web session with zero warning. Now, BEFORE
     * any device/session row is created, this checks whether logging in
     * would be a genuine takeover (a different device, not just a
     * refreshed tab) and, if so, throws WebSessionConflictException instead
     * of proceeding — caught in AuthController and returned as a 200
     * challenge response, the same "pause and ask" shape as
     * TwoFactorRequiredException. The actual takeover only happens via
     * confirmWebSessionTakeover() below, once the user explicitly confirms.
     * Called by login() and completeTwoFactorLogin(), each right before
     * their own call to finishLogin() — deliberately NOT called from inside
     * finishLogin() itself, since confirmWebSessionTakeover() needs to call
     * straight into finishLogin() without re-triggering this same check
     * (which would otherwise throw again forever, since the conflicting
     * device hasn't been replaced yet at that point).
     */
    private void checkWebSessionConflict(User user, com.socialmedia.auth.dto.DeviceInfoRequest deviceInfo) {
        if (deviceInfo == null || !"WEB".equalsIgnoreCase(deviceInfo.getPlatform())) {
            return;
        }
        activeWebSessionService.findConflictingDevice(user.getId(), deviceInfo.getDeviceId())
                .ifPresent(conflictingDevice -> {
                    String challengeToken = tokenProvider.generateWebSessionConfirmToken(user.getId());
                    throw new com.socialmedia.auth.exception.WebSessionConflictException(
                            new com.socialmedia.auth.dto.WebSessionConflictResponse(
                                    challengeToken,
                                    conflictingDevice.getPlatform(),
                                    conflictingDevice.getOsName(),
                                    conflictingDevice.getBrowserName(),
                                    conflictingDevice.getDeviceModel()));
                });
    }

    /**
     * Phase 7: POST /login/2fa/verify — completes a login that was paused
     * for a 2FA challenge. Validates the short-lived challenge token (must
     * be one from generateTwoFactorChallengeToken, not a real access/
     * refresh token), verifies the OTP against the account's configured
     * method, and only then does exactly what the non-2FA path does:
     * create the device/session and issue real tokens.
     *
     * Post-Phase-10: noRollbackFor(WebSessionConflictException) — this
     * method's own write (verifyLoginChallengeOtp marking the OTP row used)
     * must survive finishLogin() throwing that exception at its very start,
     * same reasoning as TwoFactorRequiredException's own noRollbackFor
     * elsewhere in this class.
     */
    @Transactional(noRollbackFor = com.socialmedia.auth.exception.WebSessionConflictException.class)
    public AuthResponse completeTwoFactorLogin(String challengeToken, String otp, com.socialmedia.auth.dto.DeviceInfoRequest deviceInfo, String ipAddress) {
        if (!tokenProvider.validateToken(challengeToken) || !tokenProvider.isTwoFactorChallengeToken(challengeToken)) {
            throw new AuthApiException(AuthApiException.ErrorCode.OTP_INVALID, "Invalid or expired challenge", HttpStatus.BAD_REQUEST);
        }
        Long userId = tokenProvider.getUserIdFromToken(challengeToken);
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new AuthApiException(AuthApiException.ErrorCode.USER_NOT_FOUND, "User not found", HttpStatus.NOT_FOUND));

        if (!Boolean.TRUE.equals(user.getTwoFactorEnabled())) {
            // 2FA was disabled between challenge issuance and now — the
            // challenge token is stale; the client should just log in again
            // through the normal (now-2FA-free) path instead.
            throw new AuthApiException(AuthApiException.ErrorCode.TWO_FA_NOT_ENABLED,
                    "Two-factor authentication is no longer enabled on this account", HttpStatus.BAD_REQUEST);
        }

        boolean verified = twoFactorAuthService.verifyLoginChallengeOtp(user, otp);
        if (!verified) {
            throw new AuthApiException(AuthApiException.ErrorCode.OTP_INVALID, "Invalid or expired OTP", HttpStatus.BAD_REQUEST);
        }

        checkWebSessionConflict(user, deviceInfo);
        return finishLogin(user, deviceInfo, ipAddress);
    }

    /**
     * Post-Phase-10: POST /login/web-session/confirm — completes a login
     * that was paused by checkWebSessionConflict() (called from either
     * login() or completeTwoFactorLogin()). Validates the short-lived
     * confirm token (must be one from generateWebSessionConfirmToken, not a
     * real access/refresh token — see isWebSessionConfirmToken's own doc
     * comment for why that guard matters), then calls straight into
     * finishLogin() — deliberately bypassing checkWebSessionConflict() this
     * second time, since the user has now explicitly agreed to the
     * takeover and re-checking would just throw the same conflict forever.
     */
    @Transactional
    public AuthResponse confirmWebSessionTakeover(String challengeToken, com.socialmedia.auth.dto.DeviceInfoRequest deviceInfo, String ipAddress) {
        if (!tokenProvider.validateToken(challengeToken) || !tokenProvider.isWebSessionConfirmToken(challengeToken)) {
            throw new AuthApiException(AuthApiException.ErrorCode.OTP_INVALID, "Invalid or expired challenge", HttpStatus.BAD_REQUEST);
        }
        Long userId = tokenProvider.getUserIdFromToken(challengeToken);
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new AuthApiException(AuthApiException.ErrorCode.USER_NOT_FOUND, "User not found", HttpStatus.NOT_FOUND));

        return finishLogin(user, deviceInfo, ipAddress);
    }

    /** Phase 7: resends the login-challenge OTP for an in-progress 2FA login. */
    public void resendTwoFactorLoginOtp(String challengeToken) {
        if (!tokenProvider.validateToken(challengeToken) || !tokenProvider.isTwoFactorChallengeToken(challengeToken)) {
            throw new AuthApiException(AuthApiException.ErrorCode.OTP_INVALID, "Invalid or expired challenge", HttpStatus.BAD_REQUEST);
        }
        Long userId = tokenProvider.getUserIdFromToken(challengeToken);
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new AuthApiException(AuthApiException.ErrorCode.USER_NOT_FOUND, "User not found", HttpStatus.NOT_FOUND));
        twoFactorAuthService.resendLoginChallengeOtp(user);
    }

    /**
     * Everything that happens once a login is actually allowed to complete
     * — device/session creation, single-active-web-session enforcement,
     * token issuance, profile sync. Shared by the normal (no 2FA) path and
     * completeTwoFactorLogin, so both end up with identical session/device
     * behavior; only how they got here differs.
     *
     * Post-Phase-10 UX change: this method itself no longer decides whether
     * a WEB takeover needs confirmation — checkWebSessionConflict() (called
     * by login()/completeTwoFactorLogin() BEFORE they call this method) does
     * that, and confirmWebSessionTakeover() deliberately calls straight into
     * this method WITHOUT that check, since by then the user has already
     * confirmed. Putting the check inside finishLogin() itself was tried
     * first and rejected — confirmWebSessionTakeover() calling finishLogin()
     * would re-detect the same still-present conflict and throw again,
     * an infinite "confirm" loop that never actually logs in.
     * activeWebSessionService.claimOrReplace() below still runs
     * unconditionally on every WEB login exactly as before — it's a genuine
     * takeover only if checkWebSessionConflict() didn't already catch it
     * (i.e., this is a same-device re-login, which was never a conflict).
     */
    private AuthResponse finishLogin(User user, com.socialmedia.auth.dto.DeviceInfoRequest deviceInfo, String ipAddress) {
        var device = deviceSessionService.registerDevice(user.getId(), deviceInfo);
        var session = device == null ? null : deviceSessionService.createSession(user.getId(), device.getId(), ipAddress);
        String sessionToken = session == null ? null : session.getSessionToken();
        Long deviceId = device == null ? null : device.getId();
        if (device != null && session != null && "WEB".equals(device.getPlatform())) {
            activeWebSessionService.claimOrReplace(user.getId(), deviceId, session);
        }

        String accessToken = tokenProvider.generateAccessToken(user.getId(), user.getEmail(), sessionToken, deviceId);
        String refreshToken = tokenProvider.generateRefreshToken(user.getId(), user.getEmail(), sessionToken, deviceId);

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

        AuthResponse response = new AuthResponse(
            accessToken,
            refreshToken,
            user.getId(),
            user.getUsername(),
            user.getEmail(),
            user.getFullName()
        );
        response.setDeviceId(deviceId);
        return response;
    }

    @Transactional
    public void logout(Long userId) {
        logout(userId, null);
    }

    @Transactional
    public void logout(Long userId, String sessionToken) {
        // 1. Revoke this specific session (device/session tracking) so its
        // access token stops working on its next request, not just at
        // natural expiry. Done first and unconditionally — this is the
        // actual security-relevant action or logout, unlike the two
        // best-effort steps below.
        deviceSessionService.revokeSessionByToken(userId, sessionToken, "user_logout");

        // 2. Delete Refresh Token from Redis. Same "Redis optional in
        // local/dev" defensive pattern as storeRefreshToken()/refreshToken()
        // elsewhere in this class — without it, a Redis outage would 500 the
        // whole logout call and step 1 above (already committed in this same
        // @Transactional method) would roll back along with it.
        try {
            redisTemplate.delete("refresh_token:" + userId);
        } catch (Exception e) {
            logger.warn("Skipping refresh token cache delete on logout for user {} (Redis unavailable): {}", userId, e.getMessage());
        }

        // 3. Clear FCM Token from Database to stop notifications to this device for this user
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

        // Not currently called by the client (it only ever uses the access
        // token — see the architecture plan's Q4 discussion), so there's no
        // existing session to re-link here; refreshed tokens carry no "sid".
        String newAccessToken = tokenProvider.generateAccessToken(user.getId(), user.getEmail(), null, null);
        String newRefreshToken = tokenProvider.generateRefreshToken(user.getId(), user.getEmail(), null, null);

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
     * Reset password after OTP verification.
     *
     * SECURITY FIX (found while wiring Phase 8's audit event into this exact
     * method): despite the doc comment above always having claimed "after
     * OTP verification", nothing here ever actually checked one — the
     * endpoint accepted {email, newPassword} alone and reset the password
     * unconditionally, letting anyone take over any account just by knowing
     * its email address. otp is now REQUIRED and verified here before the
     * password is touched.
     */
    @Transactional
    public void resetPasswordWithEmail(String email, String otp, String newPassword) {
        if (otp == null || otp.isBlank()) {
            throw new AuthApiException(AuthApiException.ErrorCode.OTP_INVALID, "otp is required", HttpStatus.BAD_REQUEST);
        }

        User user = userRepository.findByEmail(email)
                .orElseThrow(() -> new RuntimeException("User not found with email: " + email));

        boolean verified = otpService.verifyOtp(email, otp, com.socialmedia.auth.entity.OtpVerification.Purpose.PASSWORD_RESET);
        if (!verified) {
            throw new AuthApiException(AuthApiException.ErrorCode.OTP_INVALID, "Invalid or expired OTP", HttpStatus.BAD_REQUEST);
        }

        user.setPassword(passwordEncoder.encode(newPassword));
        userRepository.save(user);

        // Phase 9: the plain-text sendPasswordChangedEmail() call that used
        // to live here is gone — record() below now sends the HTML security
        // alert itself (SecurityEventService's own doc comment), so keeping
        // both would have emailed the user twice for one password reset.
        securityEventService.record(user.getId(), SecurityEvent.EventType.PASSWORD_CHANGED, null, null, null, null, null);
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
        securityEventService.record(userId, SecurityEvent.EventType.PHONE_CHANGED, null, null, null, null, null);
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
        securityEventService.record(userId, SecurityEvent.EventType.EMAIL_CHANGED, null, null, null, null, null);
    }

    /**
     * Delete user account. HARDENING FIX (Phase 10 audit): the previous
     * entry point took a bare userId with no verification of its own,
     * trusting the caller (AuthController.deleteAccount) to have already
     * checked identity — which it did via {email, password} in an
     * UNAUTHENTICATED request body ("/account" was in SecurityConfig's
     * permitAll list), never checking a Bearer token at all AND never
     * checking whether the account had 2FA enabled. That meant the single
     * most destructive, irreversible action in the entire app - permanent
     * account deletion - could be performed with nothing but a leaked
     * password, completely bypassing 2FA even on an account that enabled
     * it specifically to survive a leaked password. This is the exact same
     * severity class as the two bugs already found and fixed in Phases 7-8
     * (2FA/OTP bypass, unauthenticated password reset).
     *
     * Now requires: a valid Bearer token (userId comes from there, not a
     * client-supplied email - "/account" removed from permitAll), the
     * current password, and - if 2FA is enabled on the account - a valid
     * OTP too, mirroring TwoFactorAuthService.disable()'s own
     * re-authentication bar for a similarly-irreversible action.
     */
    @Transactional
    public void deleteAccount(Long userId, String password, String otp) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new AuthApiException(AuthApiException.ErrorCode.USER_NOT_FOUND, "User not found", HttpStatus.NOT_FOUND));

        if (password == null || !passwordEncoder.matches(password, user.getPassword())) {
            throw new AuthApiException(AuthApiException.ErrorCode.INVALID_PASSWORD, "Incorrect password", HttpStatus.BAD_REQUEST);
        }
        if (Boolean.TRUE.equals(user.getTwoFactorEnabled())) {
            if (otp == null || otp.isBlank()) {
                throw new AuthApiException(AuthApiException.ErrorCode.OTP_INVALID,
                        "Two-factor authentication is enabled on this account - otp is required", HttpStatus.BAD_REQUEST);
            }
            if (!twoFactorAuthService.verifyLoginChallengeOtp(user, otp)) {
                throw new AuthApiException(AuthApiException.ErrorCode.OTP_INVALID, "Invalid or expired OTP", HttpStatus.BAD_REQUEST);
            }
        }

        performAccountDeletion(user);
    }

    private void performAccountDeletion(User user) {
        Long userId = user.getId();
        logger.info("Deleting account for user ID: {}", userId);
        
        // Delete user data from social service
        try {
            socialServiceClient.deleteUserProfile(userId);
            logger.info("Deleted user profile from social service for user ID: {}", userId);
        } catch (Exception e) {
            logger.warn("Failed to delete user profile from social service: {}", e.getMessage());
            // Continue with auth service deletion even if social service fails
        }

        // Recorded before the row is actually gone — security_events.user_id
        // has no FK constraint (a plain audit column, not a relationship), so
        // this row survives the account's deletion, which is the point: a
        // record that account N requested deletion at time T outlives N.
        securityEventService.record(userId, SecurityEvent.EventType.ACCOUNT_DELETED, null, null, null, null, null);

        // Cleanup auth-side dependent rows first.
        // In production, password_reset_tokens.user_id uses NO ACTION and can block user delete.
        passwordResetTokenRepository.deleteByUser(user);

        // Delete user from auth database
        userRepository.delete(user);

        // Clear refresh tokens from Redis. SECURITY/CORRECTNESS FIX (found
        // while testing Phase 8's ACCOUNT_DELETED event): this call was
        // completely unguarded, so a Redis outage 500'd the entire method —
        // rolling back the whole @Transactional deleteAccount(), including
        // the user row deletion and the ACCOUNT_DELETED audit event above,
        // even though both had already "succeeded" up to that point. Same
        // defensive-Redis pattern already used by storeRefreshToken()/
        // logout() elsewhere in this class (Redis is treated as optional in
        // local/dev throughout this codebase — see those methods' own
        // comments).
        try {
            String refreshTokenKey = "refresh_token:" + userId;
            redisTemplate.delete(refreshTokenKey);
        } catch (Exception e) {
            logger.warn("Skipping refresh token cache delete for deleted account {} (Redis unavailable): {}", userId, e.getMessage());
        }

        logger.info("Successfully deleted account for user ID: {}", userId);
    }
}