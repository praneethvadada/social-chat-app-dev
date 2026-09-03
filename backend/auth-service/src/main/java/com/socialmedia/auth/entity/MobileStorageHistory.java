package com.socialmedia.auth.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;

import java.time.LocalDateTime;

/** Append-only audit trail of every mobile-storage claim/transfer. */
@Entity
@Table(name = "mobile_storage_history", indexes = {
    @Index(name = "idx_mobile_storage_history_user", columnList = "user_id,transferred_at")
})
public class MobileStorageHistory {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    // Null for the very first-ever claim (no prior owner to transfer from).
    @Column(name = "from_device_id")
    private Long fromDeviceId;

    @Column(name = "to_device_id", nullable = false)
    private Long toDeviceId;

    @Column(name = "transferred_at", nullable = false)
    private LocalDateTime transferredAt;

    public MobileStorageHistory() {
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public Long getUserId() { return userId; }
    public void setUserId(Long userId) { this.userId = userId; }

    public Long getFromDeviceId() { return fromDeviceId; }
    public void setFromDeviceId(Long fromDeviceId) { this.fromDeviceId = fromDeviceId; }

    public Long getToDeviceId() { return toDeviceId; }
    public void setToDeviceId(Long toDeviceId) { this.toDeviceId = toDeviceId; }

    public LocalDateTime getTransferredAt() { return transferredAt; }
    public void setTransferredAt(LocalDateTime transferredAt) { this.transferredAt = transferredAt; }
}
