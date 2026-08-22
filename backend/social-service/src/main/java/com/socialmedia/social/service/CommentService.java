package com.socialmedia.social.service;

import com.socialmedia.social.dto.CommentRequest;
import com.socialmedia.social.dto.CommentResponse;
import com.socialmedia.social.entity.Comment;
import com.socialmedia.social.entity.Like.LikeTargetType;
import com.socialmedia.social.entity.Post;
import com.socialmedia.social.entity.UserProfile;
import com.socialmedia.social.repository.CommentRepository;
import com.socialmedia.social.repository.LikeRepository;
import com.socialmedia.social.repository.PostRepository;
import com.socialmedia.social.repository.UserProfileRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class CommentService {

    private final CommentRepository commentRepository;
    private final PostRepository postRepository;
    private final LikeRepository likeRepository;
    private final UserProfileRepository userProfileRepository;
    private final NotificationService notificationService;
    private final FCMService fcmService;
    private final BlockService blockService;
    
    @Value("${aws.s3.bucket-name}")
    private String bucketName;

    @Value("${aws.s3.region}")
    private String region;

    @Transactional
    public CommentResponse createComment(CommentRequest request, Long userId) {
        Post post = postRepository.findById(request.getPostId())
                .orElseThrow(() -> new RuntimeException("Post not found"));
        
        // ✅ BLOCKING FIX: Check if either user has blocked the other
        if (blockService.isEitherBlocked(userId, post.getUserId())) {
            throw new RuntimeException("Cannot comment on this post");
        }
        
        Comment comment = new Comment();
        comment.setPostId(request.getPostId());
        comment.setUserId(userId);
        comment.setContent(request.getContent());
        comment.setParentCommentId(request.getParentCommentId());
        
        Comment savedComment = commentRepository.save(comment);
        
        post.setCommentsCount(post.getCommentsCount() + 1);
        postRepository.save(post);

        // notify post author that someone commented or replied
        Long postAuthorId = post.getUserId();
        if (!postAuthorId.equals(userId)) {
            String body = request.getParentCommentId() != null ? "replied to a comment on your post" : "commented on your post";
            notificationService.createNotification(postAuthorId, "COMMENT", userId, post.getId(), body);
            
            // Send FCM push notification
            try {
                fcmService.onPostCommented(postAuthorId, userId, post.getId(), request.getContent());
            } catch (Exception e) {
                System.out.println("[COMMENT SERVICE] ⚠️ Failed to send FCM for comment: " + e.getMessage());
            }
        }
        
        return mapToResponse(savedComment, userId);
    }

    @Transactional
    public CommentResponse updateComment(Long commentId, String content, Long userId) {
        Comment comment = commentRepository.findById(commentId)
                .orElseThrow(() -> new RuntimeException("Comment not found"));
        
        if (!comment.getUserId().equals(userId)) {
            throw new RuntimeException("Unauthorized to update this comment");
        }
        
        comment.setContent(content);
        Comment updatedComment = commentRepository.save(comment);
        
        return mapToResponse(updatedComment, userId);
    }

    @Transactional
    public void deleteComment(Long commentId, Long userId) {
        Comment comment = commentRepository.findById(commentId)
                .orElseThrow(() -> new RuntimeException("Comment not found"));
        
        if (!comment.getUserId().equals(userId)) {
            throw new RuntimeException("Unauthorized to delete this comment");
        }
        
        Post post = postRepository.findById(comment.getPostId())
                .orElseThrow(() -> new RuntimeException("Post not found"));
        post.setCommentsCount(post.getCommentsCount() - 1);
        postRepository.save(post);
        
        likeRepository.deleteByTargetTypeAndTargetId(LikeTargetType.COMMENT, commentId);
        
        commentRepository.delete(comment);
    }

    @Transactional(readOnly = true)
    public Page<CommentResponse> getPostComments(Long postId, Long userId, Pageable pageable) {
        Page<Comment> comments = commentRepository.findByPostIdAndParentCommentIdIsNullOrderByCreatedAtDesc(postId, pageable);
        return comments.map(comment -> mapToResponseWithReplies(comment, userId));
    }

    private CommentResponse mapToResponse(Comment comment, Long userId) {
        CommentResponse response = new CommentResponse();
        response.setId(comment.getId());
        response.setPostId(comment.getPostId());
        response.setUserId(comment.getUserId());
        response.setContent(comment.getContent());
        response.setParentCommentId(comment.getParentCommentId());
        response.setLikesCount(comment.getLikesCount());
        response.setCreatedAt(comment.getCreatedAt());
        response.setUpdatedAt(comment.getUpdatedAt());
        
        // Fetch user profile to get author name and picture
        userProfileRepository.findByUserId(comment.getUserId()).ifPresent(userProfile -> {
            response.setAuthorName(userProfile.getFullName() != null && !userProfile.getFullName().isEmpty() 
                ? userProfile.getFullName() 
                : userProfile.getUsername());
            
            // Construct full S3 URL for profile picture
            String profilePictureUrl = userProfile.getProfilePictureUrl();
            if (profilePictureUrl != null && !profilePictureUrl.isEmpty()) {
                // Only construct URL if it's not already a full URL
                if (!profilePictureUrl.startsWith("http://") && !profilePictureUrl.startsWith("https://")) {
                    profilePictureUrl = String.format("https://%s.s3.%s.amazonaws.com/%s", 
                        bucketName, region, profilePictureUrl);
                }
            }
            response.setAuthorProfilePictureUrl(profilePictureUrl);
        });
        
        if (userId != null) {
            response.setIsLikedByCurrentUser(
                likeRepository.existsByUserIdAndTargetTypeAndTargetId(
                    userId, LikeTargetType.COMMENT, comment.getId()));
        }
        
        return response;
    }

    private CommentResponse mapToResponseWithReplies(Comment comment, Long userId) {
        CommentResponse response = mapToResponse(comment, userId);
        
        List<Comment> replies = commentRepository.findByParentCommentIdOrderByCreatedAtAsc(comment.getId());
        response.setReplies(replies.stream()
                .map(reply -> mapToResponse(reply, userId))
                .collect(Collectors.toList()));
        
        return response;
    }
}
