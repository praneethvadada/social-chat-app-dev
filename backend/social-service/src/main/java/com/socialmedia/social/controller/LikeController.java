package com.socialmedia.social.controller;

import com.socialmedia.social.service.LikeService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/likes")
@RequiredArgsConstructor
public class LikeController {

    private final LikeService likeService;

    @PostMapping("/post/{postId}")
    public ResponseEntity<Void> likePost(
            @PathVariable Long postId,
            @RequestAttribute("userId") Long userId) {
        likeService.likePost(postId, userId);
        return ResponseEntity.ok().build();
    }

    @DeleteMapping("/post/{postId}")
    public ResponseEntity<Void> unlikePost(
            @PathVariable Long postId,
            @RequestAttribute("userId") Long userId) {
        likeService.unlikePost(postId, userId);
        return ResponseEntity.noContent().build();
    }

    @PostMapping("/comment/{commentId}")
    public ResponseEntity<Void> likeComment(
            @PathVariable Long commentId,
            @RequestAttribute("userId") Long userId) {
        likeService.likeComment(commentId, userId);
        return ResponseEntity.ok().build();
    }

    @DeleteMapping("/comment/{commentId}")
    public ResponseEntity<Void> unlikeComment(
            @PathVariable Long commentId,
            @RequestAttribute("userId") Long userId) {
        likeService.unlikeComment(commentId, userId);
        return ResponseEntity.noContent().build();
    }
}
