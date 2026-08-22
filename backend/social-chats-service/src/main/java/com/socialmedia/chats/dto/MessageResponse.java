package com.socialmedia.chats.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;
import com.fasterxml.jackson.annotation.JsonFormat;

import java.time.LocalDateTime;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class MessageResponse {
    private Long id;
    private Long senderId;
    private String senderName;
    private String senderProfilePictureUrl;
    private Long receiverId;
    private String content;
    private String mediaUrl;
    private Boolean isRead;

    @JsonFormat(shape = JsonFormat.Shape.STRING, pattern = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", timezone = "UTC")
    private LocalDateTime readAt;

    @JsonFormat(shape = JsonFormat.Shape.STRING, pattern = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", timezone = "UTC")
    private LocalDateTime createdAt;
    private String clientMessageId;  // ΓåÉ Echo back client's optimistic ID for reconciliation
    private String status;  // "sending", "sent", or "read"
    private Long conversationId;  // G1: set for group messages (used for topic routing)

    // G2: system messages ("X was added"). messageType is USER or SYSTEM.
    private String messageType;
    private String systemEvent;
    private Long systemActorId;
    private Long systemTargetId;

    // S3: status-reply reference (snapshot; survives status expiry)
    private Long replyToStatusId;
    private String replyToStatusType;
    private String replyToStatusPreview;
    private String statusReaction;

    // G4: reply snapshot, pin/delete state, and reaction summary
    private Long replyToMessageId;
    private Long replyToSenderId;
    private String replyToSenderName;
    private String replyToPreview;
    private Boolean isPinned;
    private Boolean isDeleted;
    private java.util.Map<String, Long> reactionCounts;
    private String myReaction;

    // GAP-2/3: media descriptor + forwarded marker
    private String mediaType;
    private String mediaName;
    private Boolean isForwarded;
}
