package com.socialmedia.chats.scheduler;

import com.socialmedia.chats.service.PresenceService;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

/**
 * Periodically reaps users whose presence heartbeat has gone stale, as a safety
 * net for WebSocket disconnect events that never arrived (app killed, network
 * drop). Presence is entirely in-memory now (no users-table writes).
 *
 * Relies on the mobile client sending a periodic presence.update heartbeat
 * (~25s); the 45s cutoff leaves room for one missed heartbeat before reaping.
 */
@Component
public class PresenceSweepScheduler {

    private static final long STALE_AFTER_MS = 45_000;

    private final PresenceService presenceService;

    public PresenceSweepScheduler(PresenceService presenceService) {
        this.presenceService = presenceService;
    }

    @Scheduled(fixedDelay = 30_000)
    public void sweep() {
        presenceService.sweepStale(STALE_AFTER_MS);
    }
}
