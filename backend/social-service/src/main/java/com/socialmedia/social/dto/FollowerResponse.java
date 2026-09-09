package com.socialmedia.social.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.time.LocalDateTime;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class FollowerResponse {
    private Long id;
    private Long userId;
    private LocalDateTime followedAt;

    // Enriched profile fields (added — this used to be a bare follow-
    // relationship record with no name/avatar at all, which is why the
    // frontend's "Online now" panel fell back to the literal string "User"
    // for every single entry: FollowerResponse never carried a name in the
    // first place, so there was nothing for it to display). Nullable since
    // a followed userId can, in principle, have no profile row yet.
    private String username;
    private String fullName;
    private String profilePictureUrl;
    private Boolean isVerified;

    public FollowerResponse(Long id, Long userId, LocalDateTime followedAt) {
        this.id = id;
        this.userId = userId;
        this.followedAt = followedAt;
    }
}
