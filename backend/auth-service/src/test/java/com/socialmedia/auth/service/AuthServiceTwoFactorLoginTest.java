package com.socialmedia.auth.service;

import com.socialmedia.auth.client.SocialServiceClient;
import com.socialmedia.auth.dto.AuthResponse;
import com.socialmedia.auth.dto.LoginRequest;
import com.socialmedia.auth.dto.TwoFactorChallengeResponse;
import com.socialmedia.auth.entity.User;
import com.socialmedia.auth.exception.AuthApiException;
import com.socialmedia.auth.exception.TwoFactorRequiredException;
import com.socialmedia.auth.repository.PasswordResetTokenRepository;
import com.socialmedia.auth.repository.UserRepository;
import com.socialmedia.auth.security.JwtTokenProvider;
import com.socialmedia.auth.util.PhoneNumberValidator;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.data.redis.core.RedisTemplate;

import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.lenient;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Phase 7: the 2FA login-challenge branch of AuthService.login()/
 * completeTwoFactorLogin(), separate from AuthServiceTest so the much
 * larger non-2FA suite there doesn't need every one of these mocks.
 */
@ExtendWith(MockitoExtension.class)
class AuthServiceTwoFactorLoginTest {

    private static final String EMAIL = "twofactor@example.com";
    private static final Long USER_ID = 42L;
    private static final String CHALLENGE_TOKEN = "challenge-token";

    @Mock private UserRepository userRepository;
    @Mock private org.springframework.security.crypto.password.PasswordEncoder passwordEncoder;
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
    }

    private User twoFactorEnabledUser() {
        User u = new User();
        u.setId(USER_ID);
        u.setUsername("twofactoruser");
        u.setEmail(EMAIL);
        u.setPassword("hashed");
        u.setEmailVerified(true);
        u.setAccountNonLocked(true);
        u.setFailedLoginAttempts(0);
        u.setTwoFactorEnabled(true);
        u.setTwoFactorMethod("EMAIL");
        return u;
    }

    private LoginRequest loginRequest() {
        LoginRequest r = new LoginRequest();
        r.setEmail(EMAIL);
        r.setPassword("Password@123");
        return r;
    }

    @Test
    void login_with2faEnabled_sendsChallengeOtpAndThrowsInsteadOfIssuingTokens() {
        User user = twoFactorEnabledUser();
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.of(user));
        when(passwordEncoder.matches("Password@123", "hashed")).thenReturn(true);
        when(tokenProvider.generateTwoFactorChallengeToken(USER_ID)).thenReturn(CHALLENGE_TOKEN);

        TwoFactorRequiredException ex = assertThrows(TwoFactorRequiredException.class,
                () -> authService.login(loginRequest()));

        assertEquals("EMAIL", ex.getChallenge().getMethod());
        assertEquals(CHALLENGE_TOKEN, ex.getChallenge().getChallengeToken());
        verify(twoFactorAuthService).sendLoginChallengeOtp(user);
        // No session/device/real token must be created before the OTP step passes.
        verify(deviceSessionService, never()).registerDevice(any(), any());
        verify(tokenProvider, never()).generateAccessToken(any(), any(), any(), any());
    }

    @Test
    void completeTwoFactorLogin_validOtp_finishesLoginAndIssuesRealTokens() {
        User user = twoFactorEnabledUser();
        when(tokenProvider.validateToken(CHALLENGE_TOKEN)).thenReturn(true);
        when(tokenProvider.isTwoFactorChallengeToken(CHALLENGE_TOKEN)).thenReturn(true);
        when(tokenProvider.getUserIdFromToken(CHALLENGE_TOKEN)).thenReturn(USER_ID);
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user));
        when(twoFactorAuthService.verifyLoginChallengeOtp(user, "123456")).thenReturn(true);
        when(tokenProvider.generateAccessToken(any(), any(), any(), any())).thenReturn("access-token");
        when(tokenProvider.generateRefreshToken(any(), any(), any(), any())).thenReturn("refresh-token");
        // No deviceInfo passed -> registerDevice returns null (Mockito default),
        // short-circuiting session creation, matching AuthServiceTest's own
        // convention for the plain "no device info" case.

        AuthResponse response = authService.completeTwoFactorLogin(CHALLENGE_TOKEN, "123456", null, null);

        assertEquals("access-token", response.getAccessToken());
        assertEquals(USER_ID, response.getUserId());
    }

    @Test
    void completeTwoFactorLogin_wrongOtp_throwsOtpInvalid() {
        User user = twoFactorEnabledUser();
        when(tokenProvider.validateToken(CHALLENGE_TOKEN)).thenReturn(true);
        when(tokenProvider.isTwoFactorChallengeToken(CHALLENGE_TOKEN)).thenReturn(true);
        when(tokenProvider.getUserIdFromToken(CHALLENGE_TOKEN)).thenReturn(USER_ID);
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user));
        when(twoFactorAuthService.verifyLoginChallengeOtp(user, "000000")).thenReturn(false);

        AuthApiException ex = assertThrows(AuthApiException.class,
                () -> authService.completeTwoFactorLogin(CHALLENGE_TOKEN, "000000", null, null));

        assertEquals(AuthApiException.ErrorCode.OTP_INVALID, ex.getErrorCode());
        verify(tokenProvider, never()).generateAccessToken(any(), any(), any(), any());
    }

    @Test
    void completeTwoFactorLogin_notAChallengeToken_rejectedEvenIfOtherwiseValid() {
        // A real access/refresh token (or any token without the 2fa_challenge
        // purpose claim) must never be usable here — see JwtTokenProvider's
        // own doc comment on isTwoFactorChallengeToken for why this matters.
        when(tokenProvider.validateToken("real-access-token")).thenReturn(true);
        when(tokenProvider.isTwoFactorChallengeToken("real-access-token")).thenReturn(false);

        AuthApiException ex = assertThrows(AuthApiException.class,
                () -> authService.completeTwoFactorLogin("real-access-token", "123456", null, null));

        assertEquals(AuthApiException.ErrorCode.OTP_INVALID, ex.getErrorCode());
        verify(userRepository, never()).findById(any());
    }

    @Test
    void completeTwoFactorLogin_2faDisabledSinceChallengeWasIssued_rejected() {
        User user = twoFactorEnabledUser();
        user.setTwoFactorEnabled(false);
        user.setTwoFactorMethod(null);
        when(tokenProvider.validateToken(CHALLENGE_TOKEN)).thenReturn(true);
        when(tokenProvider.isTwoFactorChallengeToken(CHALLENGE_TOKEN)).thenReturn(true);
        when(tokenProvider.getUserIdFromToken(CHALLENGE_TOKEN)).thenReturn(USER_ID);
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user));

        AuthApiException ex = assertThrows(AuthApiException.class,
                () -> authService.completeTwoFactorLogin(CHALLENGE_TOKEN, "123456", null, null));

        assertEquals(AuthApiException.ErrorCode.TWO_FA_NOT_ENABLED, ex.getErrorCode());
        verify(twoFactorAuthService, never()).verifyLoginChallengeOtp(any(), any());
    }
}
