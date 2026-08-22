package com.socialmedia.social.service;

import com.socialmedia.social.dto.PostResponse;
import com.socialmedia.social.entity.Post;
import com.socialmedia.social.entity.Save;
import com.socialmedia.social.repository.LikeRepository;
import com.socialmedia.social.repository.PostRepository;
import com.socialmedia.social.repository.SaveRepository;
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
public class SaveService {

    private final SaveRepository saveRepository;
    private final PostRepository postRepository;
    private final LikeRepository likeRepository;
    private final UserProfileRepository userProfileRepository;

    @Value("${aws.s3.bucket-name}")
    private String bucketName;

    @Value("${aws.s3.region}")
    private String region;

    @Transactional
    public void savePost(Long postId, Long userId) {
        if (saveRepository.existsByUserIdAndPostId(userId, postId)) {
            throw new RuntimeException("Post already saved");
        }
        
        Post post = postRepository.findById(postId)
                .orElseThrow(() -> new RuntimeException("Post not found"));
        
        Save save = new Save();
        save.setUserId(userId);
        save.setPostId(postId);
        
        saveRepository.save(save);
        
        post.setSavesCount(post.getSavesCount() + 1);
        postRepository.save(post);
    }

    @Transactional
    public void unsavePost(Long postId, Long userId) {
        Save save = saveRepository.findByUserIdAndPostId(userId, postId)
                .orElseThrow(() -> new RuntimeException("Save not found"));
        
        Post post = postRepository.findById(postId)
                .orElseThrow(() -> new RuntimeException("Post not found"));
        
        saveRepository.delete(save);
        
        post.setSavesCount(Math.max(0, post.getSavesCount() - 1));
        postRepository.save(post);
    }

    @Transactional(readOnly = true)
    public Page<PostResponse> getSavedPosts(Long userId, Pageable pageable) {
        Page<Save> saves = saveRepository.findByUserIdOrderByCreatedAtDesc(userId, pageable);
        return saves.map(save -> {
            Post post = postRepository.findById(save.getPostId())
                    .orElseThrow(() -> new RuntimeException("Post not found"));
            return mapToResponse(post, userId);
        });
    }

    private PostResponse mapToResponse(Post post, Long userId) {
        PostResponse response = new PostResponse();
        response.setId(post.getId());
        response.setUserId(post.getUserId());
        response.setContent(post.getContent());
        
        // Convert S3 keys to full URLs (only if not already full URLs)
        List<String> fullImageUrls = post.getImageUrls().stream()
            .map(key -> {
                // If already a full URL, return as is
                if (key.startsWith("http://") || key.startsWith("https://")) {
                    return key;
                }
                // Otherwise construct the full URL
                return String.format("https://%s.s3.%s.amazonaws.com/%s", bucketName, region, key);
            })
            .collect(Collectors.toList());
        response.setImageUrls(fullImageUrls);
        
        response.setIsPublic(post.getIsPublic());
        response.setLikesCount(post.getLikesCount());
        response.setCommentsCount(post.getCommentsCount());
        response.setSharesCount(post.getSharesCount());
        response.setSavesCount(post.getSavesCount());
        response.setCreatedAt(post.getCreatedAt());
        response.setUpdatedAt(post.getUpdatedAt());
        
        // Fetch and populate author information
        userProfileRepository.findByUserId(post.getUserId()).ifPresent(profile -> {
            String name = profile.getFullName() != null && !profile.getFullName().isBlank()
                    ? profile.getFullName()
                    : profile.getUsername();
            response.setAuthorName(name);
            
            // Construct full S3 URL for profile picture
            String profilePictureUrl = profile.getProfilePictureUrl();
            if (profilePictureUrl != null && !profilePictureUrl.isEmpty()) {
                // Only construct URL if it's not already a full URL
                if (!profilePictureUrl.startsWith("http://") && !profilePictureUrl.startsWith("https://")) {
                    profilePictureUrl = String.format("https://%s.s3.%s.amazonaws.com/%s", 
                        bucketName, region, profilePictureUrl);
                }
            }
            response.setAuthorProfilePictureUrl(profilePictureUrl);
        });
        
        // Fallback if profile not found
        if (response.getAuthorName() == null || response.getAuthorName().isBlank()) {
            response.setAuthorName("User " + post.getUserId());
        }
        
        if (userId != null) {
            response.setIsLikedByCurrentUser(
                likeRepository.existsByUserIdAndTargetTypeAndTargetId(
                    userId, com.socialmedia.social.entity.Like.LikeTargetType.POST, post.getId()));
            response.setIsSavedByCurrentUser(
                saveRepository.existsByUserIdAndPostId(userId, post.getId()));
        }
        
        return response;
    }
}
