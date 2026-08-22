package com.socialmedia.social.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.CreationTimestamp;

import java.time.LocalDateTime;

@Entity
@Table(name = "notifications",
    indexes = {
        @Index(name = "idx_user_read", columnList = "user_id, is_read"),
        @Index(name = "idx_created_at", columnList = "created_at")
    }
)
@Data
@NoArgsConstructor
@AllArgsConstructor
public class Notification {
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "user_id", nullable = false)
    private Long userId; // recipient of the notification

    @Column(name = "type", nullable = false)
    private String type; // LIKE, COMMENT, FOLLOW, MESSAGE, etc

    @Column(name = "actor_id")
    private Long actorId; // user who triggered the notification

    @Column(name = "target_id")
    private Long targetId; // Post/Comment ID the notification is about

    @Column(name = "content", length = 1024)
    private String content;

    @Column(name = "is_read", nullable = false)
    private Boolean isRead = false;

    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;
}
