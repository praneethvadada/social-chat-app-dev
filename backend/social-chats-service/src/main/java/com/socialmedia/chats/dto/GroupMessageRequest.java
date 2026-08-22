package com.socialmedia.chats.dto;

import lombok.Data;

@Data
public class GroupMessageRequest {

    /** Optional when media is attached (a media-only message has no text). */
    private String content;

    private String mediaUrl;

    private String clientMessageId;

    /** G4: id of the message being replied to (must be in the same conversation). */
    private Long replyToMessageId;

    /** GAP-2: media type + original name, so documents render properly. */
    private String mediaType;
    private String mediaName;
}
