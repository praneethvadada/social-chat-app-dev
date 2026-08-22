package com.socialmedia.chats.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;
import java.time.ZoneId;

/**
 * One user's reaction to one message (G4).
 * Unique per (message, user) - reacting again replaces, tapping the same
 * reaction removes.
 */
@Entity
@Table(name = "message_reactions",
       uniqueConstraints = @UniqueConstraint(name = "uk_message_user",
               columnNames = {"message_id", "user_id"}))
@Data
@NoArgsConstructor
@AllArgsConstructor
public class MessageReaction {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "message_id", nullable = false)
    private Long messageId;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    /** Stable key (heart, laugh, ...) - never the emoji glyph. */
    @Column(nullable = false, length = 20)
    private String reaction;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @PrePersist
    protected void onCreate() {
        if (createdAt == null) createdAt = LocalDateTime.now(ZoneId.of("UTC"));
    }
}
