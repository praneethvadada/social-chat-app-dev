package com.socialmedia.auth.scheduler;

import com.socialmedia.auth.repository.PhoneOtpVerificationRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;

/**
 * Housekeeping for expired phone OTP rows. Modeled directly on
 * social-service's StatusCleanupScheduler (DB-based, hourly, transactional).
 * Verification/expiry checks never depend on this job running — every read
 * already checks isExpired()/expiresAt — this only reclaims storage.
 */
@Component
public class PhoneOtpCleanupScheduler {
    private static final Logger log = LoggerFactory.getLogger(PhoneOtpCleanupScheduler.class);

    // Keep a grace period past expiry so a row that just expired isn't
    // yanked out from under an in-flight request.
    private static final int GRACE_HOURS = 24;

    private final PhoneOtpVerificationRepository phoneOtpVerificationRepository;

    public PhoneOtpCleanupScheduler(PhoneOtpVerificationRepository phoneOtpVerificationRepository) {
        this.phoneOtpVerificationRepository = phoneOtpVerificationRepository;
    }

    @Scheduled(fixedDelay = 3_600_000) // hourly
    @Transactional
    public void purgeExpired() {
        LocalDateTime cutoff = LocalDateTime.now().minusHours(GRACE_HOURS);
        int removed = phoneOtpVerificationRepository.deleteExpiredBefore(cutoff);
        if (removed > 0) {
            log.info("[PhoneOtp] Purged {} expired OTP row(s) created before {}", removed, cutoff);
        }
    }
}
