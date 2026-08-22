package com.socialmedia.chats.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;
import java.time.ZoneId;

/**
 * A conversation is the container for messages: DIRECT (1:1) or GROUP.
 *
 * DIRECT conversations carry a directKey "minUserId:maxUserId" with a unique
 * constraint, guaranteeing at most one direct conversation per user pair and
 * making find-or-create race-safe (concurrent creators: one insert wins, the
 * loser re-reads).
 */
@Entity
@Table(name = "conversations")
@Data
@NoArgsConstructor
@AllArgsConstructor
public class Conversation {

    public enum Type { DIRECT, GROUP }

    /** Who is allowed to perform a given group action. */
    public enum PermissionLevel { EVERYONE, ADMINS }

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 10)
    private Type type;

    /** Group name; null for DIRECT. */
    @Column(length = 100)
    private String name;

    @Column(length = 500)
    private String description;

    @Column(name = "photo_url")
    private String photoUrl;

    @Column(name = "created_by", nullable = false)
    private Long createdBy;

    @Column(name = "direct_key", length = 41, unique = true)
    private String directKey;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "updated_at", nullable = false)
    private LocalDateTime updatedAt;

    // ---- G5: per-group permissions (spec §R). Role-based, not hard-coded. ----

    /** Who may post messages. */
    @Enumerated(EnumType.STRING)
    @Column(name = "who_can_send", nullable = false, length = 10)
    private PermissionLevel whoCanSend = PermissionLevel.EVERYONE;

    @Enumerated(EnumType.STRING)
    @Column(name = "who_can_edit_info", nullable = false, length = 10)
    private PermissionLevel whoCanEditInfo = PermissionLevel.ADMINS;

    @Enumerated(EnumType.STRING)
    @Column(name = "who_can_add_members", nullable = false, length = 10)
    private PermissionLevel whoCanAddMembers = PermissionLevel.ADMINS;

    @Enumerated(EnumType.STRING)
    @Column(name = "who_can_pin", nullable = false, length = 10)
    private PermissionLevel whoCanPin = PermissionLevel.ADMINS;

    /** When true, invite-link joins become join requests instead (spec §P). */
    @Column(name = "approve_new_members", nullable = false)
    private Boolean approveNewMembers = false;

    @PrePersist
    protected void onCreate() {
        LocalDateTime now = LocalDateTime.now(ZoneId.of("UTC"));
        createdAt = now;
        updatedAt = now;
    }

    @PreUpdate
    protected void onUpdate() {
        updatedAt = LocalDateTime.now(ZoneId.of("UTC"));
    }

    /** Canonical direct-conversation key for a user pair, order-independent. */
    public static String directKeyFor(Long userA, Long userB) {
        long lo = Math.min(userA, userB);
        long hi = Math.max(userA, userB);
        return lo + ":" + hi;
    }
}
