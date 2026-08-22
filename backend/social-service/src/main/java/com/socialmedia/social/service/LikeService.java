package com.socialmedia.social.service;

import com.socialmedia.social.entity.Comment;
import com.socialmedia.social.entity.Like;
import com.socialmedia.social.entity.Like.LikeTargetType;
import com.socialmedia.social.entity.Post;
import com.socialmedia.social.repository.CommentRepository;
import com.socialmedia.social.repository.LikeRepository;
import com.socialmedia.social.repository.PostRepository;
import com.socialmedia.social.service.NotificationService;
import lombok.RequiredArgsConstructor;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
public class LikeService {

    private final LikeRepository likeRepository;
    private final PostRepository postRepository;
    private final CommentRepository commentRepository;
    private final NotificationService notificationService;
    private final FCMService fcmService;
    private final BlockService blockService;

    @Transactional
    public void likePost(Long postId, Long userId) {
        System.out.println("[LIKE SERVICE] likePost called - postId: " + postId + ", userId: " + userId);
        
        if (likeRepository.existsByUserIdAndTargetTypeAndTargetId(userId, LikeTargetType.POST, postId)) {
            System.out.println("[LIKE SERVICE] Post already liked - returning silently");
            return; // Idempotent: if already liked, just return success
        }
        
        Post post = postRepository.findById(postId)
                .orElseThrow(() -> new RuntimeException("Post not found"));
        
        // ✅ BLOCKING FIX: Check if either user has blocked the other
        if (blockService.isEitherBlocked(userId, post.getUserId())) {
            throw new RuntimeException("Cannot like this post");
        }
        
        System.out.println("[LIKE SERVICE] Post found - current likes_count: " + post.getLikesCount());
        
        Like like = new Like();
        like.setUserId(userId);
        like.setTargetType(LikeTargetType.POST);
        like.setTargetId(postId);
        
        try {
            likeRepository.save(like);
            System.out.println("[LIKE SERVICE] Like entity saved");
        } catch (DataIntegrityViolationException e) {
            // ✅ RACE CONDITION HANDLING: Two rapid clicks both passed the existence check
            // but only one can insert due to unique constraint. Treat as idempotent - just return.
            System.out.println("[LIKE SERVICE] ⚠️ Unique constraint violation (race condition) - already liked by this user");
            return;
        }
        
        // ✅ FIX: Database trigger automatically increments likes_count when like is inserted
        // DO NOT manually increment here - it causes double counting!
        // The trigger trg_after_like_insert handles the increment
        System.out.println("[LIKE SERVICE] ✅ Database trigger will automatically increment likes_count");

        // notify post author
        if (!post.getUserId().equals(userId)) {
            String body = "liked your post";
            notificationService.createNotification(post.getUserId(), "LIKE", userId, postId, body);
            
            // Send FCM push notification
            try {
                fcmService.onPostLiked(post.getUserId(), userId, postId);
            } catch (Exception e) {
                System.out.println("[LIKE SERVICE] ⚠️ Failed to send FCM for like: " + e.getMessage());
            }
        }
        System.out.println("[LIKE SERVICE] likePost completed successfully");
    }

    @Transactional
    public void unlikePost(Long postId, Long userId) {
        Like like = likeRepository.findByUserIdAndTargetTypeAndTargetId(userId, LikeTargetType.POST, postId)
                .orElse(null);
        
        // If like doesn't exist, it's already unliked - just return silently
        if (like == null) {
            System.out.println("[LIKE SERVICE] unlikePost called but like not found - already unliked");
            return;
        }
        
        Post post = postRepository.findById(postId)
                .orElseThrow(() -> new RuntimeException("Post not found"));
        
        likeRepository.delete(like);
        
        // ✅ FIX: Database trigger automatically decrements likes_count when like is deleted
        // DO NOT manually decrement here - it causes double decrement!
        // The trigger trg_after_like_delete handles the decrement
        System.out.println("[LIKE SERVICE] ✅ Database trigger will automatically decrement likes_count");
    }

    @Transactional
    public void likeComment(Long commentId, Long userId) {
        if (likeRepository.existsByUserIdAndTargetTypeAndTargetId(userId, LikeTargetType.COMMENT, commentId)) {
            throw new RuntimeException("Comment already liked");
        }
        
        Comment comment = commentRepository.findById(commentId)
                .orElseThrow(() -> new RuntimeException("Comment not found"));
        
        // ✅ BLOCKING FIX: Check if either user has blocked the other
        if (blockService.isEitherBlocked(userId, comment.getUserId())) {
            throw new RuntimeException("Cannot like this comment");
        }
        
        Like like = new Like();
        like.setUserId(userId);
        like.setTargetType(LikeTargetType.COMMENT);
        like.setTargetId(commentId);
        
        likeRepository.save(like);
        
        // Use atomic increment to prevent race condition
        commentRepository.incrementLikesCount(commentId);

        // notify comment author (only for comment likes)
        if (!comment.getUserId().equals(userId)) {
            String body = "liked your comment";
            notificationService.createNotification(comment.getUserId(), "LIKE", userId, commentId, body);
        }
    }

    @Transactional
    public void unlikeComment(Long commentId, Long userId) {
        Like like = likeRepository.findByUserIdAndTargetTypeAndTargetId(userId, LikeTargetType.COMMENT, commentId)
                .orElseThrow(() -> new RuntimeException("Like not found"));
        
        Comment comment = commentRepository.findById(commentId)
                .orElseThrow(() -> new RuntimeException("Comment not found"));
        
        likeRepository.delete(like);
        
        // Use atomic decrement to prevent race condition
        commentRepository.decrementLikesCount(commentId);
    }
}
