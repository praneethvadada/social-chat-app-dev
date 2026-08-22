package com.socialmedia.auth.service;

import com.socialmedia.auth.entity.PhoneOtpVerification;
import com.socialmedia.auth.exception.AuthApiException;
import com.socialmedia.auth.repository.PhoneOtpVerificationRepository;
import com.socialmedia.auth.service.sms.SmsProvider;
import com.socialmedia.auth.util.PhoneNumberValidator;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.security.SecureRandom;
import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

/**
 * Phone-number OTP lifecycle: generation, hashed storage, SMS dispatch,
 * atomic verification, resend cooldown, and hourly per-phone rate limiting.
 * Mirrors OtpService's shape (the existing email-OTP service) but hardened
 * per the phone-auth feature's security requirements: SecureRandom instead
 * of Random, hashed storage instead of plaintext, purpose isolation, and
 * row-locked atomic verification.
 */
@Service
public class PhoneOtpService {
    private static final Logger log = LoggerFactory.getLogger(PhoneOtpService.class);
    private static final SecureRandom SECURE_RANDOM = new SecureRandom();

    private final PhoneOtpVerificationRepository otpRepository;
    private final SmsProvider smsProvider;
    private final PasswordEncoder passwordEncoder;
    private final PhoneNumberValidator phoneNumberValidator;

    @Value("${otp.length:6}")
    private int otpLength;

    @Value("${otp.expiry-seconds:300}")
    private long otpExpirySeconds;

    @Value("${otp.max-attempts:5}")
    private int otpMaxAttempts;

    @Value("${otp.resend-cooldown-seconds:60}")
    private long resendCooldownSeconds;

    @Value("${otp.max-requests-per-hour:5}")
    private int maxRequestsPerHour;

    // How recent a successful verification must be for register()/link
    // endpoints to accept it as proof — generous enough for a real signup
    // flow (fill in username/password after verifying), tight enough that a
    // verification from days ago can't be replayed.
    @Value("${otp.verification-proof-validity-minutes:30}")
    private long verificationProofValidityMinutes;

    public PhoneOtpService(PhoneOtpVerificationRepository otpRepository,
                            SmsProvider smsProvider,
                            PasswordEncoder passwordEncoder,
                            PhoneNumberValidator phoneNumberValidator) {
        this.otpRepository = otpRepository;
        this.smsProvider = smsProvider;
        this.passwordEncoder = passwordEncoder;
        this.phoneNumberValidator = phoneNumberValidator;
    }

    @Transactional
    public void sendOtp(String phoneNumberE164, PhoneOtpVerification.Purpose purpose) {
        enforceRateLimit(phoneNumberE164, purpose);
        enforceResendCooldown(phoneNumberE164, purpose);
        issueNewOtp(phoneNumberE164, purpose);
    }

    @Transactional
    public void resendOtp(String phoneNumberE164, PhoneOtpVerification.Purpose purpose) {
        // Same underlying mechanics as sendOtp — history-based rate limiting
        // (unlike the email OTP table's overwrite-in-place model) means
        // "send" and "resend" are naturally the same operation here.
        Optional<PhoneOtpVerification> existing = otpRepository
                .findTopByPhoneNumberAndPurposeOrderByCreatedAtDesc(phoneNumberE164, purpose.name());
        if (existing.isEmpty()) {
            throw new AuthApiException(AuthApiException.ErrorCode.OTP_INVALID,
                    "No OTP request found for this phone number", org.springframework.http.HttpStatus.BAD_REQUEST);
        }
        enforceRateLimit(phoneNumberE164, purpose);
        enforceResendCooldown(phoneNumberE164, purpose);
        issueNewOtp(phoneNumberE164, purpose);
    }

    /**
     * Atomically verifies the OTP: locks the latest row for this
     * phone+purpose so two concurrent requests (replay or guess-race) can't
     * both succeed, checks purpose/expiry/attempts, and marks it verified
     * exactly once.
     */
    @Transactional
    public boolean verifyOtp(String phoneNumberE164, String otp, PhoneOtpVerification.Purpose purpose) {
        List<PhoneOtpVerification> rows = otpRepository.lockLatestByPhoneAndPurpose(phoneNumberE164, purpose.name());
        if (rows.isEmpty()) {
            throw new AuthApiException(AuthApiException.ErrorCode.OTP_INVALID, "No OTP request found for this phone number",
                    org.springframework.http.HttpStatus.BAD_REQUEST);
        }
        PhoneOtpVerification verification = rows.get(0);

        if (verification.isVerified()) {
            // Already consumed — a concurrent/replayed request. Treat as invalid, not a silent success.
            throw new AuthApiException(AuthApiException.ErrorCode.OTP_INVALID, "OTP already used",
                    org.springframework.http.HttpStatus.BAD_REQUEST);
        }
        if (verification.isExpired()) {
            throw new AuthApiException(AuthApiException.ErrorCode.OTP_EXPIRED, "OTP has expired",
                    org.springframework.http.HttpStatus.BAD_REQUEST);
        }
        if (verification.attemptsExhausted()) {
            throw new AuthApiException(AuthApiException.ErrorCode.OTP_MAX_ATTEMPTS,
                    "Maximum verification attempts exceeded. Please request a new OTP.",
                    org.springframework.http.HttpStatus.BAD_REQUEST);
        }

        boolean matches = passwordEncoder.matches(otp, verification.getOtpHash());
        if (!matches) {
            verification.setAttemptCount(verification.getAttemptCount() + 1);
            otpRepository.save(verification);
            throw new AuthApiException(AuthApiException.ErrorCode.OTP_INVALID, "Invalid OTP",
                    org.springframework.http.HttpStatus.BAD_REQUEST);
        }

        verification.setVerifiedAt(LocalDateTime.now());
        otpRepository.save(verification);
        log.info("Phone OTP verified for {} purpose={}", PhoneNumberValidator.mask(phoneNumberE164), purpose);
        return true;
    }

    /** Used by register()/link endpoints as proof of a recently-completed OTP verification. */
    public boolean hasRecentVerification(String phoneNumberE164, PhoneOtpVerification.Purpose purpose) {
        return otpRepository.findTopByPhoneNumberAndPurposeAndVerifiedAtIsNotNullOrderByVerifiedAtDesc(phoneNumberE164, purpose.name())
                .map(v -> v.getVerifiedAt().isAfter(LocalDateTime.now().minusMinutes(verificationProofValidityMinutes)))
                .orElse(false);
    }

    private void issueNewOtp(String phoneNumberE164, PhoneOtpVerification.Purpose purpose) {
        String otp = generateOtp();
        String otpHash = passwordEncoder.encode(otp);
        LocalDateTime expiresAt = LocalDateTime.now().plusSeconds(otpExpirySeconds);

        PhoneOtpVerification verification = new PhoneOtpVerification(phoneNumberE164, otpHash, purpose, expiresAt, otpMaxAttempts);
        otpRepository.save(verification);

        try {
            smsProvider.sendOtp(phoneNumberE164, otp);
        } catch (Exception e) {
            log.error("Failed to dispatch OTP SMS to {}: {}", PhoneNumberValidator.mask(phoneNumberE164), e.getMessage());
            throw new AuthApiException(AuthApiException.ErrorCode.OTP_INVALID,
                    "Unable to send OTP. Please try again later.", org.springframework.http.HttpStatus.SERVICE_UNAVAILABLE);
        }
        log.info("OTP issued for {} purpose={}", PhoneNumberValidator.mask(phoneNumberE164), purpose);
    }

    private void enforceRateLimit(String phoneNumberE164, PhoneOtpVerification.Purpose purpose) {
        long countInLastHour = otpRepository.countByPhoneNumberAndPurposeAndCreatedAtAfter(
                phoneNumberE164, purpose.name(), LocalDateTime.now().minusHours(1));
        if (countInLastHour >= maxRequestsPerHour) {
            throw new AuthApiException(AuthApiException.ErrorCode.OTP_RATE_LIMIT_EXCEEDED,
                    "Too many OTP requests. Please try again later.", org.springframework.http.HttpStatus.TOO_MANY_REQUESTS);
        }
    }

    private void enforceResendCooldown(String phoneNumberE164, PhoneOtpVerification.Purpose purpose) {
        otpRepository.findTopByPhoneNumberAndPurposeOrderByCreatedAtDesc(phoneNumberE164, purpose.name())
                .ifPresent(latest -> {
                    LocalDateTime cooldownEnds = latest.getCreatedAt().plusSeconds(resendCooldownSeconds);
                    if (LocalDateTime.now().isBefore(cooldownEnds)) {
                        throw new AuthApiException(AuthApiException.ErrorCode.OTP_RESEND_TOO_SOON,
                                "Please wait before requesting another OTP.", org.springframework.http.HttpStatus.TOO_MANY_REQUESTS);
                    }
                });
    }

    private String generateOtp() {
        int max = (int) Math.pow(10, otpLength);
        int min = (int) Math.pow(10, otpLength - 1);
        int otp = min + SECURE_RANDOM.nextInt(max - min);
        return String.valueOf(otp);
    }
}
