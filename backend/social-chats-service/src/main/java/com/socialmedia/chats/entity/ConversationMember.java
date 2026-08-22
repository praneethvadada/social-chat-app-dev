package com.socialmedia.chats.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;
import java.time.ZoneId;

/**
 * Membership of a user in a conversation, with a group role.
 * DIRECT conversations have two MEMBER rows; GROUP conversations have exactly
 * one OWNER, any number of ADMINs and MEMBERs (enforced in service logic).
 */
@Entity
@Table(name = "conversation_members",
       uniqueConstraints = @UniqueConstraint(name = "uk_conversation_user",
               columnNames = {"conversation_id", "user_id"}))
@Data
@NoArgsConstructor
@AllArgsConstructor
public class ConversationMember {

    public enum Role { OWNER, ADMIN, MEMBER }

    public enum NotificationLevel { ALL, MENTIONS, NONE }

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "conversation_id", nullable = false)
    private Long conversationId;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 10)
    private Role role = Role.MEMBER;

    @Column(name = "joined_at", nullable = false, updatable = false)
    private LocalDateTime joinedAt;

    @Column(name = "muted_until")
    private LocalDateTime mutedUntil;

    /** Last time this member opened the conversation — drives the unread badge. */
    @Column(name = "last_read_at")
    private LocalDateTime lastReadAt;

    /** G5 (spec §U): ALL, MENTIONS or NONE. */
    @Enumerated(EnumType.STRING)
    @Column(name = "notification_level", nullable = false, length = 10)
    private NotificationLevel notificationLevel = NotificationLevel.ALL;

    @PrePersist
    protected void onCreate() {
        if (joinedAt == null) {
            joinedAt = LocalDateTime.now(ZoneId.of("UTC"));
        }
    }
}
