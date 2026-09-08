package com.socialmedia.social.controller;

import com.socialmedia.social.dto.HashtagResponse;
import com.socialmedia.social.dto.PostRequest;
import com.socialmedia.social.dto.PostResponse;
import com.socialmedia.social.service.PostService;
import java.util.List;
import java.util.Map;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/posts")
@RequiredArgsConstructor
public class PostController {

    private final PostService postService;

    @PostMapping
    public ResponseEntity<PostResponse> createPost(
            @Valid @RequestBody PostRequest request,
            @RequestAttribute("userId") Long userId) {
        System.out.println("[CONTROLLER DEBUG] Received POST request - visibility: " + request.getVisibility() + ", isPublic: " + request.getIsPublic());
        PostResponse response = postService.createPost(request, userId);
        System.out.println("[CONTROLLER DEBUG] Response visibility: " + response.getVisibility());
        return ResponseEntity.ok(response);
    }

    @PutMapping("/{postId}")
    public ResponseEntity<PostResponse> updatePost(
            @PathVariable Long postId,
            @Valid @RequestBody PostRequest request,
            @RequestAttribute("userId") Long userId) {
        PostResponse response = postService.updatePost(postId, request, userId);
        return ResponseEntity.ok(response);
    }

    @DeleteMapping("/{postId}")
    public ResponseEntity<Void> deletePost(
            @PathVariable Long postId,
            @RequestAttribute("userId") Long userId) {
        postService.deletePost(postId, userId);
        return ResponseEntity.noContent().build();
    }

    @GetMapping("/{postId}")
    public ResponseEntity<PostResponse> getPost(
            @PathVariable Long postId,
            @RequestAttribute("userId") Long userId) {
        PostResponse response = postService.getPost(postId, userId);
        return ResponseEntity.ok(response);
    }

    @GetMapping("/user/{targetUserId}")
    public ResponseEntity<Page<PostResponse>> getUserPosts(
            @PathVariable Long targetUserId,
            @RequestAttribute("userId") Long currentUserId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        Pageable pageable = PageRequest.of(page, size);
        Page<PostResponse> posts = postService.getUserPosts(targetUserId, currentUserId, pageable);
        return ResponseEntity.ok(posts);
    }

    @GetMapping("/explore")
    public ResponseEntity<Page<PostResponse>> getPublicPosts(
            @RequestAttribute("userId") Long userId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        Pageable pageable = PageRequest.of(page, size);
        Page<PostResponse> posts = postService.getPublicPosts(userId, pageable);
        return ResponseEntity.ok(posts);
    }

    @GetMapping("/feed")
    public ResponseEntity<Page<PostResponse>> getFeed(
            @RequestAttribute("userId") Long userId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        Pageable pageable = PageRequest.of(page, size);
        Page<PostResponse> posts = postService.getFeed(userId, pageable);
        return ResponseEntity.ok(posts);
    }

    @PostMapping("/{postId}/vote")
    public ResponseEntity<PostResponse> votePoll(
            @PathVariable Long postId,
            @RequestBody Map<String, Long> body,
            @RequestAttribute("userId") Long userId) {
        Long optionId = body.get("optionId");
        return ResponseEntity.ok(postService.votePoll(postId, optionId, userId));
    }

    @PostMapping("/{postId}/rsvp")
    public ResponseEntity<PostResponse> rsvpEvent(
            @PathVariable Long postId,
            @RequestBody Map<String, String> body,
            @RequestAttribute("userId") Long userId) {
        String status = body.get("status");
        return ResponseEntity.ok(postService.rsvpEvent(postId, status, userId));
    }

    /** Who voted for what, grouped by option id — not just the aggregate counts. */
    @GetMapping("/{postId}/vote/voters")
    public ResponseEntity<Map<Long, List<com.socialmedia.social.dto.VoterSummary>>> getPollVoters(
            @PathVariable Long postId,
            @RequestAttribute("userId") Long userId) {
        return ResponseEntity.ok(postService.getPollVoters(postId, userId));
    }

    /** Who RSVP'd with what status, grouped — the event equivalent of poll voters. */
    @GetMapping("/{postId}/rsvp/voters")
    public ResponseEntity<Map<String, List<com.socialmedia.social.dto.VoterSummary>>> getEventRsvps(
            @PathVariable Long postId,
            @RequestAttribute("userId") Long userId) {
        return ResponseEntity.ok(postService.getEventRsvps(postId, userId));
    }

    @GetMapping("/hashtags/trending")
    public ResponseEntity<List<HashtagResponse>> getTrendingHashtags(
            @RequestParam(defaultValue = "10") int limit) {
        return ResponseEntity.ok(postService.getTrendingHashtags(limit));
    }

    @GetMapping("/hashtag/{tag}")
    public ResponseEntity<Page<PostResponse>> getPostsByHashtag(
            @PathVariable String tag,
            @RequestAttribute("userId") Long userId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        Pageable pageable = PageRequest.of(page, size);
        Page<PostResponse> posts = postService.getPostsByHashtag(tag, userId, pageable);
        return ResponseEntity.ok(posts);
    }
}
