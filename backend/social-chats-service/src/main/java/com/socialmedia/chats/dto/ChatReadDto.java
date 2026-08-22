package com.socialmedia.chats.dto;

import java.time.LocalDateTime;
import java.util.List;

public class ChatReadDto {
    private String type; // MESSAGE_READ or READ_RECEIPT
    private Long chatId;
    private Long readerId;      // Who read the messages
    private Long otherUserId;   // The other user in the conversation (message sender)
    private List<Long> messageIds;
    private List<String> clientMessageIds;
    private LocalDateTime timestamp;

    public String getType() { return type; }
    public void setType(String type) { this.type = type; }

    public Long getChatId() { return chatId; }
    public void setChatId(Long chatId) { this.chatId = chatId; }

    public Long getReaderId() { return readerId; }
    public void setReaderId(Long readerId) { this.readerId = readerId; }

    public Long getOtherUserId() { return otherUserId; }
    public void setOtherUserId(Long otherUserId) { this.otherUserId = otherUserId; }

    public List<Long> getMessageIds() { return messageIds; }
    public void setMessageIds(List<Long> messageIds) { this.messageIds = messageIds; }

    public List<String> getClientMessageIds() { return clientMessageIds; }
    public void setClientMessageIds(List<String> clientMessageIds) { this.clientMessageIds = clientMessageIds; }

    public LocalDateTime getTimestamp() { return timestamp; }
    public void setTimestamp(LocalDateTime timestamp) { this.timestamp = timestamp; }
}
