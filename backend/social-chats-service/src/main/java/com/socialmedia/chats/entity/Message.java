package com.socialmedia.chats.entity;

import java.time.LocalDateTime;
import java.time.ZonedDateTime;
import java.time.ZoneId;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import jakarta.persistence.PrePersist;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Entity
@Table(name = "messages", indexes = {
    @Index(name = "idx_sender_receiver", columnList = "senderId,receiverId"),
    @Index(name = "idx_receiver_read", columnList = "receiverId,isRead")
},
    uniqueConstraints = {
        // Phase 4: makes a retried offline send idempotent at the DB level, not
        // just app-level - MySQL permits unlimited NULLs through a unique index,
        // so rows without a clientMessageId (none expected from the current
        // client, but not enforced elsewhere) are unaffected.
        @UniqueConstraint(name = "uk_sender_client_message_id", columnNames = {"senderId", "clientMessageId"})
    })
@Data
@NoArgsConstructor
@AllArgsConstructor
public class Message {
    
    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;
    
    @Column(nullable = false)
    private Long senderId;

    /** Direct-message recipient. NULL for GROUP messages (delivery is by conversation). */
    @Column
    private Long receiverId;

    /**
     * Conversation container (G0). Nullable during transition: legacy rows may
     * lack it, but every new message is stamped. GROUP messages (G1) will rely
     * on this exclusively.
     */
    @Column(name = "conversation_id")
    private Long conversationId;
    
    @Column(columnDefinition = "TEXT", nullable = false)
    private String content;
    
    @Column
    private String mediaUrl;
    
    @Column
    private String clientMessageId;
    
    @Column(nullable = false)
    private Boolean isRead = false;
    
    @Column
    private LocalDateTime readAt;
    
    @Column(nullable = false, updatable = false)
    private LocalDateTime createdAt;

    /**
     * G2: system messages ("X was added", "Y is now admin") live in the message
     * stream so group history is self-describing. Rendered differently by the
     * client. NOTE: block/unblock never produces one (spec §24).
     */
    @Column(name = "message_type", nullable = false, length = 10)
    private String messageType = "USER";

    @Column(name = "system_event", length = 30)
    private String systemEvent;

    @Column(name = "system_actor_id")
    private Long systemActorId;

    @Column(name = "system_target_id")
    private Long systemTargetId;

    /**
     * S3: when this DM is a reply to a 24h status, we snapshot a reference to
     * it. A snapshot (not a live lookup) because the status expires in 24h -
     * the chat bubble must still render afterwards, and statuses live in a
     * different service/database entirely.
     */
    @Column(name = "reply_to_status_id")
    private Long replyToStatusId;

    @Column(name = "reply_to_status_type", length = 10)
    private String replyToStatusType;

    @Column(name = "reply_to_status_preview", length = 500)
    private String replyToStatusPreview;

    /**
     * Set when this message is a *reaction* to the referenced status rather
     * than a typed reply. Stored separately from content so the bubble can
     * render "Reacted to status" instead of quoting an emoji as if it were
     * a sentence.
     */
    @Column(name = "status_reaction", length = 16)
    private String statusReaction;

    // ---- G4: reply / pin / delete ----

    /**
     * Reply target. The sender + preview are SNAPSHOTTED so a quoted bubble
     * still renders after the original is deleted, and so rendering a page of
     * messages needs no extra lookup per bubble.
     */
    @Column(name = "reply_to_message_id")
    private Long replyToMessageId;

    @Column(name = "reply_to_sender_id")
    private Long replyToSenderId;

    @Column(name = "reply_to_preview", length = 300)
    private String replyToPreview;

    @Column(name = "is_pinned", nullable = false)
    private Boolean isPinned = false;

    @Column(name = "pinned_at")
    private LocalDateTime pinnedAt;

    @Column(name = "pinned_by")
    private Long pinnedBy;

    /** Tombstone: the row stays so replies quoting it still make sense. */
    @Column(name = "is_deleted", nullable = false)
    private Boolean isDeleted = false;

    @Column(name = "deleted_at")
    private LocalDateTime deletedAt;

    @Column(name = "deleted_by")
    private Long deletedBy;

    /** True when this message was forwarded from another conversation. */
    @Column(name = "is_forwarded", nullable = false)
    private Boolean isForwarded = false;

    /** IMAGE, VIDEO or DOCUMENT - lets the client pick a renderer without sniffing the URL. */
    @Column(name = "media_type", length = 10)
    private String mediaType;

    /** Original filename, shown for documents. */
    @Column(name = "media_name")
    private String mediaName;
    
    // ✅ NEW: Force UTC timezone on message creation
    @PrePersist
    protected void onCreate() {
        if (this.createdAt == null) {
            // Set createdAt to current UTC time
            this.createdAt = LocalDateTime.now(ZoneId.of("UTC"));
        }
    }
}
