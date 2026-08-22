package com.socialmedia.social.controller;

import com.socialmedia.social.dto.PostResponse;
import com.socialmedia.social.service.SaveService;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/saves")
@RequiredArgsConstructor
public class SaveController {

    private final SaveService saveService;

    @PostMapping("/{postId}")
    public ResponseEntity<Void> savePost(
            @PathVariable Long postId,
            @RequestAttribute("userId") Long userId) {
        saveService.savePost(postId, userId);
        return ResponseEntity.ok().build();
    }

    @DeleteMapping("/{postId}")
    public ResponseEntity<Void> unsavePost(
            @PathVariable Long postId,
            @RequestAttribute("userId") Long userId) {
        saveService.unsavePost(postId, userId);
        return ResponseEntity.noContent().build();
    }

    @GetMapping
    public ResponseEntity<Page<PostResponse>> getSavedPosts(
            @RequestAttribute("userId") Long userId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "20") int size) {
        Pageable pageable = PageRequest.of(page, size);
        Page<PostResponse> posts = saveService.getSavedPosts(userId, pageable);
        return ResponseEntity.ok(posts);
    }
}
