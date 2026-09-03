package com.socialmedia.chats.service;

import com.socialmedia.chats.client.BlockClient;
import com.socialmedia.chats.client.UserLookupClient;
import com.socialmedia.chats.dto.ConversationResponse;
import com.socialmedia.chats.dto.ConversationSyncResponse;
import com.socialmedia.chats.dto.GroupMessageRequest;
import com.socialmedia.chats.dto.MessageRequest;
import com.socialmedia.chats.dto.MessageResponse;
import com.socialmedia.chats.dto.UserSummary;
import com.socialmedia.chats.entity.ChatDeletion;
import com.socialmedia.chats.entity.Message;
import com.socialmedia.chats.entity.MessageReaction;
import com.socialmedia.chats.entity.ConversationMember;
import com.socialmedia.chats.repository.ChatDeletionRepository;
import com.socialmedia.chats.repository.ConversationMemberRepository;
import com.socialmedia.chats.repository.MessageReactionRepository;
import com.socialmedia.chats.repository.MessageRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.stream.Collectors;

/**
 * Chat message logic for social-chats-service.
 *
 * User profile data (name / avatar / verified) comes from auth-service via
 * {@link UserLookupClient}; block checks come from posts-service via
 * {@link BlockClient}; online status is local ({@link PresenceService}).
 * This service owns only messages + chat deletions in social_chats_db.
 */
@Service
@RequiredArgsConstructor
public class MessageService {

    private final MessageRepository messageRepository;
    private final ChatDeletionRepository chatDeletionRepository;
    private final SimpMessagingTemplate messagingTemplate;
    private final FCMService fcmService;
    private final BlockClient blockClient;
    private final UserLookupClient userLookupClient;
    private final PresenceService presenceService;
    private final ConversationService conversationService;
    private final MessageReactionRepository reactionRepository;
    private final ConversationMemberRepository conversationMemberRepository;

    @Value("${aws.s3.bucket-name:social-media-gidut-54513}")
    private String bucketName;

    @Value("${aws.s3.region:us-east-1}")
    private String region;

    @Transactional
    public MessageResponse sendMessage(MessageRequest request, Long senderId) {
        // Phase 4: idempotent retry - a client that queued this offline (or
        // never got its ack) resends with the SAME clientMessageId. Returning
        // the original row instead of inserting again is what makes that safe;
        // without this, a flaky ack turns one message into two on the wire.
        MessageResponse existing = findExistingByClientMessageId(senderId, request.getClientMessageId());
        if (existing != null) {
            return existing;
        }

        // Block check now goes to posts-service over REST (owner of blocked_users).
        if (blockClient.isEitherBlocked(senderId, request.getReceiverId())) {
            throw new RuntimeException("Cannot send message to this user");
        }

        Message message = new Message();
        message.setSenderId(senderId);
        message.setReceiverId(request.getReceiverId());
        message.setContent(request.getContent());
        message.setMediaUrl(request.getMediaUrl());
        message.setClientMessageId(request.getClientMessageId());
        // S3: carry the status-reply reference if this DM answers a status
        message.setReplyToStatusId(request.getReplyToStatusId());
        message.setReplyToStatusType(request.getReplyToStatusType());
        message.setReplyToStatusPreview(request.getReplyToStatusPreview());
        message.setStatusReaction(request.getStatusReaction());

        // G0: every 1:1 message lives in a DIRECT conversation. Best-effort -
        // a conversation hiccup must never block message delivery.
        try {
            message.setConversationId(
                    conversationService.findOrCreateDirect(senderId, request.getReceiverId()).getId());
        } catch (Exception e) {
            System.out.println("[MessageService] ⚠️ findOrCreateDirect failed (message still sent): " + e.getMessage());
        }

        System.out.println("[MessageService] 💾 SAVING MESSAGE: sender=" + senderId
                + " receiver=" + request.getReceiverId());

        UserSummary sender = userLookupClient.getUser(senderId);

        Message savedMessage;
        try {
            savedMessage = messageRepository.save(message);
        } catch (org.springframework.dao.DataIntegrityViolationException e) {
            // Two near-simultaneous retries both passed the check above before
            // either committed - the unique constraint caught what the
            // read-then-write check above couldn't. Whoever inserted first wins;
            // return that row rather than surfacing a spurious 500 to the loser.
            MessageResponse raced = findExistingByClientMessageId(senderId, request.getClientMessageId());
            if (raced != null) {
                return raced;
            }
            throw e;
        }
        System.out.println("[MessageService] ✅ MESSAGE SAVED id=" + savedMessage.getId());

        MessageResponse response = mapToResponse(savedMessage);
        if (sender != null) {
            response.setSenderName(sender.getUsername());
            response.setSenderProfilePictureUrl(buildAvatarUrl(sender.getProfilePictureUrl()));
        }

        // Confirmation to SENDER (replaces the optimistic bubble).
        try {
            messagingTemplate.convertAndSendToUser(senderId.toString(), "/queue/messages", response);
            System.out.println("[MessageService] ✅ Confirmation sent to sender " + senderId);
        } catch (Exception e) {
            System.out.println("[MessageService] ❌ Error sending confirmation to sender: " + e.getMessage());
        }

        // Deliver to RECIPIENT.
        try {
            messagingTemplate.convertAndSendToUser(
                    request.getReceiverId().toString(), "/queue/messages", response);
            System.out.println("[MessageService] ✅ Message delivered to receiver " + request.getReceiverId());

            try {
                fcmService.onNewMessage(senderId, request.getReceiverId(), request.getContent());
            } catch (Exception e) {
                System.out.println("[MessageService] ⚠️ FCM error for new message: " + e.getMessage());
            }
        } catch (Exception e) {
            System.out.println("[MessageService] ❌ Error sending via WebSocket: " + e.getMessage());
        }

        // Notify recipient of new/existing conversation so their list refreshes.
        try {
            if (chatDeletionRepository.hasUserDeletedConversation(request.getReceiverId(), senderId)) {
                restoreConversation(request.getReceiverId(), senderId);
            }

            java.util.Map<String, Object> conversationNotification = new java.util.HashMap<>();
            conversationNotification.put("type", "new_conversation");
            conversationNotification.put("senderId", senderId);
            conversationNotification.put("userId", senderId);
            conversationNotification.put("username", sender != null ? sender.getUsername() : "Unknown");
            conversationNotification.put("profilePictureUrl",
                    sender != null ? buildAvatarUrl(sender.getProfilePictureUrl()) : null);
            conversationNotification.put("message", request.getContent());
            conversationNotification.put("timestamp", LocalDateTime.now(ZoneId.of("UTC")).toString());

            messagingTemplate.convertAndSendToUser(
                    request.getReceiverId().toString(), "/queue/notifications", conversationNotification);
        } catch (Exception e) {
            System.out.println("[MessageService] ⚠️ Error sending conversation notification: " + e.getMessage());
        }

        return response;
    }

    @Transactional(readOnly = true)
    public Page<MessageResponse> getConversation(Long userId, Long otherUserId, Pageable pageable) {
        Page<Message> messages = messageRepository.findConversation(userId, otherUserId, pageable);
        return messages.map(this::mapToResponse);
    }

    // ------------------------------------------------------------------
    // G1: GROUP messaging
    // ------------------------------------------------------------------

    /**
     * Send a message into a GROUP conversation and fan it out over STOMP to
     * /topic/conversation.{id}.
     *
     * BLOCKING RULE (spec §6): fan-out is NEVER block-filtered. Personal blocks
     * only apply to member-addition and direct messages, so every group member
     * (including mutually-blocked pairs) sees every group message.
     */
    @Transactional
    public MessageResponse sendGroupMessage(Long conversationId, Long senderId, GroupMessageRequest request) {
        // Phase 4: same idempotent-retry guarantee as the 1:1 path.
        MessageResponse existing = findExistingByClientMessageId(senderId, request.getClientMessageId());
        if (existing != null) {
            return existing;
        }

        // G5: who may post is a per-group setting (spec §R), not a fixed rule.
        conversationService.requirePermission(
                conversationId, senderId, ConversationService.GroupAction.SEND);

        // GAP-2: a group message needs text OR media (media-only is valid).
        boolean hasText = request.getContent() != null && !request.getContent().trim().isEmpty();
        boolean hasMedia = request.getMediaUrl() != null && !request.getMediaUrl().isEmpty();
        if (!hasText && !hasMedia) {
            throw new IllegalArgumentException("Message needs text or media");
        }

        Message message = new Message();
        message.setSenderId(senderId);
        message.setReceiverId(null);                // group: no single recipient
        message.setConversationId(conversationId);
        message.setContent(request.getContent() == null ? "" : request.getContent());
        message.setMediaUrl(request.getMediaUrl());
        message.setMediaType(request.getMediaType());
        message.setMediaName(request.getMediaName());
        message.setClientMessageId(request.getClientMessageId());

        // G4: snapshot the reply target so the quote survives the original's
        // deletion. Reject cross-conversation replies outright.
        if (request.getReplyToMessageId() != null) {
            Message target = messageRepository.findById(request.getReplyToMessageId())
                    .orElseThrow(() -> new IllegalArgumentException("Reply target not found"));
            if (!conversationId.equals(target.getConversationId())) {
                throw new IllegalArgumentException("Cannot reply to a message from another conversation");
            }
            message.setReplyToMessageId(target.getId());
            message.setReplyToSenderId(target.getSenderId());
            message.setReplyToPreview(snippet(target));
        }

        Message saved;
        try {
            saved = messageRepository.save(message);
        } catch (org.springframework.dao.DataIntegrityViolationException e) {
            MessageResponse raced = findExistingByClientMessageId(senderId, request.getClientMessageId());
            if (raced != null) {
                return raced;
            }
            throw e;
        }

        MessageResponse response = mapToResponse(saved);
        response.setConversationId(conversationId);

        try {
            messagingTemplate.convertAndSend("/topic/conversation." + conversationId, response);
            System.out.println("[MessageService] 📣 GROUP message " + saved.getId()
                    + " fanned out to /topic/conversation." + conversationId);
        } catch (Exception e) {
            System.out.println("[MessageService] ❌ Group fan-out failed: " + e.getMessage());
        }

        // Also nudge every other member's personal notification queue — the
        // conversation topic above only reaches someone with that specific
        // group screen open, but the Connect list (showing unread badges)
        // needs to know even when no group screen is open.
        try {
            java.util.Map<String, Object> groupNotification = new java.util.HashMap<>();
            groupNotification.put("type", "new_group_message");
            groupNotification.put("conversationId", conversationId);
            groupNotification.put("senderId", senderId);
            for (com.socialmedia.chats.entity.ConversationMember member : conversationService.getMembers(conversationId)) {
                if (member.getUserId().equals(senderId)) continue;
                messagingTemplate.convertAndSendToUser(
                        member.getUserId().toString(), "/queue/notifications", groupNotification);
            }
        } catch (Exception e) {
            System.out.println("[MessageService] ⚠️ Group unread notification failed: " + e.getMessage());
        }

        // Keep the group sorted by latest activity in the chats list.
        try {
            conversationService.touchConversation(conversationId);
        } catch (Exception ignored) {
        }

        return response;
    }

    @Transactional(readOnly = true)
    public Page<MessageResponse> getGroupMessages(Long conversationId, Long userId, Pageable pageable) {
        conversationService.assertMember(conversationId, userId);
        Page<Message> page =
                messageRepository.findByConversationIdOrderByCreatedAtDesc(conversationId, pageable);

        // Load every reaction for this page in ONE query, then attach.
        List<Long> ids = page.getContent().stream().map(Message::getId).collect(Collectors.toList());
        Map<Long, List<MessageReaction>> byMessage = ids.isEmpty()
                ? Map.of()
                : reactionRepository.findByMessageIdIn(ids).stream()
                        .collect(Collectors.groupingBy(MessageReaction::getMessageId));

        return page.map(m -> {
            MessageResponse r = mapToResponse(m);
            r.setConversationId(conversationId);
            attachReactions(r, byMessage.getOrDefault(m.getId(), List.of()), userId);
            return r;
        });
    }

    /**
     * Phase 4: incremental catch-up for a conversation the client already has
     * locally cached (DIRECT or GROUP - both carry a real conversationId via
     * G0). {@code cursor} is the highest message id the client last fetched;
     * null/0 means "never synced before" and is rejected (400) since dumping
     * full history through this path defeats the point of a delta endpoint -
     * the client should use the regular paginated history endpoint for that
     * one-time backfill instead, then start sync from the id it saw there.
     *
     * Advances the caller's own {@code ConversationMember.lastSyncCursor} to
     * the highest id actually returned, NOT to "now" - if the page was capped
     * by {@code limit} (hasMore=true), the client is expected to call again
     * immediately with the returned cursor rather than the gap being silently
     * skipped.
     */
    @Transactional
    public ConversationSyncResponse syncConversation(Long conversationId, Long userId, Long cursor, int limit) {
        conversationService.assertMember(conversationId, userId);
        if (cursor == null || cursor <= 0) {
            throw new IllegalArgumentException("cursor is required - use the paginated history endpoint for the initial load");
        }

        int pageSize = Math.min(Math.max(limit, 1), 200);
        Page<Message> page = messageRepository.findByConversationIdAndIdGreaterThanOrderByIdAsc(
                conversationId, cursor, org.springframework.data.domain.PageRequest.of(0, pageSize));

        List<Message> content = page.getContent();
        Long newCursor = content.isEmpty() ? cursor : content.get(content.size() - 1).getId();

        ConversationMember member = conversationMemberRepository
                .findByConversationIdAndUserId(conversationId, userId)
                .orElse(null);
        if (member != null) {
            member.setLastSyncCursor(newCursor);
            member.setLastSyncAt(LocalDateTime.now(ZoneId.of("UTC")));
            conversationMemberRepository.save(member);
        }

        List<MessageResponse> responses = content.stream().map(m -> {
            MessageResponse r = mapToResponse(m);
            r.setConversationId(conversationId);
            return r;
        }).collect(Collectors.toList());
        return new ConversationSyncResponse(responses, newCursor, page.hasNext());
    }

    // ------------------------------------------------------------------
    // G4: reactions, pin, delete, search
    // ------------------------------------------------------------------

    /** Toggle a reaction: same key removes it, a different key replaces it. */
    @Transactional
    public void reactToMessage(Long messageId, Long userId, String reaction) {
        Message message = messageRepository.findById(messageId)
                .orElseThrow(() -> new IllegalArgumentException("Message not found"));
        conversationService.assertMember(message.getConversationId(), userId);

        Optional<MessageReaction> existing =
                reactionRepository.findByMessageIdAndUserId(messageId, userId);

        if (reaction == null || reaction.trim().isEmpty()
                || (existing.isPresent() && existing.get().getReaction().equals(reaction))) {
            existing.ifPresent(reactionRepository::delete);
        } else {
            MessageReaction r = existing.orElseGet(() -> {
                MessageReaction n = new MessageReaction();
                n.setMessageId(messageId);
                n.setUserId(userId);
                return n;
            });
            r.setReaction(reaction.trim());
            reactionRepository.save(r);
        }
        broadcastMessageUpdate(message.getConversationId(), messageId, "REACTION");
    }

    /** Who reacted to a message, with their names. */
    @Transactional(readOnly = true)
    public List<Map<String, Object>> getMessageReactions(Long messageId, Long userId) {
        Message message = messageRepository.findById(messageId)
                .orElseThrow(() -> new IllegalArgumentException("Message not found"));
        conversationService.assertMember(message.getConversationId(), userId);

        List<MessageReaction> reactions = reactionRepository.findByMessageId(messageId);
        userLookupClient.getUsers(reactions.stream()
                .map(MessageReaction::getUserId).collect(Collectors.toList()));

        List<Map<String, Object>> result = new ArrayList<>();
        for (MessageReaction r : reactions) {
            Map<String, Object> entry = new java.util.HashMap<>();
            entry.put("userId", r.getUserId());
            entry.put("reaction", r.getReaction());
            UserSummary u = userLookupClient.getUser(r.getUserId());
            entry.put("username", u != null ? u.getUsername() : null);
            entry.put("fullName", u != null ? u.getFullName() : null);
            result.add(entry);
        }
        return result;
    }

    /** Pin or unpin a message (OWNER/ADMIN only in G4; configurable in G5). */
    @Transactional
    public void setPinned(Long messageId, Long userId, boolean pinned) {
        Message message = messageRepository.findById(messageId)
                .orElseThrow(() -> new IllegalArgumentException("Message not found"));
        conversationService.requirePermission(message.getConversationId(), userId,
                ConversationService.GroupAction.PIN);

        message.setIsPinned(pinned);
        message.setPinnedAt(pinned ? LocalDateTime.now(ZoneId.of("UTC")) : null);
        message.setPinnedBy(pinned ? userId : null);
        messageRepository.save(message);
        broadcastMessageUpdate(message.getConversationId(), messageId, pinned ? "PINNED" : "UNPINNED");
    }

    @Transactional(readOnly = true)
    public List<MessageResponse> getPinned(Long conversationId, Long userId) {
        conversationService.assertMember(conversationId, userId);
        return messageRepository.findPinned(conversationId).stream()
                .map(this::mapToResponse)
                .collect(Collectors.toList());
    }

    /**
     * Delete for everyone. Allowed for your own message, or for any message if
     * you are an admin/owner (moderation). Writes a tombstone rather than
     * removing the row so replies quoting it still make sense.
     */
    @Transactional
    public void deleteForEveryone(Long messageId, Long userId) {
        Message message = messageRepository.findById(messageId)
                .orElseThrow(() -> new IllegalArgumentException("Message not found"));
        Long conversationId = message.getConversationId();
        conversationService.assertMember(conversationId, userId);

        boolean isOwnMessage = message.getSenderId().equals(userId);
        if (!isOwnMessage) {
            // Not mine - only moderators may remove it.
            conversationService.assertAdmin(conversationId, userId);
        }

        message.setIsDeleted(true);
        message.setDeletedAt(LocalDateTime.now(ZoneId.of("UTC")));
        message.setDeletedBy(userId);
        message.setContent("");
        message.setMediaUrl(null);
        message.setIsPinned(false);
        messageRepository.save(message);
        broadcastMessageUpdate(conversationId, messageId, "DELETED");
    }

    @Transactional(readOnly = true)
    public List<MessageResponse> searchInConversation(Long conversationId, Long userId, String query) {
        conversationService.assertMember(conversationId, userId);
        if (query == null || query.trim().isEmpty()) return List.of();
        return messageRepository.searchInConversation(conversationId, query.trim()).stream()
                .map(this::mapToResponse)
                .collect(Collectors.toList());
    }

    /**
     * GAP-3: forward a message into another conversation.
     *
     * Authorization is checked on BOTH ends: you must be able to read the
     * source and be permitted to post in the target. The content is COPIED
     * (not linked), so deleting the original leaves the forward intact - and
     * reply/pin/reaction state is deliberately not carried over.
     */
    @Transactional
    public MessageResponse forwardMessage(Long messageId, Long userId, Long targetConversationId) {
        Message source = messageRepository.findById(messageId)
                .orElseThrow(() -> new IllegalArgumentException("Message not found"));
        if (Boolean.TRUE.equals(source.getIsDeleted())) {
            throw new IllegalArgumentException("Cannot forward a deleted message");
        }
        // Must be able to see the source...
        conversationService.assertMember(source.getConversationId(), userId);
        // ...and be allowed to post in the destination (honours G5 permissions).
        conversationService.requirePermission(targetConversationId, userId,
                ConversationService.GroupAction.SEND);

        Message copy = new Message();
        copy.setSenderId(userId);
        copy.setReceiverId(null);
        copy.setConversationId(targetConversationId);
        copy.setContent(source.getContent());
        copy.setMediaUrl(source.getMediaUrl());
        copy.setMediaType(source.getMediaType());
        copy.setMediaName(source.getMediaName());
        copy.setIsForwarded(true);
        Message saved = messageRepository.save(copy);

        MessageResponse response = mapToResponse(saved);
        response.setConversationId(targetConversationId);
        try {
            UserSummary sender = userLookupClient.getUser(userId);
            if (sender != null) response.setSenderName(sender.getUsername());
        } catch (Exception ignored) { }

        try {
            messagingTemplate.convertAndSend(
                    "/topic/conversation." + targetConversationId, response);
        } catch (Exception e) {
            System.out.println("[MessageService] ❌ Forward fan-out failed: " + e.getMessage());
        }
        try {
            conversationService.touchConversation(targetConversationId);
        } catch (Exception ignored) { }

        return response;
    }

    /** Tell everyone in the conversation that one message changed. */
    private void broadcastMessageUpdate(Long conversationId, Long messageId, String change) {
        try {
            Map<String, Object> payload = new java.util.HashMap<>();
            payload.put("type", "MESSAGE_UPDATED");
            payload.put("change", change);
            payload.put("messageId", messageId);
            payload.put("conversationId", conversationId);
            messagingTemplate.convertAndSend("/topic/conversation." + conversationId, payload);
        } catch (Exception e) {
            System.out.println("[MessageService] ⚠️ update broadcast failed: " + e.getMessage());
        }
    }

    private void attachReactions(MessageResponse response,
                                 List<MessageReaction> reactions, Long viewerId) {
        Map<String, Long> counts = new java.util.LinkedHashMap<>();
        for (MessageReaction r : reactions) {
            counts.merge(r.getReaction(), 1L, Long::sum);
            if (r.getUserId().equals(viewerId)) {
                response.setMyReaction(r.getReaction());
            }
        }
        response.setReactionCounts(counts);
    }

    /** Short preview text used when quoting a message. */
    private String snippet(Message m) {
        if (Boolean.TRUE.equals(m.getIsDeleted())) return "Deleted message";
        String text = m.getContent();
        if (text == null || text.isEmpty()) {
            return m.getMediaUrl() != null ? "Media" : "";
        }
        return text.length() > 120 ? text.substring(0, 120) + "..." : text;
    }

    @Transactional
    public void markAsRead(Long messageId, Long userId) {
        Message message = messageRepository.findById(messageId)
                .orElseThrow(() -> new RuntimeException("Message not found"));

        if (!message.getReceiverId().equals(userId)) {
            throw new RuntimeException("Unauthorized");
        }

        if (!message.getIsRead()) {
            message.setIsRead(true);
            message.setReadAt(LocalDateTime.now(ZoneId.of("UTC")));
            messageRepository.save(message);

            try {
                java.util.Map<String, Object> payload = new java.util.HashMap<>();
                payload.put("type", "read_receipt");
                payload.put("messageIds", java.util.List.of(message.getId()));
                payload.put("fromUserId", userId);
                payload.put("toUserId", message.getSenderId());
                payload.put("timestamp", LocalDateTime.now(ZoneId.of("UTC")));
                messagingTemplate.convertAndSendToUser(
                        message.getSenderId().toString(), "/queue/notifications", payload);
            } catch (Exception e) {
                System.out.println("[MessageService] Error sending read receipt notification: " + e.getMessage());
            }
        }
    }

    @Transactional
    public void markConversationAsRead(Long userId, Long otherUserId) {
        List<Message> unreadMessages = messageRepository.findConversation(userId, otherUserId, Pageable.unpaged())
                .getContent().stream()
                .filter(m -> m.getReceiverId().equals(userId) && !m.getIsRead())
                .collect(Collectors.toList());

        for (Message message : unreadMessages) {
            message.setIsRead(true);
            message.setReadAt(LocalDateTime.now(ZoneId.of("UTC")));
        }

        if (!unreadMessages.isEmpty()) {
            messageRepository.saveAll(unreadMessages);
            try {
                java.util.Map<String, Object> payload = new java.util.HashMap<>();
                payload.put("type", "read_receipt");
                payload.put("messageIds", unreadMessages.stream().map(Message::getId).collect(Collectors.toList()));
                payload.put("fromUserId", userId);
                payload.put("toUserId", otherUserId);
                payload.put("timestamp", LocalDateTime.now(ZoneId.of("UTC")));
                messagingTemplate.convertAndSendToUser(
                        otherUserId.toString(), "/queue/notifications", payload);
            } catch (Exception e) {
                System.out.println("[MessageService] Error sending read receipts: " + e.getMessage());
            }
        }
    }

    @Transactional(readOnly = true)
    public Long getUnreadCount(Long userId) {
        return messageRepository.countByReceiverIdAndIsReadFalse(userId);
    }

    @Transactional(readOnly = true)
    public List<MessageResponse> getUnreadMessages(Long userId) {
        return messageRepository.findUnreadMessages(userId).stream()
                .map(this::mapToResponse)
                .collect(Collectors.toList());
    }

    @Transactional(readOnly = true)
    public List<ConversationResponse> getConversations(Long userId) {
        List<Long> conversationPartners = messageRepository.findConversationPartners(userId);

        // Warm the user cache in one batch so we don't do N sequential REST calls.
        userLookupClient.getUsers(conversationPartners);

        List<ConversationResponse> conversations = new ArrayList<>();
        for (Long partnerId : conversationPartners) {
            if (chatDeletionRepository.hasUserDeletedConversation(userId, partnerId)) {
                continue;
            }

            UserSummary partner = userLookupClient.getUser(partnerId);
            if (partner == null) continue;

            Message lastMessage = messageRepository.findLastMessageBetween(userId, partnerId);
            if (lastMessage == null) continue;

            Long unreadCount = messageRepository.countUnreadMessagesBetween(userId, partnerId);

            ConversationResponse conversation = new ConversationResponse();
            conversation.setConversationId(lastMessage.getConversationId());
            conversation.setUserId(partnerId);
            conversation.setUsername(partner.getUsername());
            conversation.setFullName(partner.getFullName());
            conversation.setProfilePictureUrl(buildAvatarUrl(partner.getProfilePictureUrl()));
            conversation.setIsVerified(partner.getIsVerified() != null && partner.getIsVerified());
            conversation.setLastMessageContent(lastMessage.getContent());
            conversation.setLastMessageMediaUrl(lastMessage.getMediaUrl());
            conversation.setLastMessageTime(lastMessage.getCreatedAt());
            conversation.setUnreadCount(unreadCount);
            conversation.setIsLastMessageFromMe(lastMessage.getSenderId().equals(userId));
            // Online status is local to this service.
            conversation.setIsOnline(presenceService.isOnline(partnerId));

            conversations.add(conversation);
        }

        conversations.sort((a, b) -> b.getLastMessageTime().compareTo(a.getLastMessageTime()));
        return conversations;
    }

    /** Phase 4: null clientMessageId means "not a retryable send" (e.g. group system messages) - never dedup those. */
    private MessageResponse findExistingByClientMessageId(Long senderId, String clientMessageId) {
        if (clientMessageId == null || clientMessageId.isBlank()) {
            return null;
        }
        return messageRepository.findFirstBySenderIdAndClientMessageId(senderId, clientMessageId)
                .map(this::mapToResponse)
                .orElse(null);
    }

    private MessageResponse mapToResponse(Message message) {
        MessageResponse response = new MessageResponse();
        response.setId(message.getId());
        response.setSenderId(message.getSenderId());
        response.setReceiverId(message.getReceiverId());
        response.setContent(message.getContent());
        response.setMediaUrl(buildMediaUrl(message.getMediaUrl()));
        // G2: carry system-event fields so the client can render group events
        response.setMessageType(message.getMessageType());
        response.setSystemEvent(message.getSystemEvent());
        response.setSystemActorId(message.getSystemActorId());
        response.setSystemTargetId(message.getSystemTargetId());
        response.setReplyToStatusId(message.getReplyToStatusId());
        response.setReplyToStatusType(message.getReplyToStatusType());
        response.setReplyToStatusPreview(message.getReplyToStatusPreview());
        response.setStatusReaction(message.getStatusReaction());
        // G4
        response.setReplyToMessageId(message.getReplyToMessageId());
        response.setReplyToSenderId(message.getReplyToSenderId());
        response.setReplyToPreview(message.getReplyToPreview());
        response.setMediaType(message.getMediaType());
        response.setMediaName(message.getMediaName());
        response.setIsForwarded(Boolean.TRUE.equals(message.getIsForwarded()));
        response.setIsPinned(Boolean.TRUE.equals(message.getIsPinned()));
        response.setIsDeleted(Boolean.TRUE.equals(message.getIsDeleted()));
        if (message.getReplyToSenderId() != null) {
            try {
                UserSummary u = userLookupClient.getUser(message.getReplyToSenderId());
                if (u != null) response.setReplyToSenderName(u.getUsername());
            } catch (Exception ignored) { }
        }
        response.setIsRead(message.getIsRead());
        response.setReadAt(message.getReadAt());
        response.setCreatedAt(message.getCreatedAt());
        response.setClientMessageId(message.getClientMessageId());
        response.setStatus(message.getIsRead() ? "read" : "sent");

        try {
            UserSummary sender = userLookupClient.getUser(message.getSenderId());
            if (sender != null) {
                response.setSenderName(sender.getUsername());
                response.setSenderProfilePictureUrl(buildAvatarUrl(sender.getProfilePictureUrl()));
            } else {
                response.setSenderName("Unknown");
                response.setSenderProfilePictureUrl(null);
            }
        } catch (Exception e) {
            response.setSenderName("Unknown");
            response.setSenderProfilePictureUrl(null);
        }

        return response;
    }

    /** Build a full S3 URL from a stored key (no-op if already a URL or empty). */
    private String buildAvatarUrl(String keyOrUrl) {
        if (keyOrUrl == null || keyOrUrl.isEmpty()) return keyOrUrl;
        if (keyOrUrl.startsWith("http://") || keyOrUrl.startsWith("https://")) return keyOrUrl;
        return String.format("https://%s.s3.%s.amazonaws.com/%s", bucketName, region, keyOrUrl);
    }

    private String buildMediaUrl(String keyOrUrl) {
        if (keyOrUrl == null || keyOrUrl.isEmpty()) return keyOrUrl;
        if (keyOrUrl.startsWith("http")) return keyOrUrl;
        return String.format("https://%s.s3.%s.amazonaws.com/%s", bucketName, region, keyOrUrl);
    }

    @Transactional
    public void deleteConversation(Long userId, Long otherUserId) {
        ChatDeletion deletion = new ChatDeletion();
        deletion.setUserId(userId);
        deletion.setOtherUserId(otherUserId);
        try {
            chatDeletionRepository.save(deletion);
        } catch (Exception e) {
            System.out.println("[MessageService] Error recording chat deletion: " + e.getMessage());
        }
    }

    @Transactional
    public void restoreConversation(Long userId, Long otherUserId) {
        try {
            java.util.Optional<ChatDeletion> deletion =
                    chatDeletionRepository.findByUserIdAndOtherUserId(userId, otherUserId);
            deletion.ifPresent(chatDeletionRepository::delete);
        } catch (Exception e) {
            System.out.println("[MessageService] Error restoring conversation: " + e.getMessage());
        }
    }

    @Transactional
    public void markMessagesAsRead(List<Long> messageIds, Long readBy) {
        if (messageIds == null || messageIds.isEmpty() || readBy == null || readBy <= 0) {
            return;
        }
        try {
            List<Message> messages = messageRepository.findAllById(messageIds);
            for (Message msg : messages) {
                if (msg.getReceiverId().equals(readBy) && msg.getReadAt() == null) {
                    msg.setReadAt(LocalDateTime.now(ZoneId.of("UTC")));
                    messageRepository.save(msg);
                }
            }
        } catch (Exception e) {
            System.out.println("[MessageService] ❌ Error marking messages as read: " + e.getMessage());
        }
    }
}
