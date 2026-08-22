package com.socialmedia.social.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;
import java.time.ZoneId;

/** One viewer's view of a status. Unique per (status, viewer). */
@Entity
@Table(name = "status_views",
       uniqueConstraints = @UniqueConstraint(name = "uk_status_viewer",
               columnNames = {"status_id", "viewer_id"}))
@Data
@NoArgsConstructor
@AllArgsConstructor
public class StatusView {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "status_id", nullable = false)
    private Long statusId;

    @Column(name = "viewer_id", nullable = false)
    private Long viewerId;

    @Column(name = "viewed_at", nullable = false)
    private LocalDateTime viewedAt;

    /** Emoji reaction - populated in S3. */
    @Column(length = 20)
    private String reaction;

    @PrePersist
    protected void onCreate() {
        if (viewedAt == null) viewedAt = LocalDateTime.now(ZoneId.of("UTC"));
    }
}
