package com.socialmedia.auth.service;

import com.socialmedia.auth.entity.OtpVerification;
import com.socialmedia.auth.entity.OtpVerification.Purpose;
import com.socialmedia.auth.repository.OtpVerificationRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import java.security.SecureRandom;
import java.time.LocalDateTime;
import java.util.Optional;

@Service
public class OtpService {
    private static final Logger log = LoggerFactory.getLogger(OtpService.class);
    private static final int OTP_LENGTH = 4;
    private static final int OTP_VALIDITY_MINUTES = 10;
    private static final int MAX_ATTEMPTS = 5;
    // Phase 10 hardening: guess-attempt cap for verifyOtp(), distinct from
    // MAX_ATTEMPTS above (which only ever gated /resend-otp call count).
    private static final int MAX_VERIFY_ATTEMPTS = 5;
    private static final int VERIFICATION_PROOF_VALIDITY_MINUTES = 30;
    private static final SecureRandom SECURE_RANDOM = new SecureRandom();

    private final OtpVerificationRepository otpRepository;
    private final EmailService emailService;
    private final PasswordEncoder passwordEncoder;

    public OtpService(OtpVerificationRepository otpRepository, EmailService emailService, PasswordEncoder passwordEncoder) {
        this.otpRepository = otpRepository;
        this.emailService = emailService;
        this.passwordEncoder = passwordEncoder;
    }

    /**
     * Generate and send OTP to email for the given purpose. Phase 6: purpose-
     * keyed (see OtpVerification's doc comment) — a signup-verification OTP
     * and a 2FA OTP for the same email now live in separate rows instead of
     * silently overwriting each other.
     */
    public void sendOtp(String email, Purpose purpose) {
        try {
            String otp = generateOtp();
            LocalDateTime expiresAt = LocalDateTime.now().plusMinutes(OTP_VALIDITY_MINUTES);

            // Check if OTP already exists for this (email, purpose) and delete it
            Optional<OtpVerification> existingOtp = otpRepository.findByEmailAndPurpose(email, purpose.name());
            if (existingOtp.isPresent()) {
                otpRepository.delete(existingOtp.get());
                otpRepository.flush(); // Force delete to commit before insert
            }

            // Save new OTP — hashed, never plaintext
            OtpVerification otpVerification = new OtpVerification(email, purpose.name(), passwordEncoder.encode(otp), expiresAt);
            otpRepository.save(otpVerification);

            // Send OTP via email (plaintext, to the user only — never stored or logged)
            emailService.sendOtpEmail(email, otp);

            log.info("OTP sent successfully to email: {} (purpose={})", email, purpose);
        } catch (Exception e) {
            log.error("Failed to send OTP to email: {} (purpose={})", email, purpose, e);
            throw new RuntimeException("Failed to send OTP: " + e.getMessage());
        }
    }

    /**
     * Verify OTP code for the given purpose.
     */
    public boolean verifyOtp(String email, String otp, Purpose purpose) {
        try {
            Optional<OtpVerification> otpVerification = otpRepository.findByEmailAndPurpose(email, purpose.name());

            if (otpVerification.isEmpty()) {
                log.warn("No OTP request found for email: {} (purpose={})", email, purpose);
                return false;
            }

            OtpVerification verification = otpVerification.get();

            // Check if OTP is already used
            if (verification.getIsUsed()) {
                log.warn("OTP already used for email: {} (purpose={})", email, purpose);
                return false;
            }

            // Check if OTP is expired
            if (verification.isExpired()) {
                log.warn("OTP expired for email: {} (purpose={})", email, purpose);
                return false;
            }

            // Phase 10 hardening: without this, a 4-digit OTP (10,000
            // possibilities) had no server-side guess limit at all — see
            // OtpVerification.verifyAttempts's doc comment for the severity
            // (PASSWORD_RESET/TWO_FACTOR_AUTH/account-deletion are all
            // brute-forceable within the 10-minute validity window otherwise).
            if (verification.getVerifyAttempts() >= MAX_VERIFY_ATTEMPTS) {
                log.warn("OTP verify-attempt limit exceeded for email: {} (purpose={})", email, purpose);
                return false;
            }

            if (!passwordEncoder.matches(otp, verification.getOtpHash())) {
                verification.setVerifyAttempts(verification.getVerifyAttempts() + 1);
                otpRepository.save(verification);
                log.warn("OTP mismatch for email: {} (purpose={})", email, purpose);
                return false;
            }

            // Mark OTP as used and record when verification succeeded —
            // AuthService.register() checks verifiedAt as proof the email
            // was actually verified before it creates the account.
            verification.setIsUsed(true);
            verification.setVerifiedAt(LocalDateTime.now());
            otpRepository.save(verification);

            log.info("OTP verified successfully for email: {} (purpose={})", email, purpose);
            return true;

        } catch (Exception e) {
            log.error("Error verifying OTP for email: {} (purpose={})", email, purpose, e);
            throw new RuntimeException("OTP verification failed: " + e.getMessage());
        }
    }

    /**
     * Resend OTP to email for the given purpose.
     */
    public void resendOtp(String email, Purpose purpose) {
        try {
            Optional<OtpVerification> existingOtp = otpRepository.findByEmailAndPurpose(email, purpose.name());

            if (existingOtp.isPresent()) {
                OtpVerification verification = existingOtp.get();

                if (verification.getAttempts() >= MAX_ATTEMPTS) {
                    throw new RuntimeException("Maximum resend attempts exceeded. Please try again later.");
                }

                String newOtp = generateOtp();
                LocalDateTime expiresAt = LocalDateTime.now().plusMinutes(OTP_VALIDITY_MINUTES);

                verification.setOtpHash(passwordEncoder.encode(newOtp));
                verification.setExpiresAt(expiresAt);
                verification.setIsUsed(false);
                verification.setAttempts(verification.getAttempts() + 1);
                verification.setVerifyAttempts(0); // fresh code, fresh guess budget
                verification.setCreatedAt(LocalDateTime.now());

                otpRepository.save(verification);
                emailService.sendOtpEmail(email, newOtp);

                log.info("OTP resent successfully to email: {} (purpose={})", email, purpose);
            } else {
                throw new RuntimeException("No OTP request found for this email");
            }
        } catch (Exception e) {
            log.error("Failed to resend OTP to email: {} (purpose={})", email, purpose, e);
            throw new RuntimeException("Failed to resend OTP: " + e.getMessage());
        }
    }

    /**
     * Send OTP for password reset. Thin convenience wrapper so existing
     * callers (AuthService.sendPasswordResetOtp) don't need to know about
     * the Purpose enum directly.
     */
    public void sendPasswordResetOtp(String email) {
        sendOtp(email, Purpose.PASSWORD_RESET);
    }

    /**
     * Used by AuthService.register() as proof the email was actually
     * verified (via the existing send-otp/verify-otp flow) before creating
     * the account, instead of trusting the client to have called
     * verify-otp first — nothing previously enforced that server-side.
     */
    public boolean hasRecentVerification(String email, Purpose purpose) {
        return otpRepository.findByEmailAndPurpose(email, purpose.name())
                .filter(OtpVerification::getIsUsed)
                .map(v -> v.getVerifiedAt() != null && v.getVerifiedAt().isAfter(LocalDateTime.now().minusMinutes(VERIFICATION_PROOF_VALIDITY_MINUTES)))
                .orElse(false);
    }

    /**
     * Generate a cryptographically secure random 4-digit OTP (SecureRandom,
     * not Random/Math.random()).
     */
    private String generateOtp() {
        int otp = 1000 + SECURE_RANDOM.nextInt(9000);
        return String.valueOf(otp);
    }
}
