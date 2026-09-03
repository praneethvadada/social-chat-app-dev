package com.socialmedia.auth.entity;

import jakarta.persistence.*;
import java.time.LocalDateTime;

/**
 * Phase 6: purpose-keyed, matching {@link PhoneOtpVerification}'s better-
 * designed pattern — one row per (email, purpose), not one row per email
 * total. Without this, a 2FA-login OTP and an in-flight signup-verification
 * OTP for the same email would collide under the old UNIQUE(email)
 * constraint (whichever sent second would silently delete-then-replace the
 * other's row). Existing callers are unaffected in behavior, only in
 * signature — see OtpService.
 */
@Entity
@Table(name = "otp_verifications",
        uniqueConstraints = @UniqueConstraint(name = "uk_email_purpose", columnNames = {"email", "purpose"}))
public class OtpVerification {

    public enum Purpose {
        /** Signup email verification AND linking a verified email to an existing account — see AccountLinkingController's own doc comment on why these share one purpose. */
        EMAIL_VERIFICATION,
        PASSWORD_RESET,
        TWO_FACTOR_AUTH
    }

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String email;

    @Column(nullable = false, length = 30)
    private String purpose;

    // BCrypt hash of the OTP (via the shared PasswordEncoder bean) — never
    // store the plaintext code. Column renamed from the old plaintext "otp"
    // (Hibernate ddl-auto=update adds this new column but won't drop the
    // old one; safe to manually `ALTER TABLE otp_verifications DROP COLUMN
    // otp` later if you want to tidy it up, not required for correctness).
    @Column(name = "otp_hash", nullable = false)
    private String otpHash;

    @Column(nullable = false)
    private LocalDateTime createdAt;
    
    @Column(nullable = false)
    private LocalDateTime expiresAt;
    
    @Column(nullable = false)
    private Boolean isUsed = false;
    
    @Column(name = "attempts", nullable = false)
    private Integer attempts = 0;

    // Phase 10 hardening: separate from "attempts" above, which only ever
    // counted RESEND calls (see OtpService.resendOtp) — verifyOtp() itself
    // had no guess-limit at all, unlike PhoneOtpVerification's
    // attemptCount/attemptsExhausted(), meaning a 4-digit email OTP
    // (10,000 possibilities, no per-request delay) could be brute-forced
    // with zero lockout for PASSWORD_RESET, TWO_FACTOR_AUTH (login bypass),
    // and the new account-deletion OTP check alike. Reset to 0 whenever a
    // fresh code is issued (send/resend) since a new code deserves a fresh
    // guess budget; incremented only on a failed hash match in verifyOtp().
    @Column(name = "verify_attempts", nullable = false)
    private Integer verifyAttempts = 0;

    // Set when verifyOtp() succeeds — register() checks this (recency +
    // isUsed) as proof the email was actually verified before creating the
    // account, instead of trusting the client to have called verify-otp
    // first (which nothing previously enforced server-side).
    @Column(name = "verified_at")
    private LocalDateTime verifiedAt;

    public OtpVerification() {}

    public OtpVerification(String email, String purpose, String otpHash, LocalDateTime expiresAt) {
        this.email = email;
        this.purpose = purpose;
        this.otpHash = otpHash;
        this.createdAt = LocalDateTime.now();
        this.expiresAt = expiresAt;
        this.isUsed = false;
        this.attempts = 0;
        this.verifyAttempts = 0;
    }

    // Getters and setters
    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public String getEmail() { return email; }
    public void setEmail(String email) { this.email = email; }

    public String getPurpose() { return purpose; }
    public void setPurpose(String purpose) { this.purpose = purpose; }

    public String getOtpHash() { return otpHash; }
    public void setOtpHash(String otpHash) { this.otpHash = otpHash; }

    public LocalDateTime getCreatedAt() { return createdAt; }
    public void setCreatedAt(LocalDateTime createdAt) { this.createdAt = createdAt; }
    
    public LocalDateTime getExpiresAt() { return expiresAt; }
    public void setExpiresAt(LocalDateTime expiresAt) { this.expiresAt = expiresAt; }
    
    public Boolean getIsUsed() { return isUsed; }
    public void setIsUsed(Boolean isUsed) { this.isUsed = isUsed; }
    
    public Integer getAttempts() { return attempts; }
    public void setAttempts(Integer attempts) { this.attempts = attempts; }

    public Integer getVerifyAttempts() { return verifyAttempts; }
    public void setVerifyAttempts(Integer verifyAttempts) { this.verifyAttempts = verifyAttempts; }

    public LocalDateTime getVerifiedAt() { return verifiedAt; }
    public void setVerifiedAt(LocalDateTime verifiedAt) { this.verifiedAt = verifiedAt; }

    public Boolean isExpired() {
        return LocalDateTime.now().isAfter(expiresAt);
    }
}
