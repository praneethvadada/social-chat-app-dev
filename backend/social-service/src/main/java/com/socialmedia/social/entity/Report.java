package com.socialmedia.social.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;
import org.hibernate.annotations.CreationTimestamp;

import java.time.LocalDateTime;

/**
 * A user's report of another user, a post or a comment (Play Store UGC policy:
 * users must be able to report objectionable content and users in-app).
 * Reports are reviewed by moderators; status tracks that review.
 */
@Entity
@Table(
    name = "reports",
    uniqueConstraints = @UniqueConstraint(
        name = "uk_report_reporter_target",
        columnNames = {"reporter_id", "target_type", "target_id"}),
    indexes = {
        @Index(name = "idx_report_status_created", columnList = "status, created_at"),
        @Index(name = "idx_report_reported_user", columnList = "reported_user_id")
    }
)
@Data
@NoArgsConstructor
@AllArgsConstructor
public class Report {

    public enum TargetType { USER, POST, COMMENT }

    public enum Reason { SPAM, HARASSMENT, HATE_SPEECH, NUDITY, VIOLENCE, SCAM, IMPERSONATION, OTHER }

    public enum Status { PENDING, REVIEWED, ACTION_TAKEN, DISMISSED }

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "reporter_id", nullable = false)
    private Long reporterId;

    @Enumerated(EnumType.STRING)
    @Column(name = "target_type", nullable = false, length = 20)
    private TargetType targetType;

    @Column(name = "target_id", nullable = false)
    private Long targetId;

    /** Owner of the reported post/comment, or the reported user themselves. */
    @Column(name = "reported_user_id", nullable = false)
    private Long reportedUserId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private Reason reason;

    @Column(length = 500)
    private String details;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 20)
    private Status status = Status.PENDING;

    @CreationTimestamp
    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;
}
