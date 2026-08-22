package com.socialmedia.auth.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;

import java.time.LocalDateTime;

/**
 * Phone-number OTP verification, separate from the existing (email-only,
 * uniquely-keyed-by-email) OtpVerification table. Unlike that table, rows
 * here are NOT overwritten in place on resend/re-send — historical rows are
 * kept so hourly per-phone rate limiting can be computed with a COUNT query.
 * A single phone number can have multiple rows over time, and even multiple
 * concurrent purposes (e.g. PHONE_SIGNUP and, after that account exists,
 * PHONE_VERIFICATION for a different account attempt) without collision.
 */
@Entity
@Table(name = "phone_otp_verifications", indexes = {
        @Index(name = "idx_phone_purpose", columnList = "phone_number,purpose"),
        @Index(name = "idx_expires_at", columnList = "expires_at")
})
public class PhoneOtpVerification {

    public enum Purpose {
        PHONE_SIGNUP,
        PHONE_VERIFICATION
    }

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "phone_number", nullable = false, length = 20)
    private String phoneNumber;

    // BCrypt hash of the OTP (via the shared PasswordEncoder bean) — never
    // store the plaintext code.
    @Column(name = "otp_hash", nullable = false)
    private String otpHash;

    @Column(nullable = false, length = 30)
    private String purpose;

    @Column(name = "attempt_count", nullable = false)
    private Integer attemptCount = 0;

    @Column(name = "max_attempts", nullable = false)
    private Integer maxAttempts = 5;

    @Column(name = "expires_at", nullable = false)
    private LocalDateTime expiresAt;

    @Column(name = "verified_at")
    private LocalDateTime verifiedAt;

    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    public PhoneOtpVerification() {
    }

    public PhoneOtpVerification(String phoneNumber, String otpHash, Purpose purpose, LocalDateTime expiresAt, int maxAttempts) {
        this.phoneNumber = phoneNumber;
        this.otpHash = otpHash;
        this.purpose = purpose.name();
        this.expiresAt = expiresAt;
        this.maxAttempts = maxAttempts;
        this.attemptCount = 0;
        this.createdAt = LocalDateTime.now();
    }

    public boolean isExpired() {
        return LocalDateTime.now().isAfter(expiresAt);
    }

    public boolean isVerified() {
        return verifiedAt != null;
    }

    public boolean attemptsExhausted() {
        return attemptCount >= maxAttempts;
    }

    // Getters and setters

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public String getPhoneNumber() { return phoneNumber; }
    public void setPhoneNumber(String phoneNumber) { this.phoneNumber = phoneNumber; }

    public String getOtpHash() { return otpHash; }
    public void setOtpHash(String otpHash) { this.otpHash = otpHash; }

    public String getPurpose() { return purpose; }
    public void setPurpose(String purpose) { this.purpose = purpose; }

    public Integer getAttemptCount() { return attemptCount; }
    public void setAttemptCount(Integer attemptCount) { this.attemptCount = attemptCount; }

    public Integer getMaxAttempts() { return maxAttempts; }
    public void setMaxAttempts(Integer maxAttempts) { this.maxAttempts = maxAttempts; }

    public LocalDateTime getExpiresAt() { return expiresAt; }
    public void setExpiresAt(LocalDateTime expiresAt) { this.expiresAt = expiresAt; }

    public LocalDateTime getVerifiedAt() { return verifiedAt; }
    public void setVerifiedAt(LocalDateTime verifiedAt) { this.verifiedAt = verifiedAt; }

    public LocalDateTime getCreatedAt() { return createdAt; }
    public void setCreatedAt(LocalDateTime createdAt) { this.createdAt = createdAt; }
}
