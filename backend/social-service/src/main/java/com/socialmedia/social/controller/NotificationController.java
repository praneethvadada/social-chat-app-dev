package com.socialmedia.social.controller;

import com.socialmedia.social.dto.NotificationResponse;
import com.socialmedia.social.dto.MentionNotificationRequest;
import com.socialmedia.social.service.NotificationService;
import com.socialmedia.social.service.FCMService;
import io.swagger.v3.oas.annotations.Operation;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/notifications")
@RequiredArgsConstructor
public class NotificationController {

    @DeleteMapping("/{id}")
    @Operation(summary = "Delete a notification for the authenticated user")
    public ResponseEntity<Void> deleteNotification(@RequestAttribute("userId") Long userId,
                                                  @PathVariable Long id) {
        notificationService.deleteNotification(id, userId);
        return ResponseEntity.noContent().build();
    }

    private final NotificationService notificationService;
    private final FCMService fcmService;

    @GetMapping
    @Operation(summary = "Get notifications for authenticated user")
    public ResponseEntity<Page<NotificationResponse>> getNotifications(@RequestAttribute("userId") Long userId,
                                                                        @RequestParam(defaultValue = "0") int page,
                                                                        @RequestParam(defaultValue = "20") int size) {
        Pageable pageable = PageRequest.of(page, size);
        Page<NotificationResponse> results = notificationService.getNotifications(userId, pageable);
        return ResponseEntity.ok(results);
    }

    @PostMapping("/mention")
    @Operation(summary = "Send mention notifications to mentioned users")
    public ResponseEntity<?> sendMentionNotifications(@RequestAttribute("userId") Long actorId,
                                                     @RequestBody MentionNotificationRequest request) {
        if (request.getMentionedUserIds() == null || request.getMentionedUserIds().isEmpty()) {
            return ResponseEntity.badRequest().body("No mentioned users provided");
        }
        String message = "mentioned you in a post";
        if (request.getPostContent() != null && !request.getPostContent().isEmpty()) {
            message += ": " + request.getPostContent();
        }
        for (Long userId : request.getMentionedUserIds()) {
            notificationService.createNotification(
                userId,
                "mention",
                actorId,
                request.getPostId(),
                message
            );
        }
        
        // Send FCM push notifications for mentions
        try {
            fcmService.onUserMentioned(request.getMentionedUserIds(), actorId, request.getPostId(), request.getPostContent());
        } catch (Exception e) {
            System.out.println("[NotificationController] ⚠️ Failed to send FCM for mentions: " + e.getMessage());
        }
        return ResponseEntity.ok().build();
    }
}
