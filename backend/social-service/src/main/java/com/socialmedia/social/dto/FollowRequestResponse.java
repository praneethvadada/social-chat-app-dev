package com.socialmedia.social.dto;

import java.time.LocalDateTime;

public class FollowRequestResponse {
    private Long id;
    private RequesterInfo requester;
    private LocalDateTime createdAt;

    public Long getId() { return id; }
    public void setId(Long id) { this.id = id; }
    public RequesterInfo getRequester() { return requester; }
    public void setRequester(RequesterInfo requester) { this.requester = requester; }
    public LocalDateTime getCreatedAt() { return createdAt; }
    public void setCreatedAt(LocalDateTime createdAt) { this.createdAt = createdAt; }
}
