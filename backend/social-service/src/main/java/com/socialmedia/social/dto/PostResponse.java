package com.socialmedia.social.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.socialmedia.social.entity.Post.PostType;
import com.socialmedia.social.entity.Post.PostVisibility;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class PostResponse {
    private Long id;
    private Long userId;
    private String content;
    private List<String> imageUrls;

    @JsonProperty("isPublic")
    private Boolean isPublic;

    @JsonProperty("visibility")
    private PostVisibility visibility;
    private Integer likesCount;
    private Integer commentsCount;
    private Integer sharesCount;
    private Integer savesCount;
    private String authorName;
    private String authorProfilePictureUrl;
    private Boolean isLikedByCurrentUser;
    private Boolean isSavedByCurrentUser;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;
    private List<com.socialmedia.social.entity.UserProfile> sampleLikers;

    @JsonProperty("postType")
    private PostType postType;

    // POLL only
    private List<PollOptionResponse> pollOptions;
    private Long myPollVoteOptionId;

    // EVENT only
    private LocalDateTime eventStartTime;
    private String eventLocation;
    private Map<String, Long> eventRsvpCounts;
    private String myRsvpStatus;
}
