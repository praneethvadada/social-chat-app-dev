package com.socialmedia.chats.entity;

import java.time.LocalDateTime;

import org.hibernate.annotations.CreationTimestamp;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Entity
@Table(name = "chat_deletions", 
    uniqueConstraints = {
        @UniqueConstraint(columnNames = {"user_id", "other_user_id"})
    },
    indexes = {
        @Index(name = "idx_user_id", columnList = "user_id"),
        @Index(name = "idx_deleted_at", columnList = "deleted_at")
    })
@Data
@NoArgsConstructor
@AllArgsConstructor
public class ChatDeletion {
    
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    
    @Column(nullable = false)
    private Long userId;
    
    @Column(nullable = false)
    private Long otherUserId;
    
    @CreationTimestamp
    @Column(nullable = false, updatable = false)
    private LocalDateTime deletedAt;
}
