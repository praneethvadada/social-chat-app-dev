package com.socialmedia.social.dto;

import jakarta.validation.constraints.Size;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class BlockRequest {
    
    @Size(max = 200, message = "Reason must not exceed 200 characters")
    private String reason;
}
