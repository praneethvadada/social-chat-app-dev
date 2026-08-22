package com.socialmedia.social.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class UserSearchResult {
    
    private Long userId;
    private String username;
    private String fullName;
    private String bio;
    private String profilePictureUrl;
    private Boolean isPrivate;
    private Boolean isVerified;
    private Boolean isFollowing;
    private Long followersCount;
    private Long followingCount;
}
