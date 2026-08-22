package com.socialmedia.social.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class PollOptionResponse {
    private Long id;
    private String text;
    private Long voteCount;
    /** Only ever true here once the requesting user has voted — never leaked pre-vote. */
    private Boolean isCorrect;
}
