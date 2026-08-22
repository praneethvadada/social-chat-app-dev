package com.socialmedia.social.service;

import com.socialmedia.social.dto.UserProfileRequest;
import com.socialmedia.social.dto.UserProfileResponse;
import com.socialmedia.social.dto.UserSearchResult;
import com.socialmedia.social.entity.UserProfile;
import com.socialmedia.social.repository.FollowerRepository;
import com.socialmedia.social.repository.PostRepository;
import com.socialmedia.social.repository.UserProfileRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.PageImpl;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
import java.time.ZoneId;

@Service
@RequiredArgsConstructor
public class UserProfileService {
    
    private final UserProfileRepository userProfileRepository;
    private final com.socialmedia.social.client.AuthIdentityClient authIdentityClient;
    private final FollowerRepository followerRepository;
    private final PostRepository postRepository;
    private final BlockService blockService;
    private final com.socialmedia.social.client.NotificationRelayClient notificationRelayClient;

    @Value("${aws.s3.bucket-name}")
    private String bucketName;

    @Value("${aws.s3.region}")
    private String region;
    
    @Transactional
    public UserProfileResponse createProfile(Long userId, String username, String email, String fullName) {
        System.out.println("\n===== CREATE/UPDATE PROFILE =====");
        System.out.println("userId: " + userId);
        System.out.println("username: " + username);
        System.out.println("email: " + email);
        System.out.println("fullName: " + fullName);
        
        // Check if profile already exists
        UserProfile profile = userProfileRepository.findByUserId(userId)
                .orElse(null);
        
        if (profile != null) {
            System.out.println("\n[PROFILE EXISTS - UPDATING]");
            System.out.println("Old fullName: " + profile.getFullName());
            System.out.println("Old username: " + profile.getUsername());
            // Profile exists, update with real data (in case it was created with placeholders)
            profile.setUsername(username);
            profile.setEmail(email);
            profile.setFullName(fullName);
            System.out.println("New fullName: " + profile.getFullName());
            System.out.println("New username: " + profile.getUsername());
            UserProfile updatedProfile = userProfileRepository.save(profile);
            System.out.println("Profile updated and saved");
            return mapToResponse(updatedProfile, userId);
        }
        
        System.out.println("\n[PROFILE DOES NOT EXIST - CREATING NEW]");
        // Profile doesn't exist, create new one
        profile = new UserProfile();
        profile.setUserId(userId);
        profile.setUsername(username);
        profile.setEmail(email);
        profile.setFullName(fullName);
        profile.setIsPrivate(false);
        profile.setIsVerified(false);
        
        // Explicitly set timestamps if not auto-set by Hibernate
        if (profile.getCreatedAt() == null) {
            profile.setCreatedAt(java.time.LocalDateTime.now());
        }
        if (profile.getUpdatedAt() == null) {
            profile.setUpdatedAt(java.time.LocalDateTime.now());
        }
        
        UserProfile savedProfile = userProfileRepository.save(profile);
        System.out.println("New profile created with fullName: " + savedProfile.getFullName());
        return mapToResponse(savedProfile, userId);
    }
    
    @Transactional
    public UserProfileResponse getProfile(Long userId, Long requestingUserId) {
        System.out.println("\n===== GET PROFILE =====");
        System.out.println("Requested userId: " + userId);
        
        // Reject invalid userId values
        if (userId == null || userId <= 0) {
            System.out.println("❌ Invalid userId: " + userId);
            throw new IllegalArgumentException("Invalid userId: " + userId);
        }
        
        // ✅ BLOCKING FIX: Check if either user has blocked the other
        if (!userId.equals(requestingUserId) && blockService.isEitherBlocked(userId, requestingUserId)) {
            throw new RuntimeException("Cannot access this user's profile");
        }
        
        UserProfile profile = userProfileRepository.findByUserId(userId)
                .orElseGet(() -> {
                    System.out.println("Profile not found, auto-creating with placeholder");
                    // Auto-create profile if it doesn't exist
                    UserProfile newProfile = new UserProfile();
                    newProfile.setUserId(userId);
                    newProfile.setUsername("user_" + userId);
                    newProfile.setEmail("user_" + userId + "@social.com");
                    newProfile.setFullName("User " + userId);
                    newProfile.setIsPrivate(false);
                    newProfile.setIsVerified(false);
                    
                    // Explicitly set timestamps if not auto-set by Hibernate
                    if (newProfile.getCreatedAt() == null) {
                        newProfile.setCreatedAt(java.time.LocalDateTime.now());
                    }
                    if (newProfile.getUpdatedAt() == null) {
                        newProfile.setUpdatedAt(java.time.LocalDateTime.now());
                    }
                    
                    return userProfileRepository.save(newProfile);
                });
        
        System.out.println("Profile found/created:");
        System.out.println("  userId: " + profile.getUserId());
        System.out.println("  username: " + profile.getUsername());
        System.out.println("  email: " + profile.getEmail());
        System.out.println("  fullName: " + profile.getFullName());
        System.out.println("  createdAt: " + profile.getCreatedAt());
        
        return mapToResponseWithStats(profile, requestingUserId);
    }

    /**
     * Re-pull identity fields from auth-service for one user.
     *
     * The replica is normally kept fresh on write, but this is the self-heal
     * path: call it if a sync was missed, or from a periodic reconcile.
     */
    @Transactional
    public void reconcileFromAuth(Long userId) {
        UserProfile profile = userProfileRepository.findByUserId(userId).orElse(null);
        if (profile == null) return;
        Map<String, Object> authoritative = authIdentityClient.fetchIdentity(userId);
        if (authoritative.isEmpty()) return;

        Object username = authoritative.get("username");
        Object fullName = authoritative.get("fullName");
        if (username != null) profile.setUsername(username.toString());
        if (fullName != null) profile.setFullName(fullName.toString());
        profile.setSyncedAt(LocalDateTime.now(ZoneId.of("UTC")));
        userProfileRepository.save(profile);
    }

    @Transactional(readOnly = true)
    public UserProfile getUserProfileById(Long userId) {
        if (userId == null || userId <= 0) {
            return null;
        }
        return userProfileRepository.findByUserId(userId).orElse(null);
    }

    @Transactional
    public UserProfileResponse initializeProfile(Long userId) {
        // Check if profile already exists
        UserProfile profile = userProfileRepository.findByUserId(userId)
                .orElse(null);
        
        if (profile != null) {
            // Profile exists, just return it
            return mapToResponseWithStats(profile, userId);
        }
        
        // Profile doesn't exist, create a new one with placeholder data
        // This will be updated by user via edit profile
        UserProfile newProfile = new UserProfile();
        newProfile.setUserId(userId);
        newProfile.setUsername("user_" + userId);
        newProfile.setEmail("user_" + userId + "@social.com");
        newProfile.setFullName("User " + userId);
        newProfile.setIsPrivate(false);
        newProfile.setIsVerified(false);
        
        // Explicitly set timestamps if not auto-set by Hibernate
        if (newProfile.getCreatedAt() == null) {
            newProfile.setCreatedAt(java.time.LocalDateTime.now());
        }
        if (newProfile.getUpdatedAt() == null) {
            newProfile.setUpdatedAt(java.time.LocalDateTime.now());
        }
        
        UserProfile savedProfile = userProfileRepository.save(newProfile);
        return mapToResponseWithStats(savedProfile, userId);
    }
    
    @Transactional(readOnly = true)
    public UserProfileResponse getProfileByUsername(String username, Long requestingUserId) {
        UserProfile profile = userProfileRepository.findByUsername(username)
                .orElseThrow(() -> new RuntimeException("Profile not found"));
        
        // ✅ BLOCKING FIX: Check if either user has blocked the other
        if (!profile.getUserId().equals(requestingUserId) && blockService.isEitherBlocked(profile.getUserId(), requestingUserId)) {
            throw new RuntimeException("Cannot access this user's profile");
        }
        
        return mapToResponseWithStats(profile, requestingUserId);
    }
    
    @Transactional
    public UserProfileResponse updateProfile(Long userId, UserProfileRequest request) {
        System.out.println("\n===== UPDATE PROFILE =====");
        System.out.println("userId: " + userId);
        System.out.println("Request username: " + request.getUsername());
        System.out.println("Request fullName: " + request.getFullName());
        
        UserProfile profile = userProfileRepository.findByUserId(userId)
                .orElseThrow(() -> new RuntimeException("Profile not found"));
        
        System.out.println("Current username: " + profile.getUsername());
        System.out.println("Current fullName: " + profile.getFullName());
        
        // Check if username is being changed and if it's already taken
        // ---- IDENTITY (owned by auth-service) ----
        // username/fullName live in auth_db.users. Write them there first, then
        // mirror auth's authoritative answer into our replica. Doing it in this
        // order means a rejected username (409) never half-applies locally.
        boolean usernameChanged = request.getUsername() != null
                && !request.getUsername().equals(profile.getUsername());
        boolean fullNameChanged = request.getFullName() != null
                && !request.getFullName().equals(profile.getFullName());

        if (usernameChanged || fullNameChanged) {
            Map<String, Object> authoritative = authIdentityClient.updateIdentity(
                    userId,
                    usernameChanged ? request.getUsername() : null,
                    fullNameChanged ? request.getFullName() : null);

            Object newUsername = authoritative.get("username");
            Object newFullName = authoritative.get("fullName");
            if (newUsername != null) profile.setUsername(newUsername.toString());
            if (newFullName != null) profile.setFullName(newFullName.toString());
            profile.setSyncedAt(LocalDateTime.now(ZoneId.of("UTC")));
        }

        // ---- SOCIAL PROFILE (owned here) ----
        if (request.getBio() != null) {
            profile.setBio(request.getBio());
        }
        if (request.getProfilePictureUrl() != null) {
            profile.setProfilePictureUrl(request.getProfilePictureUrl());
        }
        if (request.getCoverPhotoUrl() != null) {
            profile.setCoverPhotoUrl(request.getCoverPhotoUrl());
        }
        if (request.getLocation() != null) {
            profile.setLocation(request.getLocation());
        }
        if (request.getWebsite() != null) {
            profile.setWebsite(request.getWebsite());
        }
        if (request.getDateOfBirth() != null) {
            profile.setDateOfBirth(request.getDateOfBirth());
        }
        if (request.getIsPrivate() != null) {
            System.out.println("Setting isPrivate to: " + request.getIsPrivate());
            profile.setIsPrivate(request.getIsPrivate());
        }
        
        UserProfile updatedProfile = userProfileRepository.save(profile);
        System.out.println("\n[PROFILE SAVED TO DATABASE]");
        System.out.println("Saved username: " + updatedProfile.getUsername());
        System.out.println("Saved fullName: " + updatedProfile.getFullName());
        System.out.println("Saved isPrivate: " + updatedProfile.getIsPrivate());
        return mapToResponseWithStats(updatedProfile, userId);
    }
    
    @Transactional(readOnly = true)
    public Page<UserSearchResult> searchUsers(String query, Long requestingUserId, Pageable pageable) {
        if (query == null || query.trim().isEmpty()) {
            throw new IllegalArgumentException("Search query cannot be empty");
        }
        
        List<Long> blockedUserIds = blockService.getBlockedUserIds(requestingUserId);
        List<Long> blockerUserIds = blockService.getBlockerUserIds(requestingUserId);
        
        Page<UserProfile> profiles = userProfileRepository.searchUsers(query.trim(), pageable);

        List<UserProfile> filteredProfiles = profiles.stream()
            .filter(profile -> !blockedUserIds.contains(profile.getUserId()) &&
                               !blockerUserIds.contains(profile.getUserId()))
            .toList();

        List<UserSearchResult> results = filteredProfiles.stream()
            .map(profile -> mapToSearchResult(profile, requestingUserId))
            .toList();

        return new PageImpl<>(results, pageable, filteredProfiles.size());
    }
    
    @Transactional(readOnly = true)
    public Page<UserSearchResult> searchPublicUsers(String query, Long requestingUserId, Pageable pageable) {
        Page<UserProfile> profiles;
        if (query == null || query.trim().isEmpty()) {
            profiles = userProfileRepository.findAll(pageable);
        } else {
            profiles = userProfileRepository.searchUsers(query.trim(), pageable);
        }
        return profiles.map(profile -> mapToSearchResult(profile, requestingUserId));
    }
    
    @Transactional(readOnly = true)
    public Page<UserSearchResult> getSuggestedUsers(Long requestingUserId, Pageable pageable) {
        List<Long> followingIds = followerRepository.findFollowingIdsByUserId(requestingUserId);
        followingIds.add(requestingUserId);
        
        List<Long> blockedUserIds = blockService.getBlockedUserIds(requestingUserId);
        List<Long> blockerUserIds = blockService.getBlockerUserIds(requestingUserId);
        
        Page<UserProfile> profiles = userProfileRepository.findAll(pageable);

        List<UserProfile> filteredProfiles = profiles.stream()
            .filter(profile -> !followingIds.contains(profile.getUserId()) &&
                               !blockedUserIds.contains(profile.getUserId()) &&
                               !blockerUserIds.contains(profile.getUserId()))
            .toList();

        List<UserSearchResult> results = filteredProfiles.stream()
            .map(profile -> mapToSearchResult(profile, requestingUserId))
            .toList();

        return new PageImpl<>(results, pageable, filteredProfiles.size());
    }
    
    @Transactional(readOnly = true)
    public List<UserSearchResult> getUserProfilesByIds(List<Long> userIds, Long requestingUserId) {
        List<UserProfile> profiles = userProfileRepository.findByUserIdIn(userIds);
        return profiles.stream()
            .map(profile -> mapToSearchResult(profile, requestingUserId))
            .toList();
    }
    
    private UserProfileResponse mapToResponse(UserProfile profile, Long requestingUserId) {
        UserProfileResponse response = new UserProfileResponse();
        response.setUserId(profile.getUserId());
        response.setUsername(profile.getUsername());
        response.setFullName(profile.getFullName());
        response.setEmail(profile.getEmail());
        response.setBio(profile.getBio());
        
        // Convert S3 keys to full URLs (only if not already full URLs)
        if (profile.getProfilePictureUrl() != null && !profile.getProfilePictureUrl().isEmpty()) {
            String profilePicUrl = profile.getProfilePictureUrl();
            if (!profilePicUrl.startsWith("http://") && !profilePicUrl.startsWith("https://")) {
                profilePicUrl = String.format("https://%s.s3.%s.amazonaws.com/%s", 
                    bucketName, region, profilePicUrl);
            }
            response.setProfilePictureUrl(profilePicUrl);
        }
        if (profile.getCoverPhotoUrl() != null && !profile.getCoverPhotoUrl().isEmpty()) {
            String coverPhotoUrl = profile.getCoverPhotoUrl();
            if (!coverPhotoUrl.startsWith("http://") && !coverPhotoUrl.startsWith("https://")) {
                coverPhotoUrl = String.format("https://%s.s3.%s.amazonaws.com/%s", 
                    bucketName, region, coverPhotoUrl);
            }
            response.setCoverPhotoUrl(coverPhotoUrl);
        }
        
        response.setLocation(profile.getLocation());
        response.setWebsite(profile.getWebsite());
        response.setDateOfBirth(profile.getDateOfBirth());
        response.setIsPrivate(profile.getIsPrivate());
        response.setIsVerified(profile.getIsVerified());
        response.setCreatedAt(profile.getCreatedAt());
        response.setUpdatedAt(profile.getUpdatedAt());
        
        return response;
    }
    
    private UserProfileResponse mapToResponseWithStats(UserProfile profile, Long requestingUserId) {
        UserProfileResponse response = mapToResponse(profile, requestingUserId);
        
        response.setFollowersCount(followerRepository.countByFollowingId(profile.getUserId()));
        response.setFollowingCount(followerRepository.countByFollowerId(profile.getUserId()));
        response.setPostsCount(postRepository.countByUserId(profile.getUserId()));
        
        if (requestingUserId != null && !requestingUserId.equals(profile.getUserId())) {
            response.setIsFollowing(
                followerRepository.existsByFollowerIdAndFollowingId(requestingUserId, profile.getUserId())
            );
            response.setIsFollowedBy(
                followerRepository.existsByFollowerIdAndFollowingId(profile.getUserId(), requestingUserId)
            );
        } else {
            response.setIsFollowing(false);
            response.setIsFollowedBy(false);
        }
        
        return response;
    }
    
    private UserSearchResult mapToSearchResult(UserProfile profile, Long requestingUserId) {
        UserSearchResult result = new UserSearchResult();
        result.setUserId(profile.getUserId());
        result.setUsername(profile.getUsername());
        result.setFullName(profile.getFullName());
        result.setBio(profile.getBio());
        
        // Construct full S3 URL for profile picture
        String profilePictureUrl = profile.getProfilePictureUrl();
        if (profilePictureUrl != null && !profilePictureUrl.isEmpty()) {
            // Only construct URL if it's not already a full URL
            if (!profilePictureUrl.startsWith("http://") && !profilePictureUrl.startsWith("https://")) {
                profilePictureUrl = String.format("https://%s.s3.%s.amazonaws.com/%s", 
                    bucketName, region, profilePictureUrl);
            }
        }
        result.setProfilePictureUrl(profilePictureUrl);
        
        result.setIsPrivate(profile.getIsPrivate());
        result.setIsVerified(profile.getIsVerified());
        
        result.setFollowersCount(followerRepository.countByFollowingId(profile.getUserId()));
        result.setFollowingCount(followerRepository.countByFollowerId(profile.getUserId()));
        
        if (requestingUserId != null && !requestingUserId.equals(profile.getUserId())) {
            result.setIsFollowing(
                followerRepository.existsByFollowerIdAndFollowingId(requestingUserId, profile.getUserId())
            );
        } else {
            result.setIsFollowing(false);
        }
        
        return result;
    }


    @Transactional(readOnly = true)
    public Boolean isUserOnline(Long userId) {
        UserProfile profile = userProfileRepository.findByUserId(userId).orElse(null);
        return profile != null && profile.getIsOnline();
    }
    
    @Transactional
    public void deleteUserProfile(Long userId) {
        System.out.println("\n===== DELETE USER PROFILE =====");
        System.out.println("Deleting profile for user ID: " + userId);
        
        try {
            UserProfile profile = userProfileRepository.findByUserId(userId)
                .orElseThrow(() -> new RuntimeException("Profile not found for user: " + userId));
            
            // Delete all posts by this user (cascade will handle likes, comments, etc.)
            System.out.println("Deleting posts for user: " + userId);
            postRepository.deleteByUserProfileId(profile.getId());
            
            // Delete all follower relationships (both following and followers)
            System.out.println("Deleting follower relationships for user: " + userId);
            followerRepository.deleteByFollowerIdOrFollowingId(userId, userId);
            
            // Note: Messages, blocked users, follow requests, etc. will be handled by DB cascade
            // or need to be deleted by their respective services if needed
            
            // Finally delete the profile
            System.out.println("Deleting user profile: " + userId);
            userProfileRepository.delete(profile);
            
            System.out.println("Successfully deleted user profile: " + userId);
        } catch (Exception e) {
            System.err.println("Error deleting user profile: " + e.getMessage());
            e.printStackTrace();
            throw new RuntimeException("Failed to delete user profile: " + e.getMessage());
        }
    }
}