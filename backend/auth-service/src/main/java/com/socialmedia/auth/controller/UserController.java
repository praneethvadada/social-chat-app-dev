package com.socialmedia.auth.controller;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.socialmedia.auth.entity.User;
import com.socialmedia.auth.repository.UserRepository;

import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.tags.Tag;

import java.util.Map;

/**
 * User controller for inter-service communication
 * Provides endpoints for other services to fetch user data
 */
@RestController
@RequestMapping("/users")
@Tag(name = "Users", description = "Internal user service endpoints")
public class UserController {

    private final UserRepository userRepository;

    public UserController(UserRepository userRepository) {
        this.userRepository = userRepository;
    }

    @Operation(summary = "Get user FCM token", description = "Get the FCM token for a user (internal service call)")
    @GetMapping("/{userId}/fcm-token")
    public ResponseEntity<String> getFCMToken(@PathVariable Long userId) {
        try {
            User user = userRepository.findById(userId)
                    .orElseThrow(() -> new RuntimeException("User not found"));

            if (user.getFcmToken() == null || user.getFcmToken().isEmpty()) {
                return ResponseEntity.noContent().build();
            }

            return ResponseEntity.ok(user.getFcmToken());
        } catch (Exception e) {
            return ResponseEntity.notFound().build();
        }
    }

    @Operation(summary = "Save user FCM token", description = "Save or update FCM token for a user")
    @PostMapping("/{userId}/fcm-token")
    public ResponseEntity<?> saveFCMToken(@PathVariable Long userId, @RequestBody Map<String, String> request) {
        try {
            String fcmToken = request.get("fcmToken");
            
            User user = userRepository.findById(userId)
                    .orElseThrow(() -> new RuntimeException("User not found"));

            if (fcmToken != null && !fcmToken.isEmpty()) {
                // ✅ CRITICAL FIX: Ensure 1-to-1 mapping (One Device -> One User)
                // If this token belongs to ANOTHER user (e.g. previous login), clear it from them.
                userRepository.findByFcmToken(fcmToken).ifPresent(otherUser -> {
                    if (!otherUser.getId().equals(userId)) {
                        System.out.println("[AuthService] ⚠️ Found FCM token on another user (" + otherUser.getId() + "). Stealing token for user " + userId);
                        otherUser.setFcmToken(null);
                        userRepository.save(otherUser);
                    }
                });

                if (!fcmToken.equals(user.getFcmToken())) {
                    user.setFcmToken(fcmToken);
                    userRepository.save(user);
                }
            } else {
                if (user.getFcmToken() != null) {
                    user.setFcmToken(null);
                    userRepository.save(user);
                    System.out.println("[AuthService] ✅ Cleared FCM token for user " + userId);
                }
            }

            return ResponseEntity.ok(Map.of("message", "FCM token saved successfully"));
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR)
                    .body(Map.of("error", e.getMessage()));
        }
    }

    @Operation(summary = "Get user username", description = "Get username for a user (internal service call)")
    @GetMapping("/{userId}/username")
    public ResponseEntity<String> getUsername(@PathVariable Long userId) {
        try {
            User user = userRepository.findById(userId)
                    .orElseThrow(() -> new RuntimeException("User not found"));

            return ResponseEntity.ok(user.getUsername());
        } catch (Exception e) {
            return ResponseEntity.notFound().build();
        }
    }

    @Operation(summary = "Get user summary", description = "Lightweight profile for other services (internal)")
    @GetMapping("/{userId}/summary")
    public ResponseEntity<Map<String, Object>> getUserSummary(@PathVariable Long userId) {
        return userRepository.findById(userId)
                .map(u -> ResponseEntity.ok(toSummary(u)))
                .orElseGet(() -> ResponseEntity.notFound().build());
    }

    @Operation(summary = "Batch user summaries", description = "Lightweight profiles for many ids (internal)")
    @PostMapping("/summaries")
    public ResponseEntity<java.util.List<Map<String, Object>>> getUserSummaries(@RequestBody java.util.List<Long> userIds) {
        if (userIds == null || userIds.isEmpty()) {
            return ResponseEntity.ok(java.util.Collections.emptyList());
        }
        java.util.List<Map<String, Object>> result = new java.util.ArrayList<>();
        for (User u : userRepository.findAllById(userIds)) {
            result.add(toSummary(u));
        }
        return ResponseEntity.ok(result);
    }

    /**
     * Internal: update identity fields that auth-service OWNS.
     *
     * social-service calls this when a user edits their username/full name, so
     * the source of truth stays here; it then refreshes its own replica.
     * Social-only fields (bio, avatar, location...) are NOT accepted here -
     * those belong to social-service.
     */
    @PutMapping("/{userId}/identity")
    public ResponseEntity<Map<String, Object>> updateIdentity(
            @PathVariable Long userId,
            @RequestBody Map<String, String> body) {
        return userRepository.findById(userId).map(u -> {
            String username = body.get("username");
            String fullName = body.get("fullName");

            if (username != null && !username.trim().isEmpty()
                    && !username.equals(u.getUsername())) {
                String trimmed = username.trim();
                // Same character-set rule as registration (RegisterRequest's
                // @Pattern) - this endpoint is a plain Map body, not a
                // validated DTO, so it needs its own explicit check. Without
                // it, editing a profile's username was a second way to land
                // a space (or anything else) in a value used as a login
                // identifier and in "/u/<username>" profile URLs.
                if (!trimmed.matches("^[a-zA-Z0-9_.]+$")) {
                    return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                            .body(Map.<String, Object>of("error",
                                    "Username can only contain letters, numbers, underscores, and periods — no spaces"));
                }
                // Username is unique across the system - reject collisions here,
                // where the authoritative table lives.
                if (userRepository.findByUsername(trimmed).isPresent()) {
                    return ResponseEntity.status(HttpStatus.CONFLICT)
                            .body(Map.<String, Object>of("error", "Username already taken"));
                }
                u.setUsername(trimmed);
            }
            if (fullName != null) {
                u.setFullName(fullName);
            }
            userRepository.save(u);
            return ResponseEntity.ok(toSummary(u));
        }).orElseGet(() -> ResponseEntity.notFound().build());
    }

    /** Shape matches chats-service UserSummary: userId, username, fullName, profilePictureUrl, isVerified. */
    private Map<String, Object> toSummary(User u) {
        Map<String, Object> m = new java.util.HashMap<>();
        m.put("userId", u.getId());
        m.put("username", u.getUsername());
        m.put("fullName", u.getFullName());
        m.put("profilePictureUrl", u.getProfilePicture());
        m.put("isVerified", false); // auth User does not track verification; cosmetic badge only
        return m;
    }
}
