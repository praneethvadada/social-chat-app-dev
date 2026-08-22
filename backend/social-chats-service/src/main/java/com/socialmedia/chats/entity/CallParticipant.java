package com.socialmedia.chats.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.Instant;

/**
 * Per-user state within a single call (1:1 or group). Backbone for group
 * roster/identity, "join later", max-participant enforcement, per-member
 * call history, and cross-call-type busy detection — see CallService.
 */
@Entity
@Table(name = "call_participants",
       uniqueConstraints = @UniqueConstraint(name = "uk_call_user", columnNames = {"call_id", "user_id"}))
@Data
@NoArgsConstructor
@AllArgsConstructor
public class CallParticipant {

    public enum Status { INVITED, RINGING, JOINED, DECLINED, LEFT, MISSED }

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "call_id", nullable = false)
    private Long callId;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    @Column(name = "agora_uid")
    private Integer agoraUid;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 10)
    private Status status = Status.INVITED;

    @Column(name = "invited_at")
    private Instant invitedAt = Instant.now();

    @Column(name = "joined_at")
    private Instant joinedAt;

    @Column(name = "left_at")
    private Instant leftAt;

    @Column(name = "deleted_for_user")
    private Boolean deletedForUser = false;
}
