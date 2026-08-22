package com.socialmedia.chats.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;
import java.time.ZoneId;

/**
 * A group-level ban (G3).
 *
 * Intentionally separate from the personal block list (spec §16, §27):
 *   USER BLOCK   -> private interaction only (owned by social-service)
 *   GROUP REMOVE -> membership deleted, user MAY rejoin
 *   GROUP BAN    -> membership deleted AND user may NOT rejoin
 *
 * A personal block must never be read as a ban, and a ban must never be read
 * as a personal block.
 */
@Entity
@Table(name = "group_bans",
       uniqueConstraints = @UniqueConstraint(name = "uk_conversation_user",
               columnNames = {"conversation_id", "user_id"}))
@Data
@NoArgsConstructor
@AllArgsConstructor
public class GroupBan {

    public enum Status { ACTIVE, LIFTED }

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "conversation_id", nullable = false)
    private Long conversationId;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    @Column(name = "banned_by", nullable = false)
    private Long bannedBy;

    @Column(length = 255)
    private String reason;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 10)
    private Status status = Status.ACTIVE;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    /** NULL = permanent. */
    @Column(name = "expires_at")
    private LocalDateTime expiresAt;

    @Column(name = "lifted_at")
    private LocalDateTime liftedAt;

    @Column(name = "lifted_by")
    private Long liftedBy;

    @PrePersist
    protected void onCreate() {
        if (createdAt == null) createdAt = LocalDateTime.now(ZoneId.of("UTC"));
    }

    /** ACTIVE and not past its expiry. */
    public boolean isCurrentlyActive() {
        if (status != Status.ACTIVE) return false;
        return expiresAt == null || expiresAt.isAfter(LocalDateTime.now(ZoneId.of("UTC")));
    }
}
