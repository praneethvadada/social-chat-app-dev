package com.socialmedia.social.dto;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class ReportResponse {

    private Long id;

    private String status;

    /** True when this reporter had already reported the same target. */
    private boolean alreadyReported;
}
