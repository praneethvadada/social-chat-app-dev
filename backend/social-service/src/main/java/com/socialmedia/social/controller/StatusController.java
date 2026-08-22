package com.socialmedia.social.controller;

import com.socialmedia.social.dto.StatusDtos.*;
import com.socialmedia.social.service.StatusService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

/** S1: 24-hour status API. Reached as /api/social/statuses/** through the gateway. */
@RestController
@RequestMapping("/statuses")
@RequiredArgsConstructor
public class StatusController {

    private final StatusService statusService;

    @PostMapping
    public ResponseEntity<StatusItem> create(
            @Valid @RequestBody CreateStatusRequest request,
            @RequestAttribute("userId") Long userId) {
        return ResponseEntity.ok(statusService.create(userId, request));
    }

    /** Status home: my status + people I follow (expiry/block enforced server-side). */
    @GetMapping("/feed")
    public ResponseEntity<StatusFeedResponse> feed(@RequestAttribute("userId") Long userId) {
        return ResponseEntity.ok(statusService.getFeed(userId));
    }

    /**
     * One status by id - used when tapping the status reference on a chat
     * bubble. Declared after /feed and /archive; Spring still prefers those
     * literal paths over this variable one.
     */
    @GetMapping("/{statusId}")
    public ResponseEntity<UserStatusGroup> one(
            @PathVariable Long statusId,
            @RequestAttribute("userId") Long userId) {
        return ResponseEntity.ok(statusService.getOne(statusId, userId));
    }

    @PostMapping("/{statusId}/view")
    public ResponseEntity<Void> markViewed(
            @PathVariable Long statusId,
            @RequestAttribute("userId") Long userId) {
        statusService.markViewed(statusId, userId);
        return ResponseEntity.ok().build();
    }

    /** S4 (§R): my expired statuses. Owner-scoped by construction. */
    @GetMapping("/archive")
    public ResponseEntity<List<StatusItem>> archive(@RequestAttribute("userId") Long userId) {
        return ResponseEntity.ok(statusService.getArchive(userId));
    }

    /** S3: set (or clear, by sending an empty reaction) my reaction to a status. */
    @PostMapping("/{statusId}/reaction")
    public ResponseEntity<Void> react(
            @PathVariable Long statusId,
            @RequestBody ReactRequest request,
            @RequestAttribute("userId") Long userId) {
        statusService.react(statusId, userId, request.getReaction());
        return ResponseEntity.ok().build();
    }

    @GetMapping("/{statusId}/viewers")
    public ResponseEntity<List<StatusViewerInfo>> viewers(
            @PathVariable Long statusId,
            @RequestAttribute("userId") Long userId) {
        return ResponseEntity.ok(statusService.getViewers(statusId, userId));
    }

    @DeleteMapping("/{statusId}")
    public ResponseEntity<Void> delete(
            @PathVariable Long statusId,
            @RequestAttribute("userId") Long userId) {
        statusService.delete(statusId, userId);
        return ResponseEntity.ok().build();
    }

    /** Neutral message - never reveals whether it was blocked, expired or deleted (§25). */
    @ExceptionHandler(SecurityException.class)
    public ResponseEntity<Map<String, String>> handleForbidden(SecurityException e) {
        return ResponseEntity.status(HttpStatus.FORBIDDEN)
                .body(Map.of("error", "Status unavailable"));
    }

    @ExceptionHandler(StatusService.StatusGoneException.class)
    public ResponseEntity<Map<String, String>> handleGone(
            StatusService.StatusGoneException e) {
        return ResponseEntity.status(HttpStatus.NOT_FOUND)
                .body(Map.of("error", e.getMessage()));
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<Map<String, String>> handleBadRequest(IllegalArgumentException e) {
        return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
    }
}
