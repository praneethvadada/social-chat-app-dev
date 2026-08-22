package com.socialmedia.auth.repository;

import com.socialmedia.auth.entity.PhoneOtpVerification;
import jakarta.persistence.LockModeType;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Lock;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

@Repository
public interface PhoneOtpVerificationRepository extends JpaRepository<PhoneOtpVerification, Long> {

    Optional<PhoneOtpVerification> findTopByPhoneNumberAndPurposeOrderByCreatedAtDesc(String phoneNumber, String purpose);

    // Row-locked variant used by verifyOtp() so two concurrent requests
    // guessing/replaying the same OTP can't both succeed — the second
    // request blocks until the first transaction commits, then sees
    // verifiedAt already set.
    @Lock(LockModeType.PESSIMISTIC_WRITE)
    @Query("SELECT p FROM PhoneOtpVerification p WHERE p.phoneNumber = :phoneNumber AND p.purpose = :purpose ORDER BY p.createdAt DESC")
    List<PhoneOtpVerification> lockLatestByPhoneAndPurpose(@Param("phoneNumber") String phoneNumber, @Param("purpose") String purpose);

    // Hourly per-phone rate limit (spec: "Maximum 5 OTP requests per hour").
    long countByPhoneNumberAndPurposeAndCreatedAtAfter(String phoneNumber, String purpose, LocalDateTime since);

    // Most recent successful verification for this phone+purpose, used by
    // register()/link endpoints as proof of a recently-completed OTP flow.
    Optional<PhoneOtpVerification> findTopByPhoneNumberAndPurposeAndVerifiedAtIsNotNullOrderByVerifiedAtDesc(String phoneNumber, String purpose);

    @Modifying
    @Query("DELETE FROM PhoneOtpVerification p WHERE p.expiresAt < :cutoff")
    int deleteExpiredBefore(@Param("cutoff") LocalDateTime cutoff);
}
