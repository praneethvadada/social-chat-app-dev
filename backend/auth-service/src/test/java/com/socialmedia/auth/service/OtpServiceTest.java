package com.socialmedia.auth.service;

import com.socialmedia.auth.entity.OtpVerification;
import com.socialmedia.auth.entity.OtpVerification.Purpose;
import com.socialmedia.auth.repository.OtpVerificationRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.time.LocalDateTime;
import java.util.Optional;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * Uses a real BCryptPasswordEncoder (not mocked) so these tests exercise the
 * actual hash/compare round trip, not just that the right methods were
 * called — the whole point of this test class is verifying the OTP is
 * genuinely hashed (not stored/compared as plaintext) and that generation
 * is cryptographically random per call. Phase 6: OtpService is purpose-
 * keyed (see OtpVerification's own doc comment) — these tests all use
 * EMAIL_VERIFICATION since which purpose is used doesn't matter to what
 * they're actually testing (hashing, expiry, used-once, rate behavior).
 */
@ExtendWith(MockitoExtension.class)
class OtpServiceTest {

    private static final String EMAIL = "user@example.com";
    private static final Purpose PURPOSE = Purpose.EMAIL_VERIFICATION;

    @Mock private OtpVerificationRepository otpRepository;
    @Mock private EmailService emailService;

    private final PasswordEncoder passwordEncoder = new BCryptPasswordEncoder();
    private OtpService service;

    @BeforeEach
    void setUp() {
        service = new OtpService(otpRepository, emailService, passwordEncoder);
    }

    @Test
    void sendOtp_storesAHashNotThePlaintextCode() {
        when(otpRepository.findByEmailAndPurpose(EMAIL, PURPOSE.name())).thenReturn(Optional.empty());

        service.sendOtp(EMAIL, PURPOSE);

        ArgumentCaptor<String> sentOtpCaptor = ArgumentCaptor.forClass(String.class);
        verify(emailService).sendOtpEmail(eq(EMAIL), sentOtpCaptor.capture());
        String plaintextOtp = sentOtpCaptor.getValue();
        assertEquals(4, plaintextOtp.length());
        assertTrue(plaintextOtp.chars().allMatch(Character::isDigit));

        ArgumentCaptor<OtpVerification> savedCaptor = ArgumentCaptor.forClass(OtpVerification.class);
        verify(otpRepository).save(savedCaptor.capture());
        String storedHash = savedCaptor.getValue().getOtpHash();

        assertNotEquals(plaintextOtp, storedHash); // never the raw code
        assertTrue(passwordEncoder.matches(plaintextOtp, storedHash)); // but a valid hash of it
    }

    @Test
    void sendOtp_generatesADifferentCodeEachTime() {
        when(otpRepository.findByEmailAndPurpose(EMAIL, PURPOSE.name())).thenReturn(Optional.empty());

        ArgumentCaptor<String> captor = ArgumentCaptor.forClass(String.class);
        service.sendOtp(EMAIL, PURPOSE);
        service.sendOtp(EMAIL, PURPOSE);
        verify(emailService, org.mockito.Mockito.times(2)).sendOtpEmail(eq(EMAIL), captor.capture());

        // Not a strict guarantee (4-digit space is small), but with a real
        // SecureRandom two consecutive calls landing on the exact same code
        // out of 9000 possibilities is vanishingly unlikely — a stale/fixed
        // seed bug would make this fail reliably.
        assertNotEquals(captor.getAllValues().get(0), captor.getAllValues().get(1));
    }

    @Test
    void verifyOtp_succeedsWithCorrectCode() {
        String realOtp = "482913".substring(0, 4);
        String hash = passwordEncoder.encode(realOtp);
        OtpVerification row = new OtpVerification(EMAIL, PURPOSE.name(), hash, LocalDateTime.now().plusMinutes(10));
        when(otpRepository.findByEmailAndPurpose(EMAIL, PURPOSE.name())).thenReturn(Optional.of(row));

        boolean result = service.verifyOtp(EMAIL, realOtp, PURPOSE);

        assertTrue(result);
        assertTrue(row.getIsUsed());
        org.junit.jupiter.api.Assertions.assertNotNull(row.getVerifiedAt());
        verify(otpRepository).save(row);
    }

    @Test
    void verifyOtp_rejectsWrongCode_comparingHashesNotPlaintext() {
        String hash = passwordEncoder.encode("1234");
        OtpVerification row = new OtpVerification(EMAIL, PURPOSE.name(), hash, LocalDateTime.now().plusMinutes(10));
        when(otpRepository.findByEmailAndPurpose(EMAIL, PURPOSE.name())).thenReturn(Optional.of(row));

        boolean result = service.verifyOtp(EMAIL, "9999", PURPOSE);

        assertFalse(result);
        assertFalse(row.getIsUsed());
        // Phase 10 hardening: a wrong guess now DOES persist — it records the
        // incremented verify-attempt count so guesses are capped (see
        // verifyOtp_locksOutAfterMaxWrongGuesses below).
        verify(otpRepository).save(row);
        assertEquals(1, row.getVerifyAttempts());
    }

    @Test
    void verifyOtp_locksOutAfterMaxWrongGuesses() {
        // Phase 10 hardening: closes a real brute-force gap — a 4-digit OTP
        // (10,000 possibilities) previously had NO guess limit at all in
        // this class, unlike PhoneOtpService's attemptCount/attemptsExhausted.
        String hash = passwordEncoder.encode("1234");
        OtpVerification row = new OtpVerification(EMAIL, PURPOSE.name(), hash, LocalDateTime.now().plusMinutes(10));
        when(otpRepository.findByEmailAndPurpose(EMAIL, PURPOSE.name())).thenReturn(Optional.of(row));

        for (int i = 0; i < 5; i++) {
            assertFalse(service.verifyOtp(EMAIL, "9999", PURPOSE), "wrong guess #" + (i + 1) + " should be rejected");
        }
        assertEquals(5, row.getVerifyAttempts());

        // Even the CORRECT code is now rejected — the budget is exhausted,
        // not just "still wrong".
        boolean result = service.verifyOtp(EMAIL, "1234", PURPOSE);
        assertFalse(result, "correct code must still be rejected once the guess budget is exhausted");
        assertFalse(row.getIsUsed());
    }

    @Test
    void verifyOtp_rejectsExpiredOtp() {
        String hash = passwordEncoder.encode("1234");
        OtpVerification row = new OtpVerification(EMAIL, PURPOSE.name(), hash, LocalDateTime.now().minusMinutes(1));
        when(otpRepository.findByEmailAndPurpose(EMAIL, PURPOSE.name())).thenReturn(Optional.of(row));

        assertFalse(service.verifyOtp(EMAIL, "1234", PURPOSE));
    }

    @Test
    void verifyOtp_rejectsAlreadyUsedOtp() {
        String hash = passwordEncoder.encode("1234");
        OtpVerification row = new OtpVerification(EMAIL, PURPOSE.name(), hash, LocalDateTime.now().plusMinutes(10));
        row.setIsUsed(true);
        when(otpRepository.findByEmailAndPurpose(EMAIL, PURPOSE.name())).thenReturn(Optional.of(row));

        assertFalse(service.verifyOtp(EMAIL, "1234", PURPOSE));
    }

    @Test
    void hasRecentVerification_trueOnlyForUsedAndRecentlyVerifiedRow() {
        String hash = passwordEncoder.encode("1234");
        OtpVerification row = new OtpVerification(EMAIL, PURPOSE.name(), hash, LocalDateTime.now().plusMinutes(10));
        row.setIsUsed(true);
        row.setVerifiedAt(LocalDateTime.now().minusMinutes(5));
        when(otpRepository.findByEmailAndPurpose(EMAIL, PURPOSE.name())).thenReturn(Optional.of(row));

        assertTrue(service.hasRecentVerification(EMAIL, PURPOSE));
    }

    @Test
    void hasRecentVerification_falseWhenNeverVerified() {
        when(otpRepository.findByEmailAndPurpose(EMAIL, PURPOSE.name())).thenReturn(Optional.empty());
        assertFalse(service.hasRecentVerification(EMAIL, PURPOSE));
    }
}
