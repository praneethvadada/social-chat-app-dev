package com.socialmedia.social.controller;

import com.socialmedia.social.dto.FollowerResponse;
import com.socialmedia.social.dto.FollowerStatsResponse;
import com.socialmedia.social.service.FollowerService;
import com.socialmedia.social.service.FCMService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/followers")
@RequiredArgsConstructor
@Tag(name = "Followers", description = "Follow/unfollow users and manage follower relationships")
public class FollowerController {
    
    private final FollowerService followerService;
    private final FCMService fcmService;
    
    @PostMapping("/{userId}")
    @Operation(
        summary = "Follow a user",
        description = "Create a follow relationship with another user. Cannot follow yourself or follow the same user twice."
    )
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Successfully followed the user"),
        @ApiResponse(responseCode = "400", description = "Invalid request (self-follow or already following)"),
        @ApiResponse(responseCode = "401", description = "Unauthorized - JWT token required")
    })
    public ResponseEntity<Map<String, String>> followUser(
            @Parameter(description = "ID of the user to follow") @PathVariable Long userId,
            @Parameter(hidden = true) @RequestAttribute("userId") Long followerId) {
        
        try {
            followerService.followUser(followerId, userId);
            
            // Send push notification to followed user
            fcmService.onUserFollowed(userId, followerId);
            
            Map<String, String> response = new HashMap<>();
            response.put("message", "Successfully followed user");
            response.put("followingUserId", userId.toString());
            
            return ResponseEntity.ok(response);
        } catch (IllegalArgumentException e) {
            Map<String, String> errorResponse = new HashMap<>();
            errorResponse.put("error", e.getMessage());
            return ResponseEntity.badRequest().body(errorResponse);
        }
    }
    
    @DeleteMapping("/{userId}")
    @Operation(
        summary = "Unfollow a user",
        description = "Remove a follow relationship with another user"
    )
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Successfully unfollowed the user"),
        @ApiResponse(responseCode = "400", description = "Not following this user"),
        @ApiResponse(responseCode = "401", description = "Unauthorized - JWT token required")
    })
    public ResponseEntity<Map<String, String>> unfollowUser(
            @Parameter(description = "ID of the user to unfollow") @PathVariable Long userId,
            @Parameter(hidden = true) @RequestAttribute("userId") Long followerId) {
        
        followerService.unfollowUser(followerId, userId);
        
        Map<String, String> response = new HashMap<>();
        response.put("message", "Successfully unfollowed user");
        response.put("unfollowedUserId", userId.toString());
        
        return ResponseEntity.ok(response);
    }
    
    @GetMapping("/check/{userId}")
    @Operation(
        summary = "Check if following a user",
        description = "Check if the authenticated user follows a specific user"
    )
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Successfully checked follow status"),
        @ApiResponse(responseCode = "401", description = "Unauthorized - JWT token required")
    })
    public ResponseEntity<Map<String, Boolean>> checkFollowing(
            @Parameter(description = "ID of the user to check") @PathVariable Long userId,
            @Parameter(hidden = true) @RequestAttribute("userId") Long followerId) {
        
        boolean isFollowing = followerService.isFollowing(followerId, userId);
        
        Map<String, Boolean> response = new HashMap<>();
        response.put("isFollowing", isFollowing);
        
        return ResponseEntity.ok(response);
    }
    
    @GetMapping("/user/{userId}")
    @Operation(
        summary = "Get user's followers",
        description = "Get a paginated list of users who follow the specified user"
    )
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Successfully retrieved followers list"),
        @ApiResponse(responseCode = "401", description = "Unauthorized - JWT token required")
    })
    public ResponseEntity<Page<FollowerResponse>> getFollowers(
            @Parameter(description = "ID of the user whose followers to retrieve") @PathVariable Long userId,
            @Parameter(description = "Page number (0-based)") @RequestParam(defaultValue = "0") int page,
            @Parameter(description = "Page size") @RequestParam(defaultValue = "20") int size) {
        
        Pageable pageable = PageRequest.of(page, size, Sort.by("createdAt").descending());
        Page<FollowerResponse> followers = followerService.getFollowers(userId, pageable);
        
        return ResponseEntity.ok(followers);
    }
    
    @GetMapping("/user/{userId}/following")
    @Operation(
        summary = "Get users that this user follows",
        description = "Get a paginated list of users that the specified user is following"
    )
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Successfully retrieved following list"),
        @ApiResponse(responseCode = "401", description = "Unauthorized - JWT token required")
    })
    public ResponseEntity<Page<FollowerResponse>> getFollowing(
            @Parameter(description = "ID of the user whose following list to retrieve") @PathVariable Long userId,
            @Parameter(description = "Page number (0-based)") @RequestParam(defaultValue = "0") int page,
            @Parameter(description = "Page size") @RequestParam(defaultValue = "20") int size) {
        
        Pageable pageable = PageRequest.of(page, size, Sort.by("createdAt").descending());
        Page<FollowerResponse> following = followerService.getFollowing(userId, pageable);
        
        return ResponseEntity.ok(following);
    }
    
    @GetMapping("/user/{userId}/stats")
    @Operation(
        summary = "Get follower statistics",
        description = "Get follower/following counts and relationship status between authenticated user and target user"
    )
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Successfully retrieved statistics"),
        @ApiResponse(responseCode = "401", description = "Unauthorized - JWT token required")
    })
    public ResponseEntity<FollowerStatsResponse> getFollowerStats(
            @Parameter(description = "ID of the user to get stats for") @PathVariable Long userId,
            @Parameter(hidden = true) @RequestAttribute("userId") Long requestingUserId) {
        
        FollowerStatsResponse stats = followerService.getFollowerStats(userId, requestingUserId);
        return ResponseEntity.ok(stats);
    }
    
    @GetMapping("/mutual")
    @Operation(
        summary = "Get mutual followers",
        description = "Get users who follow each other with the authenticated user"
    )
    @ApiResponses({
        @ApiResponse(responseCode = "200", description = "Successfully retrieved mutual followers"),
        @ApiResponse(responseCode = "401", description = "Unauthorized - JWT token required")
    })
    public ResponseEntity<Page<FollowerResponse>> getMutualFollowers(
            @Parameter(hidden = true) @RequestAttribute("userId") Long userId,
            @Parameter(description = "Page number (0-based)") @RequestParam(defaultValue = "0") int page,
            @Parameter(description = "Page size") @RequestParam(defaultValue = "20") int size) {
        
        Pageable pageable = PageRequest.of(page, size, Sort.by("createdAt").descending());
        Page<FollowerResponse> mutuals = followerService.getMutualFollowers(userId, pageable);
        
        return ResponseEntity.ok(mutuals);
    }
}
