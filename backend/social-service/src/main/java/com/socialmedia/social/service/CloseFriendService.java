package com.socialmedia.social.service;

import com.socialmedia.social.dto.UserProfileResponse;
import com.socialmedia.social.entity.CloseFriend;
import com.socialmedia.social.repository.CloseFriendRepository;
import com.socialmedia.social.repository.UserProfileRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
@Slf4j
public class CloseFriendService {

    private final CloseFriendRepository closeFriendRepository;
    private final UserProfileRepository userProfileRepository;
    
    @Value("${aws.s3.bucket-name}")
    private String bucketName;

    @Value("${aws.s3.region}")
    private String region;

    /**
     * Get all close friends of the authenticated user
     */
    @Transactional(readOnly = true)
    public List<UserProfileResponse> getCloseFriends(Long userId) {
        log.info("Getting close friends for user: {}", userId);
        
        List<Long> closeFriendIds = closeFriendRepository.findCloseFriendUserIds(userId);
        
        return closeFriendIds.stream()
            .map(friendId -> userProfileRepository.findById(friendId).orElse(null))
            .filter(profile -> profile != null)
            .map(profile -> {
                UserProfileResponse response = new UserProfileResponse();
                response.setUserId(profile.getId());
                response.setUsername(profile.getUsername());
                response.setFullName(profile.getFullName());
                response.setBio(profile.getBio());
                
                // Construct full S3 URL for profile picture
                String profilePictureUrl = profile.getProfilePictureUrl();
                if (profilePictureUrl != null && !profilePictureUrl.isEmpty()) {
                    // Only construct URL if it's not already a full URL
                    if (!profilePictureUrl.startsWith("http://") && !profilePictureUrl.startsWith("https://")) {
                        profilePictureUrl = String.format("https://%s.s3.%s.amazonaws.com/%s", 
                            bucketName, region, profilePictureUrl);
                    }
                }
                response.setProfilePictureUrl(profilePictureUrl);
                
                response.setIsPrivate(profile.getIsPrivate());
                response.setIsVerified(profile.getIsVerified());
                return response;
            })
            .collect(Collectors.toList());
    }

    /**
     * Add a user to close friends list
     */
    @Transactional
    public void addCloseFriend(Long userId, Long closeFriendUserId) {
        log.info("Adding user {} to close friends of user {}", closeFriendUserId, userId);
        
        // Check if already exists
        if (closeFriendRepository.existsByUserIdAndCloseFriendUserId(userId, closeFriendUserId)) {
            log.info("User {} is already in close friends of user {}", closeFriendUserId, userId);
            return;
        }
        
        // Verify the target user exists
        if (!userProfileRepository.existsById(closeFriendUserId)) {
            throw new IllegalArgumentException("User not found: " + closeFriendUserId);
        }
        
        CloseFriend closeFriend = new CloseFriend();
        closeFriend.setUserId(userId);
        closeFriend.setCloseFriendUserId(closeFriendUserId);
        
        closeFriendRepository.save(closeFriend);
        log.info("Successfully added user {} to close friends", closeFriendUserId);
    }

    /**
     * Remove a user from close friends list
     */
    @Transactional
    public void removeCloseFriend(Long userId, Long closeFriendUserId) {
        log.info("Removing user {} from close friends of user {}", closeFriendUserId, userId);
        closeFriendRepository.deleteByUserIdAndCloseFriendUserId(userId, closeFriendUserId);
        log.info("Successfully removed user {} from close friends", closeFriendUserId);
    }

    /**
     * Check if a user is in close friends list
     */
    @Transactional(readOnly = true)
    public boolean isCloseFriend(Long userId, Long targetUserId) {
        return closeFriendRepository.existsByUserIdAndCloseFriendUserId(userId, targetUserId);
    }

    /**
     * Get close friend IDs (for filtering posts)
     */
    @Transactional(readOnly = true)
    public List<Long> getCloseFriendIds(Long userId) {
        return closeFriendRepository.findCloseFriendUserIds(userId);
    }

    /**
     * ✅ ADDED: Get users who have this user as close friend
     * Used for feed to include posts from users who have viewer as close friend
     */
    @Transactional(readOnly = true)
    public List<Long> getUsersWhoHaveAsCloseFriend(Long userId) {
        return closeFriendRepository.findUsersWhoHaveAsCloseFriend(userId);
    }

    /**
     * Count close friends
     */
    @Transactional(readOnly = true)
    public long countCloseFriends(Long userId) {
        return closeFriendRepository.countByUserId(userId);
    }
}
