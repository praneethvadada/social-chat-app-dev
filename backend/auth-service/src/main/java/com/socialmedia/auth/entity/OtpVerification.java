package com.socialmedia.auth.entity;

import jakarta.persistence.*;
import java.time.LocalDateTime;

@Entity
@Table(name = "otp_verifications")
public class OtpVerification {
    
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    
    @Column(nullable = false, unique = true)
    private String email;
    
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

    // Set when verifyOtp() succeeds — register() checks this (recency +
    // isUsed) as proof the email was actually verified before creating the
    // account, instead of trusting the client to have called verify-otp
    // first (which nothing previously enforced server-side).
    @Column(name = "verified_at")
    private LocalDateTime verifiedAt;

    public OtpVerification() {}
    
    public OtpVerification(String email, String otpHash, LocalDateTime expiresAt) {
        this.email = email;
        this.otpHash = otpHash;
        this.createdAt = LocalDateTime.now();
        this.expiresAt = expiresAt;
        this.isUsed = false;
        this.attempts = 0;
    }

    // Getters and setters
    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public String getEmail() { return email; }
    public void setEmail(String email) { this.email = email; }

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

    public LocalDateTime getVerifiedAt() { return verifiedAt; }
    public void setVerifiedAt(LocalDateTime verifiedAt) { this.verifiedAt = verifiedAt; }

    public Boolean isExpired() {
        return LocalDateTime.now().isAfter(expiresAt);
    }
}
