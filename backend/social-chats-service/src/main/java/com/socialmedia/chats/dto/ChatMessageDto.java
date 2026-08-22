package com.socialmedia.chats.dto;

import java.time.LocalDateTime;

public class ChatMessageDto {
    private String type; // event type, e.g., MESSAGE_SEND or MESSAGE_RECEIVED
    private Long chatId;
    private Long senderId;
    private Long receiverId;
    private String content;
    private String messageId; // client-side id
    private LocalDateTime timestamp;

    public String getType() { return type; }
    public void setType(String type) { this.type = type; }

    public Long getChatId() { return chatId; }
    public void setChatId(Long chatId) { this.chatId = chatId; }

    public Long getSenderId() { return senderId; }
    public void setSenderId(Long senderId) { this.senderId = senderId; }

    public Long getReceiverId() { return receiverId; }
    public void setReceiverId(Long receiverId) { this.receiverId = receiverId; }

    public String getContent() { return content; }
    public void setContent(String content) { this.content = content; }

    public String getMessageId() { return messageId; }
    public void setMessageId(String messageId) { this.messageId = messageId; }

    public LocalDateTime getTimestamp() { return timestamp; }
    public void setTimestamp(LocalDateTime timestamp) { this.timestamp = timestamp; }
}
