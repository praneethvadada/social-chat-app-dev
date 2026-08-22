package com.socialmedia.auth.service;

import com.socialmedia.auth.entity.PhoneOtpVerification;
import com.socialmedia.auth.entity.PhoneOtpVerification.Purpose;
import com.socialmedia.auth.exception.AuthApiException;
import com.socialmedia.auth.repository.PhoneOtpVerificationRepository;
import com.socialmedia.auth.service.sms.SmsProvider;
import com.socialmedia.auth.util.PhoneNumberValidator;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.util.ReflectionTestUtils;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class PhoneOtpServiceTest {

    private static final String PHONE = "+919876543210";

    @Mock private PhoneOtpVerificationRepository otpRepository;
    @Mock private SmsProvider smsProvider;
    @Mock private PasswordEncoder passwordEncoder;
    @Mock private PhoneNumberValidator phoneNumberValidator;

    private PhoneOtpService service;

    @BeforeEach
    void setUp() {
        service = new PhoneOtpService(otpRepository, smsProvider, passwordEncoder, phoneNumberValidator);
        ReflectionTestUtils.setField(service, "otpLength", 6);
        ReflectionTestUtils.setField(service, "otpExpirySeconds", 300L);
        ReflectionTestUtils.setField(service, "otpMaxAttempts", 5);
        ReflectionTestUtils.setField(service, "resendCooldownSeconds", 60L);
        ReflectionTestUtils.setField(service, "maxRequestsPerHour", 5);
        ReflectionTestUtils.setField(service, "verificationProofValidityMinutes", 30L);
    }

    @Test
    void sendOtp_generatesSixDigitCode_hashesIt_andDispatchesViaSmsProvider() {
        when(otpRepository.countByPhoneNumberAndPurposeAndCreatedAtAfter(eq(PHONE), eq("PHONE_SIGNUP"), any())).thenReturn(0L);
        when(otpRepository.findTopByPhoneNumberAndPurposeOrderByCreatedAtDesc(PHONE, "PHONE_SIGNUP")).thenReturn(Optional.empty());
        when(passwordEncoder.encode(anyString())).thenReturn("hashed");

        service.sendOtp(PHONE, Purpose.PHONE_SIGNUP);

        ArgumentCaptor<String> otpCaptor = ArgumentCaptor.forClass(String.class);
        verify(smsProvider).sendOtp(eq(PHONE), otpCaptor.capture());
        String otp = otpCaptor.getValue();
        assertEquals(6, otp.length());
        assertTrue(otp.chars().allMatch(Character::isDigit));

        verify(passwordEncoder).encode(otp); // stored value is hashed, not plaintext
        ArgumentCaptor<PhoneOtpVerification> savedCaptor = ArgumentCaptor.forClass(PhoneOtpVerification.class);
        verify(otpRepository).save(savedCaptor.capture());
        assertEquals("hashed", savedCaptor.getValue().getOtpHash());
    }

    @Test
    void sendOtp_blocksWhenHourlyRateLimitExceeded() {
        when(otpRepository.countByPhoneNumberAndPurposeAndCreatedAtAfter(eq(PHONE), eq("PHONE_SIGNUP"), any())).thenReturn(5L);

        AuthApiException ex = assertThrows(AuthApiException.class, () -> service.sendOtp(PHONE, Purpose.PHONE_SIGNUP));
        assertEquals(AuthApiException.ErrorCode.OTP_RATE_LIMIT_EXCEEDED, ex.getErrorCode());
        verify(smsProvider, never()).sendOtp(anyString(), anyString());
    }

    @Test
    void sendOtp_blocksWithinResendCooldown() {
        when(otpRepository.countByPhoneNumberAndPurposeAndCreatedAtAfter(eq(PHONE), eq("PHONE_SIGNUP"), any())).thenReturn(0L);
        PhoneOtpVerification recent = new PhoneOtpVerification(PHONE, "hash", Purpose.PHONE_SIGNUP, LocalDateTime.now().plusMinutes(5), 5);
        when(otpRepository.findTopByPhoneNumberAndPurposeOrderByCreatedAtDesc(PHONE, "PHONE_SIGNUP")).thenReturn(Optional.of(recent));

        AuthApiException ex = assertThrows(AuthApiException.class, () -> service.sendOtp(PHONE, Purpose.PHONE_SIGNUP));
        assertEquals(AuthApiException.ErrorCode.OTP_RESEND_TOO_SOON, ex.getErrorCode());
        verify(smsProvider, never()).sendOtp(anyString(), anyString());
    }

    @Test
    void verifyOtp_succeedsWithCorrectCode_andMarksVerifiedExactlyOnce() {
        PhoneOtpVerification row = new PhoneOtpVerification(PHONE, "hashedOtp", Purpose.PHONE_SIGNUP, LocalDateTime.now().plusMinutes(5), 5);
        when(otpRepository.lockLatestByPhoneAndPurpose(PHONE, "PHONE_SIGNUP")).thenReturn(List.of(row));
        when(passwordEncoder.matches("482913", "hashedOtp")).thenReturn(true);

        boolean result = service.verifyOtp(PHONE, "482913", Purpose.PHONE_SIGNUP);

        assertTrue(result);
        assertTrue(row.isVerified());
        verify(otpRepository).save(row);
    }

    @Test
    void verifyOtp_rejectsWrongCode_andIncrementsAttemptCount() {
        PhoneOtpVerification row = new PhoneOtpVerification(PHONE, "hashedOtp", Purpose.PHONE_SIGNUP, LocalDateTime.now().plusMinutes(5), 5);
        when(otpRepository.lockLatestByPhoneAndPurpose(PHONE, "PHONE_SIGNUP")).thenReturn(List.of(row));
        when(passwordEncoder.matches("000000", "hashedOtp")).thenReturn(false);

        AuthApiException ex = assertThrows(AuthApiException.class, () -> service.verifyOtp(PHONE, "000000", Purpose.PHONE_SIGNUP));
        assertEquals(AuthApiException.ErrorCode.OTP_INVALID, ex.getErrorCode());
        assertEquals(1, row.getAttemptCount());
        assertFalse(row.isVerified());
    }

    @Test
    void verifyOtp_rejectsExpiredOtp() {
        PhoneOtpVerification row = new PhoneOtpVerification(PHONE, "hashedOtp", Purpose.PHONE_SIGNUP, LocalDateTime.now().minusMinutes(1), 5);
        when(otpRepository.lockLatestByPhoneAndPurpose(PHONE, "PHONE_SIGNUP")).thenReturn(List.of(row));

        AuthApiException ex = assertThrows(AuthApiException.class, () -> service.verifyOtp(PHONE, "482913", Purpose.PHONE_SIGNUP));
        assertEquals(AuthApiException.ErrorCode.OTP_EXPIRED, ex.getErrorCode());
    }

    @Test
    void verifyOtp_rejectsAfterMaxAttemptsExhausted() {
        PhoneOtpVerification row = new PhoneOtpVerification(PHONE, "hashedOtp", Purpose.PHONE_SIGNUP, LocalDateTime.now().plusMinutes(5), 5);
        row.setAttemptCount(5);
        when(otpRepository.lockLatestByPhoneAndPurpose(PHONE, "PHONE_SIGNUP")).thenReturn(List.of(row));

        AuthApiException ex = assertThrows(AuthApiException.class, () -> service.verifyOtp(PHONE, "482913", Purpose.PHONE_SIGNUP));
        assertEquals(AuthApiException.ErrorCode.OTP_MAX_ATTEMPTS, ex.getErrorCode());
        // Never even checked the code once attempts are exhausted.
        verify(passwordEncoder, never()).matches(anyString(), anyString());
    }

    @Test
    void verifyOtp_rejectsReplayOfAlreadyVerifiedOtp() {
        PhoneOtpVerification row = new PhoneOtpVerification(PHONE, "hashedOtp", Purpose.PHONE_SIGNUP, LocalDateTime.now().plusMinutes(5), 5);
        row.setVerifiedAt(LocalDateTime.now().minusSeconds(5)); // already consumed by an earlier request
        when(otpRepository.lockLatestByPhoneAndPurpose(PHONE, "PHONE_SIGNUP")).thenReturn(List.of(row));

        AuthApiException ex = assertThrows(AuthApiException.class, () -> service.verifyOtp(PHONE, "482913", Purpose.PHONE_SIGNUP));
        assertEquals(AuthApiException.ErrorCode.OTP_INVALID, ex.getErrorCode());
    }

    @Test
    void verifyOtp_purposeIsolation_signupOtpRowNotFoundUnderVerificationPurpose() {
        // The repository query itself is purpose-scoped — a PHONE_SIGNUP OTP
        // simply doesn't exist under a PHONE_VERIFICATION lookup.
        when(otpRepository.lockLatestByPhoneAndPurpose(PHONE, "PHONE_VERIFICATION")).thenReturn(List.of());

        AuthApiException ex = assertThrows(AuthApiException.class,
                () -> service.verifyOtp(PHONE, "482913", Purpose.PHONE_VERIFICATION));
        assertEquals(AuthApiException.ErrorCode.OTP_INVALID, ex.getErrorCode());
    }

    @Test
    void hasRecentVerification_trueOnlyWithinValidityWindow() {
        PhoneOtpVerification recent = new PhoneOtpVerification(PHONE, "h", Purpose.PHONE_SIGNUP, LocalDateTime.now().plusMinutes(5), 5);
        recent.setVerifiedAt(LocalDateTime.now().minusMinutes(10));
        when(otpRepository.findTopByPhoneNumberAndPurposeAndVerifiedAtIsNotNullOrderByVerifiedAtDesc(PHONE, "PHONE_SIGNUP"))
                .thenReturn(Optional.of(recent));

        assertTrue(service.hasRecentVerification(PHONE, Purpose.PHONE_SIGNUP));
    }

    @Test
    void hasRecentVerification_falseWhenNoVerificationExists() {
        when(otpRepository.findTopByPhoneNumberAndPurposeAndVerifiedAtIsNotNullOrderByVerifiedAtDesc(PHONE, "PHONE_SIGNUP"))
                .thenReturn(Optional.empty());

        assertFalse(service.hasRecentVerification(PHONE, Purpose.PHONE_SIGNUP));
    }

    @Test
    void resendOtp_requiresAPriorOtpRequest() {
        when(otpRepository.findTopByPhoneNumberAndPurposeOrderByCreatedAtDesc(PHONE, "PHONE_SIGNUP")).thenReturn(Optional.empty());

        assertThrows(AuthApiException.class, () -> service.resendOtp(PHONE, Purpose.PHONE_SIGNUP));
    }
}
