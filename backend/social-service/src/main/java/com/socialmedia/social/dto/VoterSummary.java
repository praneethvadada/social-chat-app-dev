package com.socialmedia.social.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * One person who voted on a poll option or RSVP'd to an event — deliberately
 * lighter than {@link UserSearchResult} (no bio/follow-state/counts), since
 * this is just a name+avatar row in a "who picked what" list, not a profile
 * card.
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
public class VoterSummary {
    private Long userId;
    private String username;
    private String fullName;
    private String profilePictureUrl;
}
