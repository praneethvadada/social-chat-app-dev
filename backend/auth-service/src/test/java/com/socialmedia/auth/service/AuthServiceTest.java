package com.socialmedia.auth.service;

import com.socialmedia.auth.client.SocialServiceClient;
import com.socialmedia.auth.dto.AuthResponse;
import com.socialmedia.auth.dto.LoginRequest;
import com.socialmedia.auth.dto.RegisterRequest;
import com.socialmedia.auth.entity.PhoneOtpVerification.Purpose;
import com.socialmedia.auth.entity.User;
import com.socialmedia.auth.exception.AuthApiException;
import com.socialmedia.auth.repository.PasswordResetTokenRepository;
import com.socialmedia.auth.repository.UserRepository;
import com.socialmedia.auth.security.JwtTokenProvider;
import com.socialmedia.auth.service.IdentifierResolver.IdentifierType;
import com.socialmedia.auth.util.PhoneNumberValidator;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.redis.core.RedisTemplate;
import org.springframework.security.authentication.BadCredentialsException;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class AuthServiceTest {

    private static final String EMAIL = "user@example.com";
    private static final String PHONE = "+919876543210";

    @Mock private UserRepository userRepository;
    @Mock private PasswordEncoder passwordEncoder;
    @Mock private JwtTokenProvider tokenProvider;
    @Mock private RedisTemplate<String, Object> redisTemplate;
    @Mock private EmailService emailService;
    @Mock private PasswordResetTokenRepository passwordResetTokenRepository;
    @Mock private SocialServiceClient socialServiceClient;
    @Mock private OtpService otpService;
    @Mock private PhoneOtpService phoneOtpService;
    @Mock private PhoneNumberValidator phoneNumberValidator;
    @Mock private IdentifierResolver identifierResolver;
    @Mock private DeviceSessionService deviceSessionService;
    @Mock private ActiveWebSessionService activeWebSessionService;
    @Mock private TwoFactorAuthService twoFactorAuthService;
    @Mock private SecurityEventService securityEventService;

    private AuthService authService;

    @BeforeEach
    void setUp() {
        authService = new AuthService(userRepository, passwordEncoder, tokenProvider, redisTemplate,
                emailService, passwordResetTokenRepository, socialServiceClient, otpService,
                phoneOtpService, phoneNumberValidator, identifierResolver, deviceSessionService,
                activeWebSessionService, twoFactorAuthService, securityEventService);
        // storeRefreshToken() defensively swallows Redis errors; leaving
        // opsForValue() unstubbed (returns null) exercises that same path
        // real local/dev traffic takes today, matching production behavior.
        // deviceSessionService.registerDevice(...) is left unstubbed too —
        // every test here builds a bare Register/LoginRequest with no
        // deviceInfo, so it returns null (Mockito's default), which
        // short-circuits session creation (and therefore
        // activeWebSessionService.claimOrReplace, which is never reached)
        // exactly like a real not-yet-updated client would hit in
        // AuthService. twoFactorAuthService is likewise never invoked here
        // — every mocked User defaults to twoFactorEnabled=null/false; see
        // AuthServiceTwoFactorLoginTest for the 2FA-enabled login path.
        lenient().when(tokenProvider.generateAccessToken(any(), any(), any(), any())).thenReturn("access-token");
        lenient().when(tokenProvider.generateRefreshToken(any(), any(), any(), any())).thenReturn("refresh-token");
    }

    private RegisterRequest baseRequest() {
        RegisterRequest r = new RegisterRequest();
        r.setUsername("praneeth");
        r.setPassword("Password@123");
        r.setFullName("Praneeth Vadada");
        return r;
    }

    // ---- register() ----

    @Test
    void register_emailPath_succeedsWhenEmailWasRecentlyVerified() {
        RegisterRequest request = baseRequest();
        request.setEmail(EMAIL);
        when(userRepository.existsByUsername("praneeth")).thenReturn(false);
        when(userRepository.existsByEmail(EMAIL)).thenReturn(false);
        when(otpService.hasRecentVerification(EMAIL, com.socialmedia.auth.entity.OtpVerification.Purpose.EMAIL_VERIFICATION)).thenReturn(true);
        when(passwordEncoder.encode(anyString())).thenReturn("hashed");
        when(userRepository.save(any(User.class))).thenAnswer(inv -> {
            User u = inv.getArgument(0);
            u.setId(1L);
            return u;
        });

        AuthResponse response = authService.register(request);

        assertEquals("access-token", response.getAccessToken());
        assertEquals(EMAIL, response.getEmail());
        verify(userRepository).save(argThatEmailVerifiedTrue());
    }

    @Test
    void register_phonePath_succeedsWhenPhoneWasRecentlyVerified() {
        RegisterRequest request = baseRequest();
        request.setPhoneNumber("+91 98765 43210");
        when(userRepository.existsByUsername("praneeth")).thenReturn(false);
        when(phoneNumberValidator.normalize("+91 98765 43210")).thenReturn(PHONE);
        when(userRepository.existsByPhoneNumber(PHONE)).thenReturn(false);
        when(phoneOtpService.hasRecentVerification(PHONE, Purpose.PHONE_SIGNUP)).thenReturn(true);
        when(passwordEncoder.encode(anyString())).thenReturn("hashed");
        when(userRepository.save(any(User.class))).thenAnswer(inv -> {
            User u = inv.getArgument(0);
            u.setId(2L);
            return u;
        });

        AuthResponse response = authService.register(request);

        assertEquals("access-token", response.getAccessToken());
        verify(emailService, never()).sendWelcomeEmail(anyString(), anyString()); // no email on this account
    }

    @Test
    void register_rejectsWhenBothEmailAndPhoneProvided() {
        RegisterRequest request = baseRequest();
        request.setEmail(EMAIL);
        request.setPhoneNumber(PHONE);
        when(userRepository.existsByUsername("praneeth")).thenReturn(false);

        AuthApiException ex = assertThrows(AuthApiException.class, () -> authService.register(request));
        assertEquals(AuthApiException.ErrorCode.INVALID_SIGNUP_IDENTIFIER, ex.getErrorCode());
    }

    @Test
    void register_rejectsWhenNeitherEmailNorPhoneProvided() {
        RegisterRequest request = baseRequest();
        when(userRepository.existsByUsername("praneeth")).thenReturn(false);

        AuthApiException ex = assertThrows(AuthApiException.class, () -> authService.register(request));
        assertEquals(AuthApiException.ErrorCode.INVALID_SIGNUP_IDENTIFIER, ex.getErrorCode());
    }

    @Test
    void register_rejectsDuplicateUsername() {
        RegisterRequest request = baseRequest();
        request.setEmail(EMAIL);
        when(userRepository.existsByUsername("praneeth")).thenReturn(true);

        RuntimeException ex = assertThrows(RuntimeException.class, () -> authService.register(request));
        assertTrue(ex.getMessage().contains("Username already exists"));
    }

    @Test
    void register_rejectsDuplicateEmail() {
        RegisterRequest request = baseRequest();
        request.setEmail(EMAIL);
        when(userRepository.existsByUsername("praneeth")).thenReturn(false);
        when(userRepository.existsByEmail(EMAIL)).thenReturn(true);

        assertThrows(RuntimeException.class, () -> authService.register(request));
    }

    @Test
    void register_rejectsDuplicatePhone() {
        RegisterRequest request = baseRequest();
        request.setPhoneNumber(PHONE);
        when(userRepository.existsByUsername("praneeth")).thenReturn(false);
        when(phoneNumberValidator.normalize(PHONE)).thenReturn(PHONE);
        when(userRepository.existsByPhoneNumber(PHONE)).thenReturn(true);

        AuthApiException ex = assertThrows(AuthApiException.class, () -> authService.register(request));
        assertEquals(AuthApiException.ErrorCode.PHONE_ALREADY_EXISTS, ex.getErrorCode());
    }

    @Test
    void register_rejectsInvalidPhoneNumber() {
        RegisterRequest request = baseRequest();
        request.setPhoneNumber("not-a-number");
        when(userRepository.existsByUsername("praneeth")).thenReturn(false);
        when(phoneNumberValidator.normalize("not-a-number")).thenThrow(new IllegalArgumentException("Invalid phone number"));

        AuthApiException ex = assertThrows(AuthApiException.class, () -> authService.register(request));
        assertEquals(AuthApiException.ErrorCode.INVALID_PHONE_NUMBER, ex.getErrorCode());
    }

    @Test
    void register_rejectsUnverifiedEmail() {
        RegisterRequest request = baseRequest();
        request.setEmail(EMAIL);
        when(userRepository.existsByUsername("praneeth")).thenReturn(false);
        when(userRepository.existsByEmail(EMAIL)).thenReturn(false);
        when(otpService.hasRecentVerification(EMAIL, com.socialmedia.auth.entity.OtpVerification.Purpose.EMAIL_VERIFICATION)).thenReturn(false);

        AuthApiException ex = assertThrows(AuthApiException.class, () -> authService.register(request));
        assertEquals(AuthApiException.ErrorCode.VERIFICATION_REQUIRED, ex.getErrorCode());
    }

    @Test
    void register_rejectsUnverifiedPhone() {
        RegisterRequest request = baseRequest();
        request.setPhoneNumber(PHONE);
        when(userRepository.existsByUsername("praneeth")).thenReturn(false);
        when(phoneNumberValidator.normalize(PHONE)).thenReturn(PHONE);
        when(userRepository.existsByPhoneNumber(PHONE)).thenReturn(false);
        when(phoneOtpService.hasRecentVerification(PHONE, Purpose.PHONE_SIGNUP)).thenReturn(false);

        AuthApiException ex = assertThrows(AuthApiException.class, () -> authService.register(request));
        assertEquals(AuthApiException.ErrorCode.VERIFICATION_REQUIRED, ex.getErrorCode());
    }

    // ---- login() ----

    @Test
    void login_viaIdentifier_resolvesVerifiedEmailAndSucceeds() {
        User user = verifiedEmailUser();
        LoginRequest request = identifierLogin(EMAIL, "Password@123");
        when(identifierResolver.resolve(EMAIL)).thenReturn(IdentifierType.EMAIL);
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.of(user));
        when(passwordEncoder.matches("Password@123", "hashed")).thenReturn(true);

        AuthResponse response = authService.login(request);

        assertEquals("access-token", response.getAccessToken());
    }

    @Test
    void login_viaIdentifier_resolvesVerifiedPhoneAndSucceeds() {
        User user = verifiedPhoneUser();
        LoginRequest request = identifierLogin(PHONE, "Password@123");
        when(identifierResolver.resolve(PHONE)).thenReturn(IdentifierType.PHONE);
        when(phoneNumberValidator.normalize(PHONE)).thenReturn(PHONE);
        when(userRepository.findByPhoneNumber(PHONE)).thenReturn(Optional.of(user));
        when(passwordEncoder.matches("Password@123", "hashed")).thenReturn(true);

        AuthResponse response = authService.login(request);

        assertEquals("access-token", response.getAccessToken());
    }

    @Test
    void login_viaIdentifier_rejectsUnverifiedEmail() {
        User user = verifiedEmailUser();
        user.setEmailVerified(false);
        LoginRequest request = identifierLogin(EMAIL, "Password@123");
        when(identifierResolver.resolve(EMAIL)).thenReturn(IdentifierType.EMAIL);
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.of(user));

        AuthApiException ex = assertThrows(AuthApiException.class, () -> authService.login(request));
        assertEquals(AuthApiException.ErrorCode.EMAIL_NOT_VERIFIED, ex.getErrorCode());
        // Must fail before ever checking the password.
        verify(passwordEncoder, never()).matches(anyString(), anyString());
    }

    @Test
    void login_viaIdentifier_rejectsUnverifiedPhone() {
        User user = verifiedPhoneUser();
        user.setPhoneVerified(false);
        LoginRequest request = identifierLogin(PHONE, "Password@123");
        when(identifierResolver.resolve(PHONE)).thenReturn(IdentifierType.PHONE);
        when(phoneNumberValidator.normalize(PHONE)).thenReturn(PHONE);
        when(userRepository.findByPhoneNumber(PHONE)).thenReturn(Optional.of(user));

        AuthApiException ex = assertThrows(AuthApiException.class, () -> authService.login(request));
        assertEquals(AuthApiException.ErrorCode.PHONE_NOT_VERIFIED, ex.getErrorCode());
    }

    @Test
    void login_identifierNotFound_fallsBackToGenericInvalidCredentials_noEnumeration() {
        LoginRequest request = identifierLogin("nobody@example.com", "whatever");
        when(identifierResolver.resolve("nobody@example.com")).thenReturn(IdentifierType.EMAIL);
        when(userRepository.findByEmail("nobody@example.com")).thenReturn(Optional.empty());

        BadCredentialsException ex = assertThrows(BadCredentialsException.class, () -> authService.login(request));
        assertEquals("Invalid credentials", ex.getMessage());
    }

    @Test
    void login_existingEmailPath_stillWorksUnchanged_regression() {
        User user = verifiedEmailUser();
        LoginRequest request = new LoginRequest();
        request.setEmail(EMAIL);
        request.setPassword("Password@123");
        // identifier is null -> must take the pre-existing branch entirely,
        // identifierResolver must never even be consulted.
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.of(user));
        when(passwordEncoder.matches("Password@123", "hashed")).thenReturn(true);

        AuthResponse response = authService.login(request);

        assertEquals("access-token", response.getAccessToken());
        verify(identifierResolver, never()).resolve(anyString());
    }

    @Test
    void login_existingUsernamePath_stillWorksUnchanged_regression() {
        User user = verifiedEmailUser();
        user.setUsername("praneeth");
        LoginRequest request = new LoginRequest();
        request.setUsername("praneeth");
        request.setPassword("Password@123");
        when(userRepository.findByUsername("praneeth")).thenReturn(Optional.of(user));
        when(passwordEncoder.matches("Password@123", "hashed")).thenReturn(true);

        AuthResponse response = authService.login(request);

        assertEquals("access-token", response.getAccessToken());
        verify(identifierResolver, never()).resolve(anyString());
    }

    @Test
    void login_wrongPassword_incrementsFailedAttempts_evenViaIdentifierPath() {
        User user = verifiedEmailUser();
        user.setFailedLoginAttempts(0);
        LoginRequest request = identifierLogin(EMAIL, "wrong-password");
        when(identifierResolver.resolve(EMAIL)).thenReturn(IdentifierType.EMAIL);
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.of(user));
        when(passwordEncoder.matches("wrong-password", "hashed")).thenReturn(false);

        assertThrows(BadCredentialsException.class, () -> authService.login(request));
        assertEquals(1, user.getFailedLoginAttempts());
    }

    // ---- helpers ----

    private LoginRequest identifierLogin(String identifier, String password) {
        LoginRequest r = new LoginRequest();
        r.setIdentifier(identifier);
        r.setPassword(password);
        return r;
    }

    private User verifiedEmailUser() {
        User u = new User();
        u.setId(1L);
        u.setUsername("praneeth");
        u.setEmail(EMAIL);
        u.setPassword("hashed");
        u.setEmailVerified(true);
        u.setAccountNonLocked(true);
        u.setFailedLoginAttempts(0);
        return u;
    }

    private User verifiedPhoneUser() {
        User u = new User();
        u.setId(2L);
        u.setUsername("phoneuser");
        u.setPhoneNumber(PHONE);
        u.setPassword("hashed");
        u.setPhoneVerified(true);
        u.setAccountNonLocked(true);
        u.setFailedLoginAttempts(0);
        return u;
    }

    private User argThatEmailVerifiedTrue() {
        return org.mockito.ArgumentMatchers.argThat(u -> Boolean.TRUE.equals(u.getEmailVerified()));
    }
}
