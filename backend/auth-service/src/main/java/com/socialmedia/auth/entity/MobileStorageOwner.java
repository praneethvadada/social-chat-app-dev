package com.socialmedia.auth.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;

import java.time.LocalDateTime;

/**
 * Exactly one row per user — userId IS the primary key, so "exactly one
 * mobile device owns local chat storage" is a database-level guarantee
 * (there's no separate status flag to get out of sync), not an
 * application-enforced invariant. A device that currently isn't the row's
 * deviceId simply isn't the owner; there's nothing else to check.
 */
@Entity
@Table(name = "mobile_storage_owner")
public class MobileStorageOwner {

    @Id
    @Column(name = "user_id")
    private Long userId;

    @Column(name = "device_id", nullable = false)
    private Long deviceId;

    @Column(name = "granted_at", nullable = false)
    private LocalDateTime grantedAt;

    public MobileStorageOwner() {
    }

    public MobileStorageOwner(Long userId, Long deviceId, LocalDateTime grantedAt) {
        this.userId = userId;
        this.deviceId = deviceId;
        this.grantedAt = grantedAt;
    }

    public Long getUserId() { return userId; }
    public void setUserId(Long userId) { this.userId = userId; }

    public Long getDeviceId() { return deviceId; }
    public void setDeviceId(Long deviceId) { this.deviceId = deviceId; }

    public LocalDateTime getGrantedAt() { return grantedAt; }
    public void setGrantedAt(LocalDateTime grantedAt) { this.grantedAt = grantedAt; }
}
