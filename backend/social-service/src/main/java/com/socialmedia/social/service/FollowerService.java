package com.socialmedia.social.service;

import com.socialmedia.social.dto.FollowerResponse;
import com.socialmedia.social.dto.FollowerStatsResponse;
import com.socialmedia.social.entity.Follower;
import com.socialmedia.social.entity.UserProfile;
import com.socialmedia.social.repository.FollowerRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@RequiredArgsConstructor
public class FollowerService {
    
    private final FollowerRepository followerRepository;
    private final BlockService blockService;
    private final NotificationService notificationService;
    private final UserProfileService userProfileService;
    
    @Transactional
    public void followUser(Long followerId, Long followingId) {
        if (followerId.equals(followingId)) {
            throw new IllegalArgumentException("Cannot follow yourself");
        }
        
        if (blockService.isEitherBlocked(followerId, followingId)) {
            throw new IllegalArgumentException("Cannot follow this user due to block");
        }
        
        if (followerRepository.existsByFollowerIdAndFollowingId(followerId, followingId)) {
            throw new IllegalArgumentException("Already following this user");
        }
        
        // Check if target user has a private account
        UserProfile targetProfile = userProfileService.getUserProfileById(followingId);
        if (targetProfile == null) {
            throw new IllegalArgumentException("User not found");
        }
        if (Boolean.TRUE.equals(targetProfile.getIsPrivate())) {
            throw new IllegalArgumentException("Cannot follow a private account directly. Please send a follow request instead.");
        }
        
        // Create the follower relationship
        createFollowerRelationship(followerId, followingId);
    }
    
    /**
     * Internal method to create a follower relationship without privacy checks.
     * Used by FollowRequestService when accepting a follow request.
     */
    @Transactional
    public void createFollowerRelationship(Long followerId, Long followingId) {
        if (followerId.equals(followingId)) {
            throw new IllegalArgumentException("Cannot follow yourself");
        }
        
        if (blockService.isEitherBlocked(followerId, followingId)) {
            throw new IllegalArgumentException("Cannot follow this user due to block");
        }
        
        if (followerRepository.existsByFollowerIdAndFollowingId(followerId, followingId)) {
            throw new IllegalArgumentException("Already following this user");
        }
        
        Follower follower = new Follower(followerId, followingId);
        followerRepository.save(follower);

        // notify the followed user
        if (!followingId.equals(followerId)) {
            String content = "started following you";
            notificationService.createNotification(followingId, "FOLLOW", followerId, followingId, content);
        }
    }
    
    @Transactional
    public void unfollowUser(Long followerId, Long followingId) {
        if (!followerRepository.existsByFollowerIdAndFollowingId(followerId, followingId)) {
            throw new IllegalArgumentException("Not following this user");
        }
        
        followerRepository.deleteByFollowerIdAndFollowingId(followerId, followingId);
    }
    
    public boolean isFollowing(Long followerId, Long followingId) {
        return followerRepository.existsByFollowerIdAndFollowingId(followerId, followingId);
    }
    
    public Page<FollowerResponse> getFollowers(Long userId, Pageable pageable) {
        Page<Follower> followers = followerRepository.findByFollowingId(userId, pageable);
        return followers.map(f -> new FollowerResponse(
            f.getId(),
            f.getFollowerId(), 
            f.getCreatedAt()
        ));
    }
    
    public Page<FollowerResponse> getFollowing(Long userId, Pageable pageable) {
        Page<Follower> following = followerRepository.findByFollowerId(userId, pageable);
        return following.map(f -> new FollowerResponse(
            f.getId(),
            f.getFollowingId(),
            f.getCreatedAt()
        ));
    }
    
    public FollowerStatsResponse getFollowerStats(Long targetUserId, Long requestingUserId) {
        long followersCount = followerRepository.countByFollowingId(targetUserId);
        long followingCount = followerRepository.countByFollowerId(targetUserId);
        
        boolean isFollowing = false;
        boolean isFollowedBy = false;
        boolean isMutual = false;
        
        if (requestingUserId != null && !requestingUserId.equals(targetUserId)) {
            isFollowing = followerRepository.existsByFollowerIdAndFollowingId(requestingUserId, targetUserId);
            isFollowedBy = followerRepository.existsByFollowerIdAndFollowingId(targetUserId, requestingUserId);
            isMutual = isFollowing && isFollowedBy;
        }
        
        return new FollowerStatsResponse(
            targetUserId,
            followersCount,
            followingCount,
            isFollowing,
            isFollowedBy,
            isMutual
        );
    }
    
    public List<Long> getFollowingIds(Long userId) {
        return followerRepository.findFollowingIdsByUserId(userId);
    }
    
    public Page<FollowerResponse> getMutualFollowers(Long userId, Pageable pageable) {
        Page<Follower> mutuals = followerRepository.findMutualFollowers(userId, pageable);
        return mutuals.map(f -> new FollowerResponse(
            f.getId(),
            f.getFollowingId(),
            f.getCreatedAt()
        ));
    }
    
    public boolean areMutualFollowers(Long userId1, Long userId2) {
        return followerRepository.areMutualFollowers(userId1, userId2);
    }
}
