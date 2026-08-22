package com.socialmedia.social.controller;

import com.socialmedia.social.dto.FollowRequestResponse;
import com.socialmedia.social.service.FollowRequestService;
import io.swagger.v3.oas.annotations.Operation;
import io.swagger.v3.oas.annotations.responses.ApiResponse;
import io.swagger.v3.oas.annotations.responses.ApiResponses;
import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.HashMap;
import java.util.Map;

@RestController
@RequestMapping("/follow-requests")
@RequiredArgsConstructor
@Tag(name = "Follow Requests", description = "Create and manage follow requests")
public class FollowRequestController {

    private final FollowRequestService followRequestService;

    @PostMapping("/{userId}")
    @Operation(summary = "Send a follow request to a user")
    @ApiResponses({@ApiResponse(responseCode = "200", description = "Request created"), @ApiResponse(responseCode = "400", description = "Invalid request")})
    public ResponseEntity<Map<String, String>> sendRequest(@PathVariable Long userId, @RequestAttribute("userId") Long requesterId) {
        // 🔴 FIX: Add input validation
        if (userId == null || userId <= 0) {
            Map<String, String> error = new HashMap<>();
            error.put("error", "Invalid target user ID");
            return ResponseEntity.badRequest().body(error);
        }
        if (requesterId == null || requesterId <= 0) {
            Map<String, String> error = new HashMap<>();
            error.put("error", "Not authenticated - invalid requester ID");
            return ResponseEntity.status(401).body(error);
        }
        
        try {
            followRequestService.sendFollowRequest(requesterId, userId);
            Map<String, String> resp = new HashMap<>();
            resp.put("message", "Follow request sent");
            resp.put("targetUserId", userId.toString());
            return ResponseEntity.ok(resp);
        } catch (IllegalArgumentException e) {
            // Handle validation errors from service
            Map<String, String> error = new HashMap<>();
            error.put("error", e.getMessage());
            return ResponseEntity.badRequest().body(error);
        } catch (Exception e) {
            // Log unexpected errors
            System.err.println("[ERROR] sendFollowRequest failed for requesterId=" + requesterId + ", targetId=" + userId);
            System.err.println("[ERROR] Exception: " + e.getClass().getName() + ": " + e.getMessage());
            e.printStackTrace();
            
            Map<String, String> error = new HashMap<>();
            error.put("error", "Server error: " + e.getMessage());
            return ResponseEntity.status(500).body(error);
        }
    }

    @GetMapping
    @Operation(summary = "Get incoming follow requests for authenticated user")
    public ResponseEntity<Page<FollowRequestResponse>> getRequests(@RequestAttribute("userId") Long targetId,
                                                                   @RequestParam(defaultValue = "0") int page,
                                                                   @RequestParam(defaultValue = "20") int size) {
        Pageable pageable = PageRequest.of(page, size);
        Page<FollowRequestResponse> results = followRequestService.getIncomingRequests(targetId, pageable);
        return ResponseEntity.ok(results);
    }

    @GetMapping("/check/{userId}")
    @Operation(summary = "Check if current user has sent a follow request to the target user")
    public ResponseEntity<Map<String, Object>> checkFollowRequest(@PathVariable Long userId, @RequestAttribute("userId") Long requesterId) {
        boolean hasPendingRequest = followRequestService.hasPendingRequest(requesterId, userId);
        Map<String, Object> resp = new HashMap<>();
        resp.put("hasPendingRequest", hasPendingRequest);
        resp.put("targetUserId", userId);
        resp.put("requesterId", requesterId);
        return ResponseEntity.ok(resp);
    }

    @PostMapping("/{requestId}/accept")
    @Operation(summary = "Accept a follow request")
    public ResponseEntity<Map<String, String>> accept(@PathVariable Long requestId, @RequestAttribute("userId") Long targetId) {
        try {
            followRequestService.acceptRequest(requestId, targetId);
            Map<String, String> resp = new HashMap<>();
            resp.put("message", "Follow request accepted");
            resp.put("requestId", requestId.toString());
            return ResponseEntity.ok(resp);
        } catch (IllegalArgumentException e) {
            Map<String, String> error = new HashMap<>();
            error.put("error", e.getMessage());
            return ResponseEntity.badRequest().body(error);
        } catch (Exception e) {
            System.err.println("[ERROR] acceptRequest failed: " + e.getMessage());
            e.printStackTrace();
            Map<String, String> error = new HashMap<>();
            error.put("error", "Server error: " + e.getMessage());
            return ResponseEntity.status(500).body(error);
        }
    }

    @PostMapping("/{requestId}/decline")
    @Operation(summary = "Decline a follow request")
    public ResponseEntity<Map<String, String>> decline(@PathVariable Long requestId, @RequestAttribute("userId") Long targetId) {
        try {
            followRequestService.declineRequest(requestId, targetId);
            Map<String, String> resp = new HashMap<>();
            resp.put("message", "Follow request declined");
            resp.put("requestId", requestId.toString());
            return ResponseEntity.ok(resp);
        } catch (IllegalArgumentException e) {
            Map<String, String> error = new HashMap<>();
            error.put("error", e.getMessage());
            return ResponseEntity.badRequest().body(error);
        } catch (Exception e) {
            System.err.println("[ERROR] declineRequest failed: " + e.getMessage());
            e.printStackTrace();
            Map<String, String> error = new HashMap<>();
            error.put("error", "Server error: " + e.getMessage());
            return ResponseEntity.status(500).body(error);
        }
    }
}
