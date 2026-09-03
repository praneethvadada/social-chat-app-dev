package com.socialmedia.auth.entity;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;

import java.time.LocalDateTime;

/**
 * Append-only security audit log. metadata is a small serialized-JSON string
 * (event-specific context) — NEVER a secret: no passwords, OTPs, or bearer
 * tokens. As of Phase 8, every value below is actually emitted somewhere.
 * PHONE_CHANGED/EMAIL_CHANGED fire for linkVerifiedPhone/linkVerifiedEmail
 * too (adding a first phone/email to an account) — there's deliberately no
 * separate "number/address CHANGED to a different one" API anywhere in this
 * service (see User.phoneNumber's own doc comment: once verified, a phone
 * number is immutable through the API), so these names cover "this
 * identity-contact-method assertion on the account changed" more broadly
 * than the literal word "changed" might suggest, rather than adding
 * near-duplicate PHONE_LINKED/EMAIL_LINKED values for the same category of
 * event.
 */
@Entity
@Table(name = "security_events", indexes = {
    @Index(name = "idx_user_created", columnList = "user_id,created_at")
})
public class SecurityEvent {

    public enum EventType {
        LOGIN,
        /** Post-Phase-10: a login attempt that resolved to a real account but failed (wrong password, or attempted against an already-locked account) — user-requested push-notification trigger, see SecurityEventService's own PUSH_NOTIFIED_TYPES. */
        LOGIN_FAILED,
        LOGOUT,
        NEW_DEVICE,
        PASSWORD_CHANGED,
        EMAIL_CHANGED,
        PHONE_CHANGED,
        TWO_FA_ENABLED,
        TWO_FA_DISABLED,
        TWO_FA_METHOD_CHANGED,
        SESSION_REVOKED,
        WEB_SESSION_REPLACED,
        LOCAL_STORAGE_DEVICE_CHANGED,
        ACCOUNT_DELETED
    }

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    @Column(name = "event_type", nullable = false, length = 40)
    private String eventType;

    @Column(name = "device_id")
    private Long deviceId;

    @Column(name = "session_id")
    private Long sessionId;

    @Column(name = "ip_address", length = 45)
    private String ipAddress;

    @Column(name = "user_agent", length = 255)
    private String userAgent;

    @Column(columnDefinition = "TEXT")
    private String metadata;

    @Column(name = "created_at", nullable = false)
    private LocalDateTime createdAt;

    public SecurityEvent() {
    }

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }

    public Long getUserId() { return userId; }
    public void setUserId(Long userId) { this.userId = userId; }

    public String getEventType() { return eventType; }
    public void setEventType(String eventType) { this.eventType = eventType; }

    public Long getDeviceId() { return deviceId; }
    public void setDeviceId(Long deviceId) { this.deviceId = deviceId; }

    public Long getSessionId() { return sessionId; }
    public void setSessionId(Long sessionId) { this.sessionId = sessionId; }

    public String getIpAddress() { return ipAddress; }
    public void setIpAddress(String ipAddress) { this.ipAddress = ipAddress; }

    public String getUserAgent() { return userAgent; }
    public void setUserAgent(String userAgent) { this.userAgent = userAgent; }

    public String getMetadata() { return metadata; }
    public void setMetadata(String metadata) { this.metadata = metadata; }

    public LocalDateTime getCreatedAt() { return createdAt; }
    public void setCreatedAt(LocalDateTime createdAt) { this.createdAt = createdAt; }
}
