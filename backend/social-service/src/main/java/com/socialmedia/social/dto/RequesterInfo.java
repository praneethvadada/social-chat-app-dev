package com.socialmedia.social.dto;

import java.time.LocalDateTime;

public class RequesterInfo {
    private Long userId;
    private String username;
    private String fullName;
    private String profilePictureUrl;
    private Integer mutualCount;

    public Long getUserId() { return userId; }
    public void setUserId(Long userId) { this.userId = userId; }
    public String getUsername() { return username; }
    public void setUsername(String username) { this.username = username; }
    public String getFullName() { return fullName; }
    public void setFullName(String fullName) { this.fullName = fullName; }
    public String getProfilePictureUrl() { return profilePictureUrl; }
    public void setProfilePictureUrl(String profilePictureUrl) { this.profilePictureUrl = profilePictureUrl; }
    public Integer getMutualCount() { return mutualCount; }
    public void setMutualCount(Integer mutualCount) { this.mutualCount = mutualCount; }
}
