package com.socialmedia.chats.controller;

import com.socialmedia.chats.dto.ChatMessageDto;
import com.socialmedia.chats.dto.ChatTypingDto;
import com.socialmedia.chats.dto.ChatReadDto;
import com.socialmedia.chats.entity.Message;
import com.socialmedia.chats.repository.MessageRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Controller;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.time.ZoneId;

@Controller
@RequiredArgsConstructor
public class ChatEventController {

    private final SimpMessagingTemplate messagingTemplate;
    private final MessageRepository messageRepository;
    private final com.socialmedia.chats.service.ConversationService conversationService;

    /**
     * Handle incoming MESSAGE_SEND events from clients and broadcast MESSAGE_RECEIVED.
     * Delivery does not depend on REST and broadcast happens immediately. Saving is done after.
     */
    @MessageMapping("/message.send")
    @Transactional
    public void handleMessageSend(@Payload ChatMessageDto payload) {
        try {
            System.out.println("[CHAT] MESSAGE_SEND payload.chatId=" + payload.getChatId()
                    + " sender=" + payload.getSenderId() + " messageId=" + payload.getMessageId());

            // Build MESSAGE_RECEIVED payload (same fields, type set)
            ChatMessageDto out = new ChatMessageDto();
            out.setType("MESSAGE_RECEIVED");
            out.setChatId(payload.getChatId());
            out.setSenderId(payload.getSenderId());
            out.setReceiverId(payload.getReceiverId());
            out.setContent(payload.getContent());
            out.setMessageId(payload.getMessageId());
            out.setTimestamp(payload.getTimestamp() != null ? payload.getTimestamp() : LocalDateTime.now());

            // Broadcast immediately to /topic/chat/{chatId}
            String dest = "/topic/chat/" + payload.getChatId();
            messagingTemplate.convertAndSend(dest, out);
            System.out.println("[CHAT] MESSAGE_RECEIVED broadcast to " + dest + " messageId=" + out.getMessageId());

            // Persist message to DB (after broadcasting)
            try {
                Message m = new Message();
                m.setSenderId(payload.getSenderId());
                m.setReceiverId(payload.getReceiverId());
                m.setContent(payload.getContent() == null ? "" : payload.getContent());
                // store clientMessageId if present so we can correlate optimistic messages
                m.setClientMessageId(payload.getMessageId());
                // mediaUrl is not part of this contract right now; ignore
                // G0: stamp the DIRECT conversation (best-effort)
                try {
                    m.setConversationId(conversationService
                            .findOrCreateDirect(payload.getSenderId(), payload.getReceiverId()).getId());
                } catch (Exception ce) {
                    System.out.println("[CHAT] ⚠️ findOrCreateDirect failed: " + ce.getMessage());
                }
                Message saved = messageRepository.save(m);
                System.out.println("[CHAT] MESSAGE_SAVED id=" + saved.getId());
            } catch (Exception e) {
                System.out.println("[CHAT] MESSAGE_SAVED failed: " + e.getMessage());
            }

        } catch (Exception e) {
            System.out.println("[CHAT] MESSAGE_SEND handler error: " + e.getMessage());
        }
    }

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
