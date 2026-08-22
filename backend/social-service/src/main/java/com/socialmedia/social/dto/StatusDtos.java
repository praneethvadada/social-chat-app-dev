package com.socialmedia.social.dto;

import com.socialmedia.social.entity.Status;
import jakarta.validation.constraints.Size;
import lombok.Data;

import java.time.LocalDateTime;
import java.util.List;

/** DTOs for the 24-hour status feature (S1). */
public class StatusDtos {

    @Data
    public static class CreateStatusRequest {
        /** TEXT, IMAGE or VIDEO. */
        private Status.Type type = Status.Type.TEXT;

        @Size(max = 1000, message = "Status text cannot exceed 1000 characters")
        private String content;

        private String mediaUrl;
        private String thumbnailUrl;
        private String backgroundColor;
        private Boolean allowReplies = true;
        private Boolean allowReactions = true;

        /** S4: CONTACTS (default), EXCEPT or ONLY. */
        private Status.PrivacyType privacyType = Status.PrivacyType.CONTACTS;

        /**
         * S4: the people this applies to - excluded users for EXCEPT, the
         * allow-list for ONLY. Ignored for CONTACTS.
         */
        private java.util.List<Long> audienceUserIds = new java.util.ArrayList<>();
    }

    /** One status item inside a user's ring. */
    @Data
    public static class StatusItem {
        private Long id;
        private String type;
        private String content;
        private String mediaUrl;
        private String thumbnailUrl;
        private String backgroundColor;
        private LocalDateTime createdAt;
        private LocalDateTime expiresAt;
        private boolean seen;        // has the requesting viewer seen it
        private long viewCount;      // only meaningful for the owner
        private boolean allowReplies;
        private boolean allowReactions;
        /** S3: this viewer's own reaction emoji, or null. */
        private String myReaction;
        /** S3: emoji -> count. Populated for the owner only. */
        private java.util.Map<String, Long> reactionCounts;
        /** S4: CONTACTS / EXCEPT / ONLY (owner-facing). */
        private String privacyType;
    }

    @Data
    public static class ReactRequest {
        /** Emoji to set, or null/empty to clear the reaction. */
        private String reaction;
    }

    /** All active statuses of one author, plus ring state for the viewer. */
    @Data
    public static class UserStatusGroup {
        private Long userId;
        private String username;
        private String fullName;
        private String profilePictureUrl;
        private boolean allSeen;             // drives the ring style
        private LocalDateTime latestAt;
        private List<StatusItem> statuses;
    }

    @Data
    public static class StatusFeedResponse {
        /** The requesting user's own statuses (may be empty). */
        private UserStatusGroup myStatus;
        /** Others' statuses: unseen groups first, then seen. */
        private List<UserStatusGroup> recent;
    }

    @Data
    public static class StatusViewerInfo {
        private Long userId;
        private String username;
        private String fullName;
        private String profilePictureUrl;
        private LocalDateTime viewedAt;
        private String reaction;
    }
}
