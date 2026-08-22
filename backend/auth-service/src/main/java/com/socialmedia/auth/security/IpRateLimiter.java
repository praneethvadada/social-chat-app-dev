package com.socialmedia.auth.security;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.ArrayDeque;
import java.util.Deque;
import java.util.Iterator;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * In-memory per-IP sliding-window rate limiter for the phone-OTP send/resend
 * endpoints — Redis isn't genuinely available anywhere in this stack (see
 * plan), so this mirrors social-chats-service's PresenceService pattern
 * (ConcurrentHashMap + scheduled sweep) as the natural precursor to a
 * Redis-backed limiter if one is introduced later. Deliberately scoped to
 * just the OTP endpoints, not a general-purpose gateway filter.
 */
@Component
public class IpRateLimiter {
    private static final Logger log = LoggerFactory.getLogger(IpRateLimiter.class);

    @Value("${otp.ip-rate-limit-per-hour:20}")
    private int maxRequestsPerHour;

    private final Map<String, Deque<Long>> requestsByIp = new ConcurrentHashMap<>();

    /** Returns true if the request is allowed (and records it); false if the IP is over its hourly cap. */
    public boolean allow(String ip) {
        if (ip == null || ip.isBlank()) return true; // fail-open on missing IP info, don't block legitimate traffic
        long now = System.currentTimeMillis();
        long windowStart = now - 3_600_000L;

        Deque<Long> timestamps = requestsByIp.computeIfAbsent(ip, k -> new ArrayDeque<>());
        synchronized (timestamps) {
            while (!timestamps.isEmpty() && timestamps.peekFirst() < windowStart) {
                timestamps.pollFirst();
            }
            if (timestamps.size() >= maxRequestsPerHour) {
                return false;
            }
            timestamps.addLast(now);
            return true;
        }
    }

    @Scheduled(fixedDelay = 1_800_000) // every 30 minutes
    public void sweepStale() {
        long cutoff = System.currentTimeMillis() - 3_600_000L;
        int removedIps = 0;
        Iterator<Map.Entry<String, Deque<Long>>> it = requestsByIp.entrySet().iterator();
        while (it.hasNext()) {
            Map.Entry<String, Deque<Long>> entry = it.next();
            Deque<Long> timestamps = entry.getValue();
            synchronized (timestamps) {
                while (!timestamps.isEmpty() && timestamps.peekFirst() < cutoff) {
                    timestamps.pollFirst();
                }
                if (timestamps.isEmpty()) {
                    it.remove();
                    removedIps++;
                }
            }
        }
        if (removedIps > 0) {
            log.debug("[IpRateLimiter] Swept {} stale IP entr(y/ies)", removedIps);
        }
    }
}
