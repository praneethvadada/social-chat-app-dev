package com.socialmedia.auth.controller;

import org.springframework.web.bind.annotation.*;
import java.util.Map;
import java.util.HashMap;

@RestController
@RequestMapping("/profiles")
public class MockProfileController {
    
    @GetMapping("/me")
    public Map<String, Object> getMyProfile(@RequestAttribute("userId") Long userId) {
        Map<String, Object> profile = new HashMap<>();
        profile.put("userId", userId);
        profile.put("username", "user" + userId);
        profile.put("fullName", "User " + userId);
        profile.put("email", "user" + userId + "@example.com");
        profile.put("bio", "This is a temporary profile");
        profile.put("profilePictureUrl", null);
        profile.put("coverPhotoUrl", null);
        profile.put("location", null);
        profile.put("website", null);
        profile.put("dateOfBirth", null);
        profile.put("isPrivate", false);
        profile.put("isVerified", false);
        profile.put("createdAt", java.time.LocalDateTime.now());
        profile.put("updatedAt", java.time.LocalDateTime.now());
        profile.put("followersCount", 0L);
        profile.put("followingCount", 0L);
        profile.put("postsCount", 0L);
        profile.put("isFollowing", false);
        profile.put("isFollowedBy", false);
        return profile;
    }
    
    @PutMapping("/me")
    public Map<String, Object> updateMyProfile(
            @RequestAttribute("userId") Long userId,
            @RequestBody Map<String, Object> request) {
        Map<String, Object> profile = new HashMap<>();
        profile.put("userId", userId);
        profile.put("username", "user" + userId);
        profile.put("fullName", request.getOrDefault("fullName", "User " + userId));
        profile.put("email", "user" + userId + "@example.com");
        profile.put("bio", request.getOrDefault("bio", "Updated bio"));
        profile.put("profilePictureUrl", null);
        profile.put("coverPhotoUrl", null);
        profile.put("location", null);
        profile.put("website", null);
        profile.put("dateOfBirth", null);
        profile.put("isPrivate", false);
        profile.put("isVerified", false);
        profile.put("createdAt", java.time.LocalDateTime.now());
        profile.put("updatedAt", java.time.LocalDateTime.now());
        profile.put("followersCount", 0L);
        profile.put("followingCount", 0L);
        profile.put("postsCount", 0L);
        profile.put("isFollowing", false);
        profile.put("isFollowedBy", false);
        return profile;
    }
}
