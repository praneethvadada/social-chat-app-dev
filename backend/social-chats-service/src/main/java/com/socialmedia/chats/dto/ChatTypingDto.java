package com.socialmedia.chats.dto;

import java.time.LocalDateTime;

public class ChatTypingDto {
    private String type; // TYPING_START or TYPING_STOP
    private Long chatId;
    private Long userId;
    private LocalDateTime timestamp;

    public String getType() { return type; }
    public void setType(String type) { this.type = type; }

    public Long getChatId() { return chatId; }
    public void setChatId(Long chatId) { this.chatId = chatId; }

    public Long getUserId() { return userId; }
    public void setUserId(Long userId) { this.userId = userId; }

    public LocalDateTime getTimestamp() { return timestamp; }
    public void setTimestamp(LocalDateTime timestamp) { this.timestamp = timestamp; }
}
