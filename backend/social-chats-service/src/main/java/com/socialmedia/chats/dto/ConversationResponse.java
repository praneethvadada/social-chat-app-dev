package com.socialmedia.chats.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;
import com.fasterxml.jackson.annotation.JsonFormat;

import java.time.LocalDateTime;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class ConversationResponse {
    /** Phase 4: the DIRECT conversation's real id, for /conversations/{id}/sync. Null on legacy rows predating G0. */
    private Long conversationId;
    private Long userId;
    private String username;
    private String fullName;
    private String profilePictureUrl;
    private Boolean isVerified;
    private String lastMessageContent;
    private String lastMessageMediaUrl;
    
    @JsonFormat(shape = JsonFormat.Shape.STRING, pattern = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", timezone = "UTC")
    private LocalDateTime lastMessageTime;
    private Long unreadCount;
    private Boolean isLastMessageFromMe;
    private Boolean isOnline;
}
