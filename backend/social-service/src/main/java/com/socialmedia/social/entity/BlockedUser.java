package com.socialmedia.social.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.CreationTimestamp;

import java.time.LocalDateTime;

@Entity
@Table(
    name = "blocked_users",
    uniqueConstraints = @UniqueConstraint(columnNames = {"blocker_id", "blocked_id"}),
    indexes = {
        @Index(name = "idx_blocker_id", columnList = "blocker_id"),
        @Index(name = "idx_blocked_id", columnList = "blocked_id")
    }
)
@Data
@NoArgsConstructor
@AllArgsConstructor
public class BlockedUser {
    
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    
    @Column(name = "blocker_id", nullable = false)
    private Long blockerId;
    
    @Column(name = "blocked_id", nullable = false)
    private Long blockedId;
    
    @Column(name = "reason")
    private String reason;
    
    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;
}
