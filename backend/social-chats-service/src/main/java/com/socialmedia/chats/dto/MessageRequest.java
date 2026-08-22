package com.socialmedia.chats.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.annotation.JsonAnySetter;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class MessageRequest {
    
    @NotNull(message = "Receiver ID is required")
    @JsonProperty("receiverId")
    private Long receiverId;
    
    @NotBlank(message = "Message content cannot be empty")
    @Size(max = 2000, message = "Message cannot exceed 2000 characters")
    private String content;
    
    private String mediaUrl;
    
    private String clientMessageId;
    
    // Explicit getter/setter for Jackson
    public Long getReceiverId() {
        return receiverId;
    }
    
    public void setReceiverId(Long receiverId) {
        this.receiverId = receiverId;
    }
    
    // Handle alternate field names that might come from STOMP
    @JsonAnySetter
    public void handleAlternateNames(String key, Object value) {
        if ("recipientId".equals(key) && this.receiverId == null) {
            try {
                this.receiverId = Long.parseLong(value.toString());
            } catch (NumberFormatException e) {
                // ignore
            }
        }
    }

    // S3: optional reference when replying to someone's 24h status
    private Long replyToStatusId;
    private String replyToStatusType;
    private String replyToStatusPreview;
    private String statusReaction;
}
