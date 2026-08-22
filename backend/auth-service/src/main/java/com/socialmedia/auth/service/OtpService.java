package com.socialmedia.auth.service;

import com.socialmedia.auth.entity.OtpVerification;
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
     * Generate and send OTP to email
     */
    public void sendOtp(String email) {
        try {
            // Generate 4-digit OTP
            String otp = generateOtp();
            LocalDateTime expiresAt = LocalDateTime.now().plusMinutes(OTP_VALIDITY_MINUTES);

            // Check if OTP already exists and delete it
            Optional<OtpVerification> existingOtp = otpRepository.findByEmail(email);
            if (existingOtp.isPresent()) {
                otpRepository.delete(existingOtp.get());
                otpRepository.flush(); // Force delete to commit before insert
            }

            // Save new OTP — hashed, never plaintext
            OtpVerification otpVerification = new OtpVerification(email, passwordEncoder.encode(otp), expiresAt);
            otpRepository.save(otpVerification);

            // Send OTP via email (plaintext, to the user only — never stored or logged)
            emailService.sendOtpEmail(email, otp);

            log.info("OTP sent successfully to email: {}", email);
        } catch (Exception e) {
            log.error("Failed to send OTP to email: {}", email, e);
            throw new RuntimeException("Failed to send OTP: " + e.getMessage());
        }
    }

    /**
     * Verify OTP code
     */
    public boolean verifyOtp(String email, String otp) {
        try {
            Optional<OtpVerification> otpVerification = otpRepository.findByEmail(email);

            if (otpVerification.isEmpty()) {
                log.warn("No OTP request found for email: {}", email);
                return false;
            }

            OtpVerification verification = otpVerification.get();

            // Check if OTP is already used
            if (verification.getIsUsed()) {
                log.warn("OTP already used for email: {}", email);
                return false;
            }

            // Check if OTP is expired
            if (verification.isExpired()) {
                log.warn("OTP expired for email: {}", email);
                return false;
            }

            if (!passwordEncoder.matches(otp, verification.getOtpHash())) {
                log.warn("OTP mismatch for email: {}", email);
                return false;
            }

            // Mark OTP as used and record when verification succeeded —
            // AuthService.register() checks verifiedAt as proof the email
            // was actually verified before it creates the account.
            verification.setIsUsed(true);
            verification.setVerifiedAt(LocalDateTime.now());
            otpRepository.save(verification);

            log.info("OTP verified successfully for email: {}", email);
            return true;

        } catch (Exception e) {
            log.error("Error verifying OTP for email: {}", email, e);
            throw new RuntimeException("OTP verification failed: " + e.getMessage());
        }
    }

    /**
     * Resend OTP to email
     */
    public void resendOtp(String email) {
        try {
            // Get existing OTP
            Optional<OtpVerification> existingOtp = otpRepository.findByEmail(email);

            if (existingOtp.isPresent()) {
                OtpVerification verification = existingOtp.get();

                // Check attempts
                if (verification.getAttempts() >= MAX_ATTEMPTS) {
                    throw new RuntimeException("Maximum resend attempts exceeded. Please try again later.");
                }

                // Generate new OTP
                String newOtp = generateOtp();
                LocalDateTime expiresAt = LocalDateTime.now().plusMinutes(OTP_VALIDITY_MINUTES);

                verification.setOtpHash(passwordEncoder.encode(newOtp));
                verification.setExpiresAt(expiresAt);
                verification.setIsUsed(false);
                verification.setAttempts(verification.getAttempts() + 1);
                verification.setCreatedAt(LocalDateTime.now());

                otpRepository.save(verification);
                emailService.sendOtpEmail(email, newOtp);

                log.info("OTP resent successfully to email: {}", email);
            } else {
                throw new RuntimeException("No OTP request found for this email");
            }
        } catch (Exception e) {
            log.error("Failed to resend OTP to email: {}", email, e);
            throw new RuntimeException("Failed to resend OTP: " + e.getMessage());
        }
    }

    /**
     * Send OTP for password reset
     */
    public void sendPasswordResetOtp(String email) {
        try {
            // Generate 4-digit OTP
            String otp = generateOtp();
            LocalDateTime expiresAt = LocalDateTime.now().plusMinutes(OTP_VALIDITY_MINUTES);

            // Check if OTP already exists and delete it
            Optional<OtpVerification> existingOtp = otpRepository.findByEmail(email);
            if (existingOtp.isPresent()) {
                otpRepository.delete(existingOtp.get());
                otpRepository.flush(); // Force delete to commit before insert
            }

            // Save new OTP
            OtpVerification otpVerification = new OtpVerification(email, passwordEncoder.encode(otp), expiresAt);
            otpRepository.save(otpVerification);

            // Send OTP via email with password reset context
            emailService.sendOtpEmail(email, otp);

            log.info("Password reset OTP sent successfully to email: {}", email);
        } catch (Exception e) {
            log.error("Failed to send password reset OTP to email: {}", email, e);
            throw new RuntimeException("Failed to send password reset OTP: " + e.getMessage());
        }
    }

    /**
     * Used by AuthService.register() as proof the email was actually
     * verified (via the existing send-otp/verify-otp flow) before creating
     * the account, instead of trusting the client to have called
     * verify-otp first — nothing previously enforced that server-side.
     */
    public boolean hasRecentVerification(String email) {
        return otpRepository.findByEmail(email)
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
