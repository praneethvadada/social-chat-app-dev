package com.socialmedia.auth.repository;

import com.socialmedia.auth.entity.OtpVerification;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface OtpVerificationRepository extends JpaRepository<OtpVerification, Long> {
    // Phase 6: purpose-keyed (see OtpVerification's own doc comment) — every
    // caller now knows which flow it's part of, so plain findByEmail no
    // longer exists (it would be ambiguous which purpose's row to return).
    Optional<OtpVerification> findByEmailAndPurpose(String email, String purpose);
    // No findByEmailAndOtp — the OTP is hashed now, so lookup is always by
    // email, then the service layer compares the hash via PasswordEncoder.
}
