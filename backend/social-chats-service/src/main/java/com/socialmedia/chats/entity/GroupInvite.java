package com.socialmedia.chats.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;
import java.time.ZoneId;

/** A shareable group invite code (G5, spec §O). Revocable and resettable. */
@Entity
@Table(name = "group_invites")
@Data
@NoArgsConstructor
@AllArgsConstructor
public class GroupInvite {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "conversation_id", nullable = false)
    private Long conversationId;

    @Column(nullable = false, unique = true, length = 32)
    private String code;

    @Column(name = "created_by", nullable = false)
    private Long createdBy;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    /** NULL = never expires. */
    @Column(name = "expires_at")
    private LocalDateTime expiresAt;

    @Column(name = "is_active", nullable = false)
    private Boolean isActive = true;

    @PrePersist
    protected void onCreate() {
        if (createdAt == null) createdAt = LocalDateTime.now(ZoneId.of("UTC"));
    }

    /** Active and not past expiry. */
    public boolean isUsable() {
        if (!Boolean.TRUE.equals(isActive)) return false;
        return expiresAt == null || expiresAt.isAfter(LocalDateTime.now(ZoneId.of("UTC")));
    }
}
