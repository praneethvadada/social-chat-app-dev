package com.socialmedia.auth.repository;

import com.socialmedia.auth.entity.OtpVerification;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface OtpVerificationRepository extends JpaRepository<OtpVerification, Long> {
    Optional<OtpVerification> findByEmail(String email);
    // No findByEmailAndOtp — the OTP is hashed now, so lookup is always by
    // email, then the service layer compares the hash via PasswordEncoder.
}
