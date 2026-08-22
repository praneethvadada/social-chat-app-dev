package com.socialmedia.social.entity;

import jakarta.persistence.*;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;
import java.time.ZoneId;

/**
 * A 24-hour status (S1).
 *
 * Expiry is data, not a job: every read filters on expiresAt, so a status
 * becomes invisible the moment it expires even if cleanup hasn't run yet.
 */
@Entity
@Table(name = "statuses")
@Data
@NoArgsConstructor
@AllArgsConstructor
public class Status {

    /** Extensible per spec §U - GIF/POLL/MUSIC can be added without schema change. */
    public enum Type { TEXT, IMAGE, VIDEO }

    /** S1 only creates CONTACTS; EXCEPT/ONLY arrive in S4 via status_audience. */
    public enum PrivacyType { CONTACTS, EXCEPT, ONLY }

    public static final int LIFETIME_HOURS = 24;

    /** Max simultaneously-active statuses one user may have. */
    public static final int MAX_ACTIVE_PER_USER = 30;

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "user_id", nullable = false)
    private Long userId;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, length = 10)
    private Type type;

    @Column(length = 1000)
    private String content;

    @Column(name = "media_url", length = 500)
    private String mediaUrl;

    @Column(name = "thumbnail_url", length = 500)
    private String thumbnailUrl;

    @Column(name = "background_color", length = 20)
    private String backgroundColor;

    @Enumerated(EnumType.STRING)
    @Column(name = "privacy_type", nullable = false, length = 20)
    private PrivacyType privacyType = PrivacyType.CONTACTS;

    @Column(name = "allow_replies", nullable = false)
    private Boolean allowReplies = true;

    @Column(name = "allow_reactions", nullable = false)
    private Boolean allowReactions = true;

    @Column(name = "is_deleted", nullable = false)
    private Boolean isDeleted = false;

    @Column(name = "created_at", nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @Column(name = "expires_at", nullable = false)
    private LocalDateTime expiresAt;

    @PrePersist
    protected void onCreate() {
        LocalDateTime now = LocalDateTime.now(ZoneId.of("UTC"));
        if (createdAt == null) createdAt = now;
        if (expiresAt == null) expiresAt = createdAt.plusHours(LIFETIME_HOURS);
    }
}
