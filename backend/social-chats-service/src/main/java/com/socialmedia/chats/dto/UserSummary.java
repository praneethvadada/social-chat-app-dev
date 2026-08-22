package com.socialmedia.chats.dto;

import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * Lightweight user profile the chats service reads from auth-service over REST.
 * Chats-service does NOT own the users table; it only needs display fields.
 * Online status is NOT here - it is overlaid locally from PresenceService.
 */
@Data
@NoArgsConstructor
public class UserSummary {
    private Long userId;
    private String username;
    private String fullName;
    private String profilePictureUrl;
    private Boolean isVerified;
}
