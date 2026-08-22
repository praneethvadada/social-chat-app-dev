package com.socialmedia.chats.dto;

import lombok.Data;

import java.time.LocalDateTime;
import java.util.List;

/** Entry for the groups section of the chats list + group creation response. */
@Data
public class GroupSummary {
    private Long id;
    private String name;
    private String description;
    private String photoUrl;
    private int memberCount;
    private String myRole;                 // OWNER / ADMIN / MEMBER
    private String lastMessageContent;
    private String lastMessageSenderName;
    private LocalDateTime lastMessageTime;
    private LocalDateTime createdAt;
    /** Member ids that could not be added at creation (neutral - no reason exposed). */
    private List<Long> skippedMemberIds;
    /** Messages since the viewer's last read — drives the Group Spaces badge. */
    private long unreadCount;

    // G5: per-group settings (spec §R/§U)
    private String whoCanSend;
    private String whoCanEditInfo;
    private String whoCanAddMembers;
    private String whoCanPin;
    private Boolean approveNewMembers;
    private String myNotificationLevel;
}
