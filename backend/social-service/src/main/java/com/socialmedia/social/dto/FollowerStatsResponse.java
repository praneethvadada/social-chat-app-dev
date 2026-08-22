package com.socialmedia.social.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class FollowerStatsResponse {
    private Long userId;
    private long followersCount;
    private long followingCount;
    private boolean isFollowing;
    private boolean isFollowedBy;
    private boolean isMutual;
}
