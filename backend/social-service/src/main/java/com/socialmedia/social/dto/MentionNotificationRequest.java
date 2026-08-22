package com.socialmedia.social.dto;

import lombok.Data;
import java.util.List;

@Data
public class MentionNotificationRequest {
    private List<Long> mentionedUserIds;
    private Long postId;
    private String postContent;
    private Long actorId;
}
