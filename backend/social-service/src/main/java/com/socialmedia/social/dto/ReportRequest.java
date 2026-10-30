package com.socialmedia.social.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class ReportRequest {

    /** USER, POST or COMMENT. */
    @NotBlank(message = "targetType is required")
    private String targetType;

    @NotNull(message = "targetId is required")
    private Long targetId;

    /** SPAM, HARASSMENT, HATE_SPEECH, NUDITY, VIOLENCE, SCAM, IMPERSONATION or OTHER. */
    @NotBlank(message = "reason is required")
    private String reason;

    @Size(max = 500, message = "Details must not exceed 500 characters")
    private String details;
}
