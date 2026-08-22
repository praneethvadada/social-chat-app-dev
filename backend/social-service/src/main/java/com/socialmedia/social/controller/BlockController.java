package com.socialmedia.social.controller;

import com.socialmedia.social.dto.BlockRequest;
import com.socialmedia.social.dto.BlockedUserResponse;
import com.socialmedia.social.service.BlockService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.Parameter;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/blocks")
@RequiredArgsConstructor
@Tag(name = "Block Management", description = "APIs for blocking and unblocking users")
public class BlockController {
    
    private final BlockService blockService;
    
    @PostMapping("/{userId}")
    @Operation(summary = "Block a user", description = "Block a user to prevent them from interacting with you")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "User blocked successfully"),
        @ApiResponse(responseCode = "400", description = "Invalid request - cannot block yourself or already blocked"),
        @ApiResponse(responseCode = "401", description = "Unauthorized - JWT token missing or invalid")
    })
    public ResponseEntity<BlockedUserResponse> blockUser(
            @Parameter(description = "ID of the user to block", required = true)
            @PathVariable Long userId,
            @Parameter(description = "Reason for blocking (optional)")
            @Valid @RequestBody(required = false) BlockRequest request,
            @Parameter(hidden = true)
            @RequestAttribute("userId") Long currentUserId) {
        
        BlockedUserResponse response = blockService.blockUser(currentUserId, userId, request);
        return ResponseEntity.ok(response);
    }
    
    @DeleteMapping("/{userId}")
    @Operation(summary = "Unblock a user", description = "Remove a user from your blocked list")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "User unblocked successfully"),
        @ApiResponse(responseCode = "404", description = "Block relationship not found"),
        @ApiResponse(responseCode = "401", description = "Unauthorized - JWT token missing or invalid")
    })
    public ResponseEntity<Map<String, String>> unblockUser(
            @Parameter(description = "ID of the user to unblock", required = true)
            @PathVariable Long userId,
            @Parameter(hidden = true)
            @RequestAttribute("userId") Long currentUserId) {
        
        blockService.unblockUser(currentUserId, userId);
        return ResponseEntity.ok(Map.of("message", "User unblocked successfully"));
    }
    
    @GetMapping("/check/{userId}")
    @Operation(summary = "Check if user is blocked", description = "Check if you have blocked a specific user")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Block status returned"),
        @ApiResponse(responseCode = "401", description = "Unauthorized - JWT token missing or invalid")
    })
    public ResponseEntity<Map<String, Boolean>> isBlocked(
            @Parameter(description = "ID of the user to check", required = true)
            @PathVariable Long userId,
            @Parameter(hidden = true)
            @RequestAttribute("userId") Long currentUserId) {
        
        boolean isBlocked = blockService.isBlocked(currentUserId, userId);
        return ResponseEntity.ok(Map.of("isBlocked", isBlocked));
    }
    
    @GetMapping("/check-either/{userId}")
    @Operation(summary = "Check if either user blocked the other", description = "Check if there's a block relationship in either direction")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Block status returned"),
        @ApiResponse(responseCode = "401", description = "Unauthorized - JWT token missing or invalid")
    })
    public ResponseEntity<Map<String, Boolean>> isEitherBlocked(
            @Parameter(description = "ID of the other user", required = true)
            @PathVariable Long userId,
            @Parameter(hidden = true)
            @RequestAttribute("userId") Long currentUserId) {
        
        boolean isBlocked = blockService.isEitherBlocked(currentUserId, userId);
        return ResponseEntity.ok(Map.of("isBlocked", isBlocked));
    }

    @GetMapping("/internal/check-either")
    @Operation(summary = "Internal: check block between two explicit users",
            description = "Service-to-service block check (both ids explicit, no user context). Used by chats-service.")
    public ResponseEntity<Map<String, Boolean>> isEitherBlockedInternal(
            @RequestParam Long userId1,
            @RequestParam Long userId2) {
        boolean isBlocked = blockService.isEitherBlocked(userId1, userId2);
        return ResponseEntity.ok(Map.of("isBlocked", isBlocked));
    }

    @GetMapping("/my-list")
    @Operation(summary = "Get blocked users list", description = "Get a paginated list of users you have blocked")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Blocked users list returned"),
        @ApiResponse(responseCode = "401", description = "Unauthorized - JWT token missing or invalid")
    })
    public ResponseEntity<Page<BlockedUserResponse>> getBlockedUsers(
            @Parameter(description = "Page number (0-based)", example = "0")
            @RequestParam(defaultValue = "0") int page,
            @Parameter(description = "Page size", example = "20")
            @RequestParam(defaultValue = "20") int size,
            @Parameter(hidden = true)
            @RequestAttribute("userId") Long currentUserId) {
        
        Page<BlockedUserResponse> blockedUsers = blockService.getBlockedUsers(
                currentUserId, PageRequest.of(page, size));
        return ResponseEntity.ok(blockedUsers);
    }
    
    @GetMapping("/count")
    @Operation(summary = "Count blocked users", description = "Get the total number of users you have blocked")
    @ApiResponses(value = {
        @ApiResponse(responseCode = "200", description = "Blocked users count returned"),
        @ApiResponse(responseCode = "401", description = "Unauthorized - JWT token missing or invalid")
    })
    public ResponseEntity<Map<String, Long>> countBlockedUsers(
            @Parameter(hidden = true)
            @RequestAttribute("userId") Long currentUserId) {
        
        long count = blockService.countBlockedUsers(currentUserId);
        return ResponseEntity.ok(Map.of("count", count));
    }
}
