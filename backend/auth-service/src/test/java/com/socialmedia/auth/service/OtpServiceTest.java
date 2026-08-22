package com.socialmedia.auth.service;

import com.socialmedia.auth.entity.OtpVerification;
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
 * is cryptographically random per call.
 */
@ExtendWith(MockitoExtension.class)
class OtpServiceTest {

    private static final String EMAIL = "user@example.com";

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
        when(otpRepository.findByEmail(EMAIL)).thenReturn(Optional.empty());

        service.sendOtp(EMAIL);

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
        when(otpRepository.findByEmail(anyString())).thenReturn(Optional.empty());

        ArgumentCaptor<String> captor = ArgumentCaptor.forClass(String.class);
        service.sendOtp(EMAIL);
        service.sendOtp(EMAIL);
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
        OtpVerification row = new OtpVerification(EMAIL, hash, LocalDateTime.now().plusMinutes(10));
        when(otpRepository.findByEmail(EMAIL)).thenReturn(Optional.of(row));

        boolean result = service.verifyOtp(EMAIL, realOtp);

        assertTrue(result);
        assertTrue(row.getIsUsed());
        org.junit.jupiter.api.Assertions.assertNotNull(row.getVerifiedAt());
        verify(otpRepository).save(row);
    }

    @Test
    void verifyOtp_rejectsWrongCode_comparingHashesNotPlaintext() {
        String hash = passwordEncoder.encode("1234");
        OtpVerification row = new OtpVerification(EMAIL, hash, LocalDateTime.now().plusMinutes(10));
        when(otpRepository.findByEmail(EMAIL)).thenReturn(Optional.of(row));

        boolean result = service.verifyOtp(EMAIL, "9999");

        assertFalse(result);
        assertFalse(row.getIsUsed());
        verify(otpRepository, never()).save(any());
    }

    @Test
    void verifyOtp_rejectsExpiredOtp() {
        String hash = passwordEncoder.encode("1234");
        OtpVerification row = new OtpVerification(EMAIL, hash, LocalDateTime.now().minusMinutes(1));
        when(otpRepository.findByEmail(EMAIL)).thenReturn(Optional.of(row));

        assertFalse(service.verifyOtp(EMAIL, "1234"));
    }

    @Test
    void verifyOtp_rejectsAlreadyUsedOtp() {
        String hash = passwordEncoder.encode("1234");
        OtpVerification row = new OtpVerification(EMAIL, hash, LocalDateTime.now().plusMinutes(10));
        row.setIsUsed(true);
        when(otpRepository.findByEmail(EMAIL)).thenReturn(Optional.of(row));

        assertFalse(service.verifyOtp(EMAIL, "1234"));
    }

    @Test
    void hasRecentVerification_trueOnlyForUsedAndRecentlyVerifiedRow() {
        String hash = passwordEncoder.encode("1234");
        OtpVerification row = new OtpVerification(EMAIL, hash, LocalDateTime.now().plusMinutes(10));
        row.setIsUsed(true);
        row.setVerifiedAt(LocalDateTime.now().minusMinutes(5));
        when(otpRepository.findByEmail(EMAIL)).thenReturn(Optional.of(row));

        assertTrue(service.hasRecentVerification(EMAIL));
    }

    @Test
    void hasRecentVerification_falseWhenNeverVerified() {
        when(otpRepository.findByEmail(EMAIL)).thenReturn(Optional.empty());
        assertFalse(service.hasRecentVerification(EMAIL));
    }
}
