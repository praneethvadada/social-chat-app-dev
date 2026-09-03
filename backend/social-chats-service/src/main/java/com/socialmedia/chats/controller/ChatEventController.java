package com.socialmedia.chats.controller;

import com.socialmedia.chats.dto.ChatTypingDto;
import com.socialmedia.chats.dto.ChatReadDto;
import com.socialmedia.chats.repository.MessageRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Controller;
import org.springframework.transaction.annotation.Transactional;

import java.time.ZoneId;

@Controller
@RequiredArgsConstructor
public class ChatEventController {

    private final SimpMessagingTemplate messagingTemplate;
    private final MessageRepository messageRepository;

    /**
     * Typing start: broadcast TYPING_START to /topic/chat/{chatId}
     * No persistence.
     */
    @MessageMapping("/typing.start")
    public void handleTypingStart(@Payload ChatTypingDto payload) {
        try {
            System.out.println("[TYPING] START chatId=" + payload.getChatId() + " user=" + payload.getUserId());
            payload.setType("TYPING_START");
            String dest = "/topic/chat/" + payload.getChatId();
            messagingTemplate.convertAndSend(dest, payload);
            System.out.println("[TYPING] START broadcast to " + dest + " user=" + payload.getUserId());
        } catch (Exception e) {
            System.out.println("[TYPING] START handler error: " + e.getMessage());
        }
    }

    /**
     * Typing stop: broadcast TYPING_STOP to /topic/chat/{chatId}
     * No persistence.
     */
    @MessageMapping("/typing.stop")
    public void handleTypingStop(@Payload ChatTypingDto payload) {
        try {
            System.out.println("[TYPING] STOP chatId=" + payload.getChatId() + " user=" + payload.getUserId());
            payload.setType("TYPING_STOP");
            String dest = "/topic/chat/" + payload.getChatId();
            messagingTemplate.convertAndSend(dest, payload);
            System.out.println("[TYPING] STOP broadcast to " + dest + " user=" + payload.getUserId());
        } catch (Exception e) {
            System.out.println("[TYPING] STOP handler error: " + e.getMessage());
        }
    }

    /**
     * Message read: Send read receipt to /user/{senderId}/queue/read-receipts (direct to message sender)
     * This allows the sender to know their messages were read (double ticks ✓✓)
     * DB update happens after broadcasting.
     */
    @MessageMapping("/chat.read")
    @Transactional
    public void handleMessageRead(@Payload ChatReadDto payload) {
        try {
            System.out.println("[READ] CHAT.READ received from reader=" + payload.getReaderId() + " otherUserId=" + payload.getOtherUserId() + " messageIds=" + payload.getMessageIds());
            
            // Mark messages as read in database FIRST
            try {
                final java.time.LocalDateTime now = java.time.LocalDateTime.now(ZoneId.of("UTC"));
                if (payload.getMessageIds() != null && !payload.getMessageIds().isEmpty()) {
                    messageRepository.markMessagesReadByIds(payload.getMessageIds(), now);
                    System.out.println("[READ] Messages marked as read for ids=" + payload.getMessageIds());
                }
            } catch (Exception e) {
                System.out.println("[READ] Message persist failed: " + e.getMessage());
            }
            
            // Send read receipt directly to the sender (other user)
            // The sender needs to know their messages were read
            Long senderId = payload.getOtherUserId(); // The person who sent the messages
            Long readerId = payload.getReaderId();     // The person who read them
            
            System.out.println("[READ] Sending read receipt to /user/" + senderId + "/queue/read-receipts from reader=" + readerId);
            
            // Create read receipt payload
            ChatReadDto readReceipt = new ChatReadDto();
            readReceipt.setReaderId(readerId);
            readReceipt.setOtherUserId(senderId);
            readReceipt.setMessageIds(payload.getMessageIds());
            readReceipt.setType("READ_RECEIPT");
            
            // Send directly to sender's queue
            String destination = "/user/" + senderId + "/queue/read-receipts";
            messagingTemplate.convertAndSendToUser(
                String.valueOf(senderId),
                "/queue/read-receipts",
                readReceipt
            );
            System.out.println("[READ] ✅ Read receipt sent to " + destination + " for " + payload.getMessageIds().size() + " messages");
            
        } catch (Exception e) {
            System.out.println("[READ] MESSAGE_READ handler error: " + e.getMessage());
            e.printStackTrace();
        }
    }
}
