package com.socialmedia.social.service;

import com.socialmedia.social.dto.BlockRequest;
import com.socialmedia.social.dto.BlockedUserResponse;
import com.socialmedia.social.entity.BlockedUser;
import com.socialmedia.social.entity.UserProfile;
import com.socialmedia.social.repository.BlockedUserRepository;
import com.socialmedia.social.repository.FollowerRepository;
import com.socialmedia.social.repository.UserProfileRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@RequiredArgsConstructor
public class BlockService {
    
    private final BlockedUserRepository blockedUserRepository;
    private final FollowerRepository followerRepository;
    private final UserProfileRepository userProfileRepository;
    
    @Value("${aws.s3.bucket-name}")
    private String bucketName;

    @Value("${aws.s3.region}")
    private String region;
    @Transactional
    public BlockedUserResponse blockUser(Long blockerId, Long blockedId, BlockRequest request) {
        if (blockerId.equals(blockedId)) {
            throw new RuntimeException("Cannot block yourself");
        }
        
        if (blockedUserRepository.existsByBlockerIdAndBlockedId(blockerId, blockedId)) {
            throw new RuntimeException("User is already blocked");
        }
        
        BlockedUser blockedUser = new BlockedUser();
        blockedUser.setBlockerId(blockerId);
        blockedUser.setBlockedId(blockedId);
        blockedUser.setReason(request != null ? request.getReason() : null);
        
        BlockedUser saved = blockedUserRepository.save(blockedUser);
        
        removeFollowRelationships(blockerId, blockedId);
        
        return mapToResponse(saved);
    }
    
    @Transactional
    public void unblockUser(Long blockerId, Long blockedId) {
        BlockedUser blockedUser = blockedUserRepository.findByBlockerIdAndBlockedId(blockerId, blockedId)
                .orElseThrow(() -> new RuntimeException("Block relationship not found"));
        
        blockedUserRepository.delete(blockedUser);
    }
    
    @Transactional(readOnly = true)
    public boolean isBlocked(Long blockerId, Long blockedId) {
        return blockedUserRepository.existsByBlockerIdAndBlockedId(blockerId, blockedId);
    }
    
    
    @Transactional(readOnly = true)
    public boolean isEitherBlocked(Long userId1, Long userId2) {
        return blockedUserRepository.isEitherBlocked(userId1, userId2);
    }
    
    
    @Transactional(readOnly = true)
    public Page<BlockedUserResponse> getBlockedUsers(Long blockerId, Pageable pageable) {
        Page<BlockedUser> blockedUsers = blockedUserRepository.findByBlockerIdOrderByCreatedAtDesc(blockerId, pageable);
        return blockedUsers.map(this::mapToResponse);
    }
    
   
    @Transactional(readOnly = true)
    public List<Long> getBlockedUserIds(Long blockerId) {
        return blockedUserRepository.findBlockedIdsByBlockerId(blockerId);
    }
    
    
    @Transactional(readOnly = true)
    public List<Long> getBlockerUserIds(Long blockedId) {
        return blockedUserRepository.findBlockerIdsByBlockedId(blockedId);
    }
    
    
    @Transactional(readOnly = true)
    public long countBlockedUsers(Long blockerId) {
        return blockedUserRepository.countByBlockerId(blockerId);
    }
    
    private void removeFollowRelationships(Long userId1, Long userId2) {
        followerRepository.findByFollowerIdAndFollowingId(userId1, userId2)
                .ifPresent(followerRepository::delete);
        followerRepository.findByFollowerIdAndFollowingId(userId2, userId1)
                .ifPresent(followerRepository::delete);
    }
    private BlockedUserResponse mapToResponse(BlockedUser blockedUser) {
        // Fetch the blocked user's profile to get username and profile picture
        UserProfile blockedUserProfile = userProfileRepository.findByUserId(blockedUser.getBlockedId())
                .orElse(null);
        
        String username = null;
        String profilePicUrl = null;
        
        if (blockedUserProfile != null) {
            // Get username, prefer username field, fallback to fullName if username is not set
            username = blockedUserProfile.getUsername();
            if (username == null || username.isBlank()) {
                username = blockedUserProfile.getFullName();
            }
            
            // Construct full S3 URL for profile picture
            String rawProfilePicUrl = blockedUserProfile.getProfilePictureUrl();
            if (rawProfilePicUrl != null && !rawProfilePicUrl.isEmpty()) {
                // Only construct URL if it's not already a full URL
                if (!rawProfilePicUrl.startsWith("http://") && !rawProfilePicUrl.startsWith("https://")) {
                    profilePicUrl = String.format("https://%s.s3.%s.amazonaws.com/%s", 
                        bucketName, region, rawProfilePicUrl);
                } else {
                    profilePicUrl = rawProfilePicUrl;
                }
            }
        }
        
        // Fallback to user ID if username not found
        if (username == null || username.isBlank()) {
            username = "user" + blockedUser.getBlockedId();
        }
        
        return BlockedUserResponse.builder()
                .id(blockedUser.getId())
                .blockedUserId(blockedUser.getBlockedId())
                .blockedUsername(username)
                .blockedProfilePicUrl(profilePicUrl)
                .reason(blockedUser.getReason())
                .blockedAt(blockedUser.getCreatedAt())
                .build();
    }
}
