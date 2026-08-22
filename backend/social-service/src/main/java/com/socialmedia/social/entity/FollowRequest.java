package com.socialmedia.social.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.CreationTimestamp;

import java.time.LocalDateTime;

@Entity
@Table(name = "follow_requests",
    uniqueConstraints = @UniqueConstraint(columnNames = {"requester_id", "receiver_id"}),
    indexes = {
        @Index(name = "idx_requester_id", columnList = "requester_id"),
        @Index(name = "idx_receiver_id", columnList = "receiver_id")
    }
)
@Data
@NoArgsConstructor
@AllArgsConstructor
public class FollowRequest {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "requester_id", nullable = false)
    private Long requesterId;

    @Column(name = "receiver_id", nullable = false)
    private Long receiverId; // Maps to database column 'receiver_id' (the target user receiving the request)

    @Column(name = "status", nullable = false, length = 20)
    private String status = "PENDING"; // Added to match SQL schema

    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    public FollowRequest(Long requesterId, Long receiverId) {
        this.requesterId = requesterId;
        this.receiverId = receiverId;
        this.status = "PENDING";
    }
}
