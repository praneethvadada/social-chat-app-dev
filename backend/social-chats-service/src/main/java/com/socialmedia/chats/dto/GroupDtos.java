package com.socialmedia.chats.dto;

import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.Size;
import lombok.Data;

import java.time.LocalDateTime;
import java.util.List;

/** DTOs for G2 group role/member management. */
public class GroupDtos {

    @Data
    public static class AddMembersRequest {
        @NotEmpty(message = "Select at least one member")
        private List<Long> memberIds;
    }

    @Data
    public static class RoleChangeRequest {
        /** ADMIN or MEMBER (OWNER only via transfer-owner). */
        private String role;
    }

    @Data
    public static class TransferOwnerRequest {
        private Long newOwnerId;
    }

    @Data
    public static class UpdateGroupInfoRequest {
        @Size(max = 100, message = "Group name cannot exceed 100 characters")
        private String name;

        @Size(max = 500, message = "Description cannot exceed 500 characters")
        private String description;

        private String photoUrl;
    }

    /** Member enriched with profile data from auth-service. */
    @Data
    public static class GroupMemberInfo {
        private Long userId;
        private String username;
        private String fullName;
        private String profilePictureUrl;
        private String role;
        private LocalDateTime joinedAt;
    }

    /** Result of an add-members call - skipped ids carry no reason (§25). */
    @Data
    public static class AddMembersResult {
        private List<Long> addedMemberIds;
        private List<Long> skippedMemberIds;
        private int memberCount;
    }
}
