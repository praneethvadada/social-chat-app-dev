package com.socialmedia.social.dto;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class BlockedUserResponse {
    
    private Long id;
    private Long blockedUserId;
    private String blockedUsername;
    private String blockedProfilePicUrl;
    private String reason;
    private LocalDateTime blockedAt;
}
