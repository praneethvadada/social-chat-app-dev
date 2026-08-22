package com.socialmedia.social.dto;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import lombok.Data;

@Data
public class ShareRequest {
    
    @NotNull(message = "Post ID is required")
    private Long postId;
    
    @Size(max = 500, message = "Share note cannot exceed 500 characters")
    private String shareNote;
}
