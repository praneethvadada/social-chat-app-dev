package com.socialmedia.social.service;

import com.socialmedia.social.dto.NotificationResponse;
import com.socialmedia.social.entity.Notification;
import com.socialmedia.social.repository.NotificationRepository;
import com.socialmedia.social.service.UserProfileService;
import com.socialmedia.social.dto.UserSearchResult;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.Pageable;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class NotificationService {
    @Transactional
    public void deleteNotification(Long notificationId, Long userId) {
        Notification n = notificationRepository.findById(notificationId)
            .orElseThrow(() -> new RuntimeException("Notification not found"));
        if (!n.getUserId().equals(userId)) {
            throw new RuntimeException("Unauthorized to delete this notification");
        }
        notificationRepository.delete(n);
    }

    private final NotificationRepository notificationRepository;
    private final com.socialmedia.social.client.NotificationRelayClient notificationRelayClient;
    private final UserProfileService userProfileService;

    @Transactional
    public NotificationResponse createNotification(Long userId, String type, Long actorId, Long targetId, String content) {
        Notification n = new Notification();
        n.setUserId(userId);
        n.setType(type);
        n.setActorId(actorId);
        n.setTargetId(targetId);
        n.setContent(content);
        n.setIsRead(false);

        Notification saved = notificationRepository.save(n);

        NotificationResponse resp = mapToResponse(saved);

        // Relay to chats-service, which owns the client WebSocket connections.
        notificationRelayClient.relayToUser(userId, "/queue/notifications", resp);

        return resp;
    }

    @Transactional(readOnly = true)
    public Page<NotificationResponse> getNotifications(Long userId, Pageable pageable) {
        Page<Notification> page = notificationRepository.findByUserIdOrderByCreatedAtDesc(userId, pageable);
        List<NotificationResponse> list = page.getContent().stream().map(this::mapToResponse).collect(Collectors.toList());
        return new PageImpl<>(list, pageable, page.getTotalElements());
    }

    private NotificationResponse mapToResponse(Notification n) {
        NotificationResponse r = new NotificationResponse();
        r.setId(n.getId());
        r.setType(n.getType());
        r.setActorId(n.getActorId());
        // enrich with actor profile info if available
        if (n.getActorId() != null) {
            try {
                var profiles = userProfileService.getUserProfilesByIds(java.util.List.of(n.getActorId()), n.getUserId());
                if (profiles != null && !profiles.isEmpty()) {
                    UserSearchResult p = profiles.get(0);
                    r.setActorUsername(p.getUsername());
                    r.setActorFullName(p.getFullName());
                    r.setActorProfilePictureUrl(p.getProfilePictureUrl());
                }
            } catch (Exception ex) {
                // swallow profile lookup errors and continue with basic response
                System.out.println("[NotificationService] Failed to enrich actor profile: " + ex.getMessage());
            }
        }
        r.setTargetId(n.getTargetId());
        r.setContent(n.getContent());
        r.setIsRead(n.getIsRead());
        r.setCreatedAt(n.getCreatedAt());
        return r;
    }
}
