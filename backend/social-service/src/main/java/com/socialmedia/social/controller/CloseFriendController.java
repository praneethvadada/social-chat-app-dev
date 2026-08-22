package com.socialmedia.social.controller;

import com.socialmedia.social.dto.UserProfileResponse;
import com.socialmedia.social.security.JwtTokenProvider;
import com.socialmedia.social.service.CloseFriendService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/close-friends")
@RequiredArgsConstructor
@Slf4j
@Tag(name = "Close Friends", description = "Manage close friends list")
public class CloseFriendController {

    private final CloseFriendService closeFriendService;
    private final JwtTokenProvider jwtTokenProvider;

    @GetMapping
    @Operation(summary = "Get close friends", description = "Get all close friends of the authenticated user")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Successfully retrieved close friends list"),
        @ApiResponse(responseCode = "401", description = "Unauthorized")
    })
    public ResponseEntity<List<UserProfileResponse>> getCloseFriends(
            @Parameter(hidden = true) @RequestHeader("Authorization") String authHeader) {
        
        Long userId = jwtTokenProvider.getUserIdFromToken(authHeader.substring(7));
        log.info("Getting close friends for user: {}", userId);
        
        List<UserProfileResponse> closeFriends = closeFriendService.getCloseFriends(userId);
        return ResponseEntity.ok(closeFriends);
    }

    @PostMapping("/{targetUserId}")
    @Operation(summary = "Add close friend", description = "Add a user to close friends list")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Successfully added to close friends"),
        @ApiResponse(responseCode = "400", description = "Invalid request"),
        @ApiResponse(responseCode = "401", description = "Unauthorized"),
        @ApiResponse(responseCode = "404", description = "User not found")
    })
    public ResponseEntity<Map<String, Object>> addCloseFriend(
            @Parameter(hidden = true) @RequestHeader("Authorization") String authHeader,
            @PathVariable Long targetUserId) {
        
        Long userId = jwtTokenProvider.getUserIdFromToken(authHeader.substring(7));
        log.info("User {} adding {} to close friends", userId, targetUserId);
        
        closeFriendService.addCloseFriend(userId, targetUserId);
        
        Map<String, Object> response = new HashMap<>();
        response.put("message", "User added to close friends");
        response.put("targetUserId", targetUserId);
        
        return ResponseEntity.ok(response);
    }

    @DeleteMapping("/{targetUserId}")
    @Operation(summary = "Remove close friend", description = "Remove a user from close friends list")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Successfully removed from close friends"),
        @ApiResponse(responseCode = "401", description = "Unauthorized")
    })
    public ResponseEntity<Map<String, Object>> removeCloseFriend(
            @Parameter(hidden = true) @RequestHeader("Authorization") String authHeader,
            @PathVariable Long targetUserId) {
        
        Long userId = jwtTokenProvider.getUserIdFromToken(authHeader.substring(7));
        log.info("User {} removing {} from close friends", userId, targetUserId);
        
        closeFriendService.removeCloseFriend(userId, targetUserId);
        
        Map<String, Object> response = new HashMap<>();
        response.put("message", "User removed from close friends");
        response.put("targetUserId", targetUserId);
        
        return ResponseEntity.ok(response);
    }

    @GetMapping("/check/{targetUserId}")
    @Operation(summary = "Check close friend status", description = "Check if a user is in close friends list")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Successfully checked status"),
        @ApiResponse(responseCode = "401", description = "Unauthorized")
    })
    public ResponseEntity<Map<String, Boolean>> isCloseFriend(
            @Parameter(hidden = true) @RequestHeader("Authorization") String authHeader,
            @PathVariable Long targetUserId) {
        
        Long userId = jwtTokenProvider.getUserIdFromToken(authHeader.substring(7));
        
        boolean isCloseFriend = closeFriendService.isCloseFriend(userId, targetUserId);
        
        Map<String, Boolean> response = new HashMap<>();
        response.put("isCloseFriend", isCloseFriend);
        
        return ResponseEntity.ok(response);
    }

    @GetMapping("/count")
    @Operation(summary = "Count close friends", description = "Get the count of close friends")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Successfully retrieved count"),
        @ApiResponse(responseCode = "401", description = "Unauthorized")
    })
    public ResponseEntity<Map<String, Long>> countCloseFriends(
            @Parameter(hidden = true) @RequestHeader("Authorization") String authHeader) {
        
        Long userId = jwtTokenProvider.getUserIdFromToken(authHeader.substring(7));
        
        long count = closeFriendService.countCloseFriends(userId);
        
        Map<String, Long> response = new HashMap<>();
        response.put("count", count);
        
        return ResponseEntity.ok(response);
    }
}
