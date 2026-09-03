package com.socialmedia.auth.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.LocalDateTime;

/**
 * Exactly one row per user — userId IS the primary key, so "at most one
 * active web session per account" is a database-level guarantee, mirroring
 * {@link MobileStorageOwner}'s exact pattern. A new WEB login pessimistic-
 * locks this row (see ActiveWebSessionRepository.lockByUserId), revokes
 * whatever UserSession this row previously pointed at, then overwrites it —
 * so two near-simultaneous web logins can never both end up "active".
 */
@Entity
@Table(name = "active_web_session")
public class ActiveWebSession {

    @Id
    @Column(name = "user_id")
    private Long userId;

    @Column(name = "session_id", nullable = false)
    private Long sessionId;

    @Column(name = "device_id", nullable = false)
    private Long deviceId;

    @Column(name = "granted_at", nullable = false)
    private LocalDateTime grantedAt;

    public ActiveWebSession() {
    }

    public ActiveWebSession(Long userId, Long sessionId, Long deviceId, LocalDateTime grantedAt) {
        this.userId = userId;
        this.sessionId = sessionId;
        this.deviceId = deviceId;
        this.grantedAt = grantedAt;
    }

    public Long getUserId() { return userId; }
    public void setUserId(Long userId) { this.userId = userId; }

    public Long getSessionId() { return sessionId; }
    public void setSessionId(Long sessionId) { this.sessionId = sessionId; }

    public Long getDeviceId() { return deviceId; }
    public void setDeviceId(Long deviceId) { this.deviceId = deviceId; }

    public LocalDateTime getGrantedAt() { return grantedAt; }
    public void setGrantedAt(LocalDateTime grantedAt) { this.grantedAt = grantedAt; }
}
