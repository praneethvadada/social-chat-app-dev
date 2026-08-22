package com.socialmedia.social.dto;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.socialmedia.social.entity.Post.PostType;
import com.socialmedia.social.entity.Post.PostVisibility;
import jakarta.validation.constraints.AssertTrue;
import jakarta.validation.constraints.Size;
import lombok.Data;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

@Data
public class PostRequest {

    @Size(max = 5000, message = "Content cannot exceed 5000 characters")
    private String content;

    private List<String> imageUrls = new ArrayList<>();

    @JsonProperty("isPublic")
    private Boolean isPublic = true;

    @JsonProperty("visibility")
    private PostVisibility visibility = PostVisibility.PUBLIC;

    @JsonProperty("postType")
    private PostType postType = PostType.TEXT;

    /** POLL only: 2-6 answer options. */
    private List<String> pollOptions;

    /** POLL only, optional: index into pollOptions the maker marks as correct (quiz-style). */
    private Integer correctOptionIndex;

    /** EVENT only. */
    private LocalDateTime eventStartTime;
    private String eventLocation;

    @AssertTrue(message = "Post must have either content or images")
    private boolean isValid() {
        boolean hasContent = content != null && !content.trim().isEmpty();
        if (postType == PostType.POLL) {
            long realOptions = pollOptions == null ? 0
                    : pollOptions.stream().filter(o -> o != null && !o.trim().isEmpty()).count();
            return hasContent && realOptions >= 2 && realOptions <= 6;
        }
        if (postType == PostType.EVENT) {
            return hasContent && eventStartTime != null;
        }
        boolean hasImages = imageUrls != null && !imageUrls.isEmpty();
        return hasContent || hasImages;
    }
}
