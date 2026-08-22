package com.socialmedia.social.scheduler;

import com.socialmedia.social.repository.StatusRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.time.ZoneId;

/**
 * Housekeeping for expired statuses.
 *
 * Visibility does NOT depend on this job - every read already filters on
 * expiresAt, so a status is invisible the instant it expires. This only
 * reclaims storage, and keeps a grace period so anything mid-view isn't
 * yanked out from under a client.
 */
@Component
@RequiredArgsConstructor
@Slf4j
public class StatusCleanupScheduler {

    private static final int GRACE_HOURS = 24;

    private final StatusRepository statusRepository;

    @Scheduled(fixedDelay = 3_600_000) // hourly
    @Transactional
    public void purgeExpired() {
        LocalDateTime cutoff = LocalDateTime.now(ZoneId.of("UTC")).minusHours(GRACE_HOURS);
        int removed = statusRepository.deleteExpiredBefore(cutoff);
        if (removed > 0) {
            log.info("[Status] Purged {} status(es) expired before {}", removed, cutoff);
        }
    }
}
