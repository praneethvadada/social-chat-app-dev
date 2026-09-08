package com.socialmedia.social.service;

import com.socialmedia.social.dto.HashtagResponse;
import com.socialmedia.social.dto.PollOptionResponse;
import com.socialmedia.social.dto.PostRequest;
import com.socialmedia.social.dto.PostResponse;
import com.socialmedia.social.dto.VoterSummary;
import com.socialmedia.social.entity.EventRsvp;
import com.socialmedia.social.entity.PollOption;
import com.socialmedia.social.entity.PollVote;
import com.socialmedia.social.entity.Post;
import com.socialmedia.social.entity.Post.PostType;
import com.socialmedia.social.entity.Post.PostVisibility;
import com.socialmedia.social.repository.*;
import com.socialmedia.social.entity.UserProfile;
import lombok.RequiredArgsConstructor;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class PostService {

    private final PostRepository postRepository;
    private final LikeRepository likeRepository;
    private final SaveRepository saveRepository;
    private final CommentRepository commentRepository;
    private final ShareRepository shareRepository;
    private final FollowerService followerService;
    private final BlockService blockService;
    private final UserProfileRepository userProfileRepository;
    private final CloseFriendService closeFriendService;
    private final PollOptionRepository pollOptionRepository;
    private final PollVoteRepository pollVoteRepository;
    private final EventRsvpRepository eventRsvpRepository;

    @Value("${aws.s3.bucket-name:social-media-gidut-54513}")
    private String bucketName;

    @Value("${aws.s3.region:us-east-1}")
    private String region;

    @Transactional
    public PostResponse createPost(PostRequest request, Long userId) {
        System.out.println("[CREATE POST DEBUG] Received request - visibility: " + request.getVisibility() + ", isPublic: " + request.getIsPublic());
        
        Post post = new Post();
        post.setUserId(userId);
        // Handle null or empty content
        String content = request.getContent();
        post.setContent(content != null ? content.trim() : "");
        post.setImageUrls(request.getImageUrls() != null ? request.getImageUrls() : new ArrayList<>());

        // Handle visibility (new Close Friends feature)
        PostVisibility visibility = request.getVisibility() != null
            ? request.getVisibility()
            : PostVisibility.PUBLIC;
        post.setVisibility(visibility); // ✅ FIXED: This now automatically sets isPublic

        PostType postType = request.getPostType() != null ? request.getPostType() : PostType.TEXT;
        post.setPostType(postType);
        if (postType == PostType.EVENT) {
            post.setEventStartTime(request.getEventStartTime());
            post.setEventLocation(request.getEventLocation());
        }

        System.out.println("[CREATE POST DEBUG] Saving post with visibility: " + post.getVisibility() + ", isPublic: " + post.getIsPublic());

        Post savedPost = postRepository.saveAndFlush(post);

        if (postType == PostType.POLL && request.getPollOptions() != null) {
            List<String> rawOptions = request.getPollOptions();
            Integer correctIndex = request.getCorrectOptionIndex();
            int order = 0;
            for (int i = 0; i < rawOptions.size(); i++) {
                String optionText = rawOptions.get(i);
                if (optionText == null || optionText.trim().isEmpty()) continue;
                PollOption option = new PollOption();
                option.setPostId(savedPost.getId());
                option.setOptionText(optionText.trim());
                option.setDisplayOrder(order++);
                option.setIsCorrect(correctIndex != null && correctIndex == i);
                pollOptionRepository.save(option);
            }
        }

        System.out.println("[CREATE POST DEBUG] Saved post - ID: " + savedPost.getId() + ", visibility: " + savedPost.getVisibility() + ", isPublic: " + savedPost.getIsPublic());

        return mapToResponse(savedPost, userId);
    }

    @Transactional
    public PostResponse votePoll(Long postId, Long optionId, Long userId) {
        Post post = postRepository.findById(postId)
                .orElseThrow(() -> new RuntimeException("Post not found"));
        if (post.getPostType() != PostType.POLL) {
            throw new RuntimeException("This post is not a poll");
        }
        PollOption option = pollOptionRepository.findById(optionId)
                .orElseThrow(() -> new RuntimeException("Poll option not found"));
        if (!option.getPostId().equals(postId)) {
            throw new RuntimeException("Option does not belong to this poll");
        }

        PollVote existing = pollVoteRepository.findByPostIdAndUserId(postId, userId).orElse(null);
        if (existing != null) {
            existing.setOptionId(optionId);
            pollVoteRepository.save(existing);
        } else {
            PollVote vote = new PollVote();
            vote.setPostId(postId);
            vote.setOptionId(optionId);
            vote.setUserId(userId);
            pollVoteRepository.save(vote);
        }
        return mapToResponse(post, userId);
    }

    /**
     * Who voted for what, grouped by option id. Anyone who can already see
     * the poll post can see this — same rule as the feed's own visibility
     * filter (owner, or PUBLIC, or a close friend if CLOSE_FRIENDS), plus
     * the block check every other single-post read already applies. Poll
     * votes were always tracked per-user (needed to prevent double-voting
     * and to compute "myPollVoteOptionId") — this just exposes what was
     * already being stored, so aggregate percentages aren't the only thing
     * visible.
     */
    @Transactional(readOnly = true)
    public java.util.Map<Long, List<VoterSummary>> getPollVoters(Long postId, Long userId) {
        Post post = postRepository.findById(postId)
                .orElseThrow(() -> new RuntimeException("Post not found"));
        if (post.getPostType() != PostType.POLL) {
            throw new RuntimeException("This post is not a poll");
        }
        if (blockService.isEitherBlocked(userId, post.getUserId()) || !isPostVisibleToUser(post, userId)) {
            throw new RuntimeException("Cannot view this post");
        }
        return groupVotersByKey(pollVoteRepository.findByPostId(postId), PollVote::getOptionId);
    }

    /** Same idea as {@link #getPollVoters}, grouped by RSVP status instead. */
    @Transactional(readOnly = true)
    public java.util.Map<String, List<VoterSummary>> getEventRsvps(Long postId, Long userId) {
        Post post = postRepository.findById(postId)
                .orElseThrow(() -> new RuntimeException("Post not found"));
        if (post.getPostType() != PostType.EVENT) {
            throw new RuntimeException("This post is not an event");
        }
        if (blockService.isEitherBlocked(userId, post.getUserId()) || !isPostVisibleToUser(post, userId)) {
            throw new RuntimeException("Cannot view this post");
        }
        return groupVotersByKey(eventRsvpRepository.findByPostId(postId), rsvp -> rsvp.getStatus().name());
    }

    private <T, K> java.util.Map<K, List<VoterSummary>> groupVotersByKey(
            List<T> rows, java.util.function.Function<T, K> keyOf) {
        java.util.Map<K, List<Long>> userIdsByKey = new java.util.LinkedHashMap<>();
        for (T row : rows) {
            Long rowUserId = row instanceof PollVote ? ((PollVote) row).getUserId() : ((EventRsvp) row).getUserId();
            userIdsByKey.computeIfAbsent(keyOf.apply(row), k -> new ArrayList<>()).add(rowUserId);
        }
        List<Long> allUserIds = userIdsByKey.values().stream().flatMap(List::stream).distinct().collect(Collectors.toList());
        java.util.Map<Long, UserProfile> profilesById = allUserIds.isEmpty()
                ? java.util.Collections.emptyMap()
                : userProfileRepository.findByUserIdIn(allUserIds).stream()
                        .collect(Collectors.toMap(UserProfile::getUserId, p -> p));
        java.util.Map<K, List<VoterSummary>> result = new java.util.LinkedHashMap<>();
        for (var entry : userIdsByKey.entrySet()) {
            List<VoterSummary> voters = entry.getValue().stream()
                    .map(profilesById::get)
                    .filter(java.util.Objects::nonNull)
                    .map(p -> new VoterSummary(p.getUserId(), p.getUsername(), p.getFullName(), p.getProfilePictureUrl()))
                    .collect(Collectors.toList());
            result.put(entry.getKey(), voters);
        }
        return result;
    }

    @Transactional
    public PostResponse rsvpEvent(Long postId, String status, Long userId) {
        Post post = postRepository.findById(postId)
                .orElseThrow(() -> new RuntimeException("Post not found"));
        if (post.getPostType() != PostType.EVENT) {
            throw new RuntimeException("This post is not an event");
        }
        EventRsvp.RsvpStatus rsvpStatus;
        try {
            rsvpStatus = EventRsvp.RsvpStatus.valueOf(status.toUpperCase());
        } catch (Exception e) {
            throw new RuntimeException("Invalid RSVP status: " + status);
        }

        EventRsvp existing = eventRsvpRepository.findByPostIdAndUserId(postId, userId).orElse(null);
        if (existing != null) {
            existing.setStatus(rsvpStatus);
            eventRsvpRepository.save(existing);
        } else {
            EventRsvp rsvp = new EventRsvp();
            rsvp.setPostId(postId);
            rsvp.setUserId(userId);
            rsvp.setStatus(rsvpStatus);
            eventRsvpRepository.save(rsvp);
        }
        return mapToResponse(post, userId);
    }

    @Transactional
    public PostResponse updatePost(Long postId, PostRequest request, Long userId) {
        Post post = postRepository.findById(postId)
                .orElseThrow(() -> new RuntimeException("Post not found"));
        
        if (!post.getUserId().equals(userId)) {
            throw new RuntimeException("Unauthorized to update this post");
        }
        
        String content = request.getContent();
        post.setContent(content != null ? content.trim() : "");
        post.setImageUrls(request.getImageUrls() != null ? request.getImageUrls() : new ArrayList<>());
        
        // Update visibility if provided
        if (request.getVisibility() != null) {
            post.setVisibility(request.getVisibility()); // ✅ FIXED: This now automatically sets isPublic
        }
        
        Post updatedPost = postRepository.save(post);
        return mapToResponse(updatedPost, userId);
    }

    @Transactional
    public void deletePost(Long postId, Long userId) {
        Post post = postRepository.findById(postId)
                .orElseThrow(() -> new RuntimeException("Post not found"));
        
        if (!post.getUserId().equals(userId)) {
            throw new RuntimeException("Unauthorized to delete this post");
        }
        
        commentRepository.deleteByPostId(postId);
        likeRepository.deleteByTargetTypeAndTargetId(com.socialmedia.social.entity.Like.LikeTargetType.POST, postId);
        saveRepository.deleteByPostId(postId);
        shareRepository.deleteByPostId(postId);
        
        postRepository.delete(post);
    }

    @Transactional(readOnly = true)
    public PostResponse getPost(Long postId, Long userId) {
        Post post = postRepository.findById(postId)
                .orElseThrow(() -> new RuntimeException("Post not found"));
        
        // ✅ BLOCKING FIX: Check if either user has blocked the other
        if (!post.getUserId().equals(userId) && blockService.isEitherBlocked(userId, post.getUserId())) {
            throw new RuntimeException("Cannot view this post");
        }
        
        return mapToResponse(post, userId);
    }

    @Transactional(readOnly = true)
    public Page<PostResponse> getUserPosts(Long targetUserId, Long currentUserId, Pageable pageable) {
        // Fetch target user's profile to check privacy
        UserProfile targetProfile = userProfileRepository.findByUserId(targetUserId).orElse(null);
        boolean isPrivate = false;
        if (targetProfile != null && targetProfile.getIsPrivate() != null) {
            isPrivate = targetProfile.getIsPrivate();
        }

        // If private, only allow if current user is a follower or self
        if (isPrivate && !targetUserId.equals(currentUserId)) {
            boolean isFollowing = followerService.isFollowing(currentUserId, targetUserId);
            if (!isFollowing) {
                // Not allowed to view posts
                return Page.empty(pageable);
            }
        }

        Page<Post> posts = postRepository.findByUserIdOrderByCreatedAtDesc(targetUserId, pageable);
        
        // ✅ FIXED: Use unified visibility rule - check per post
        List<Post> visiblePosts = posts.getContent().stream()
            .filter(post -> isPostVisibleToUser(post, currentUserId))
            .collect(Collectors.toList());
        
        return new PageImpl<>(
            visiblePosts.stream().map(p -> mapToResponse(p, currentUserId)).collect(Collectors.toList()),
            pageable,
            visiblePosts.size()
        );
    }

    @Transactional(readOnly = true)
    public Page<PostResponse> getPublicPosts(Long userId, Pageable pageable) {
        Page<Post> posts = postRepository.findPublicPosts(pageable);

        return new PageImpl<>(
            posts.getContent().stream().map(p -> mapToResponse(p, userId)).collect(Collectors.toList()),
            pageable,
            posts.getTotalElements()
        );
    }

    @Transactional(readOnly = true)
    public Page<PostResponse> getFeed(Long userId, Pageable pageable) {
        System.out.println("[FEED DEBUG] Getting feed for user: " + userId);
        
        // ✅ FIXED: Build list of users whose CLOSE_FRIENDS posts should be visible
        // This includes: 1) the viewer themselves, 2) users who have viewer as close friend
        List<Long> eligibleUserIdsForCloseFriends = new ArrayList<>();
        eligibleUserIdsForCloseFriends.add(userId); // Always include self
        
        // Users who have added the current viewer to their Close Friends list
        List<Long> closeFriendOfIds = closeFriendService.getUsersWhoHaveAsCloseFriend(userId);
        eligibleUserIdsForCloseFriends.addAll(closeFriendOfIds);
        
        // Get IDs of people the user follows (for PUBLIC post filtering)
        List<Long> followingIds = followerService.getFollowingIds(userId);
        // ✅ FIXED: Include self in following list to show own PUBLIC posts
        List<Long> publicPostEligibleUserIds = new ArrayList<>(followingIds);
        publicPostEligibleUserIds.add(userId);
        
        System.out.println("[FEED DEBUG] Users who have viewer as close friend: " + closeFriendOfIds);
        System.out.println("[FEED DEBUG] Following IDs: " + followingIds);
        System.out.println("[FEED DEBUG] Public post eligible users: " + publicPostEligibleUserIds);
        
        // Get blocked users to exclude from feed
        List<Long> blockedUserIds = blockService.getBlockedUserIds(userId);
        List<Long> blockerUserIds = blockService.getBlockerUserIds(userId);
        List<Long> excludedUserIds = new ArrayList<>();
        excludedUserIds.addAll(blockedUserIds);
        excludedUserIds.addAll(blockerUserIds);
        System.out.println("[FEED DEBUG] Excluded users (blocked): " + excludedUserIds);
        
        // Filter both eligible lists to exclude blocked users
        eligibleUserIdsForCloseFriends = eligibleUserIdsForCloseFriends.stream()
            .filter(id -> !excludedUserIds.contains(id))
            .collect(Collectors.toList());
        publicPostEligibleUserIds = publicPostEligibleUserIds.stream()
            .filter(id -> !excludedUserIds.contains(id))
            .collect(Collectors.toList());
        System.out.println("[FEED DEBUG] Final eligible users for CLOSE_FRIENDS: " + eligibleUserIdsForCloseFriends);
        System.out.println("[FEED DEBUG] Final eligible users for PUBLIC posts: " + publicPostEligibleUserIds);
        
        // ✅ FIXED: Fetch home feed posts
        // Query returns: PUBLIC posts from FOLLOWED users + CLOSE_FRIENDS posts from eligible users
        Page<Post> posts = postRepository.findHomeFeedPosts(
            publicPostEligibleUserIds,
            eligibleUserIdsForCloseFriends, 
            PostVisibility.PUBLIC, 
            PostVisibility.CLOSE_FRIENDS, 
            pageable
        );
        System.out.println("[FEED DEBUG] Found " + posts.getContent().size() + " posts from database");
        
        // Filter out posts from blocked users and apply visibility rules
        List<Post> visiblePosts = posts.getContent().stream()
            .filter(post -> {
                boolean isBlocked = excludedUserIds.contains(post.getUserId());
                boolean isVisible = isPostVisibleToUser(post, userId);
                if (!isVisible) {
                    System.out.println("[FEED DEBUG] Filtering out post ID: " + post.getId() + " by author " + post.getUserId() + 
                                       " - visibility: " + post.getVisibility() + ", isPublic: " + post.getIsPublic());
                }
                return !isBlocked && isVisible;
            })
            .collect(Collectors.toList());
        System.out.println("[FEED DEBUG] After filtering: " + visiblePosts.size() + " posts remain out of " + posts.getContent().size());
        
        return new PageImpl<>(
            visiblePosts.stream().map(p -> mapToResponse(p, userId)).collect(Collectors.toList()),
            pageable,
            posts.getTotalElements()
        );
    }

    private static final Pattern HASHTAG_PATTERN = Pattern.compile("#(\\w+)");

    @Transactional(readOnly = true)
    public List<HashtagResponse> getTrendingHashtags(int limit) {
        // No dedicated hashtag table — trending is computed live from a
        // recent window of public post content, so it stays correct as
        // posts are created/edited/deleted with zero extra writes.
        Page<Post> recent = postRepository.findPublicPosts(PageRequest.of(0, 300));
        Map<String, Long> counts = new HashMap<>();
        for (Post post : recent.getContent()) {
            String content = post.getContent();
            if (content == null || content.isEmpty()) continue;
            Matcher matcher = HASHTAG_PATTERN.matcher(content);
            Set<String> seenInPost = new HashSet<>(); // count each tag once per post
            while (matcher.find()) {
                String tag = matcher.group(1).toLowerCase();
                if (seenInPost.add(tag)) {
                    counts.merge(tag, 1L, Long::sum);
                }
            }
        }
        return counts.entrySet().stream()
            .sorted((a, b) -> Long.compare(b.getValue(), a.getValue()))
            .limit(limit)
            .map(e -> new HashtagResponse(e.getKey(), e.getValue()))
            .collect(Collectors.toList());
    }

    @Transactional(readOnly = true)
    public Page<PostResponse> getPostsByHashtag(String tag, Long userId, Pageable pageable) {
        String normalized = tag.toLowerCase().replaceFirst("^#", "");
        Page<Post> candidates = postRepository.findByHashtagLike(normalized, pageable);
        // The SQL LIKE only narrows candidates; confirm it's a real
        // hashtag token (word-bounded), not just a substring match.
        Pattern exact = Pattern.compile("#" + Pattern.quote(normalized) + "(?!\\w)", Pattern.CASE_INSENSITIVE);
        List<Post> matched = candidates.getContent().stream()
            .filter(p -> p.getContent() != null && exact.matcher(p.getContent()).find())
            .collect(Collectors.toList());
        return new PageImpl<>(
            matched.stream().map(p -> mapToResponse(p, userId)).collect(Collectors.toList()),
            pageable,
            matched.size()
        );
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
        response.setVisibility(post.getVisibility());
        response.setLikesCount(post.getLikesCount());
        response.setCommentsCount(post.getCommentsCount());
        response.setSharesCount(post.getSharesCount());
        response.setSavesCount(post.getSavesCount());
        response.setCreatedAt(post.getCreatedAt());
        response.setUpdatedAt(post.getUpdatedAt());

        userProfileRepository.findByUserId(post.getUserId()).ifPresent(profile -> {
            String name = profile.getFullName() != null && !profile.getFullName().isBlank()
                    ? profile.getFullName()
                    : profile.getUsername();
            response.setAuthorName(name);
            
            // Construct full S3 URL for profile picture
            String profilePictureUrl = profile.getProfilePictureUrl();
            System.out.println("[PROFILE PIC DEBUG] Original URL from DB: " + profilePictureUrl);
            System.out.println("[PROFILE PIC DEBUG] Bucket: " + bucketName + ", Region: " + region);
            if (profilePictureUrl != null && !profilePictureUrl.isEmpty()) {
                // Only construct URL if it's not already a full URL
                if (!profilePictureUrl.startsWith("http://") && !profilePictureUrl.startsWith("https://")) {
                    profilePictureUrl = String.format("https://%s.s3.%s.amazonaws.com/%s", 
                        bucketName, region, profilePictureUrl);
                    System.out.println("[PROFILE PIC DEBUG] Constructed URL: " + profilePictureUrl);
                } else {
                    System.out.println("[PROFILE PIC DEBUG] URL already complete: " + profilePictureUrl);
                }
            }
            response.setAuthorProfilePictureUrl(profilePictureUrl);
        });

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

        // --- Add sampleLikers logic ---
        // Get up to 10 most recent likers
        List<Long> likerIds = likeRepository.findRecentLikerUserIdsByPostIdAndTargetType(
            post.getId(), com.socialmedia.social.entity.Like.LikeTargetType.POST);
        List<Long> sampleIds = new ArrayList<>();
        if (userId != null && !likerIds.isEmpty()) {
            // Try to prioritize followings
            List<Long> followingIds = followerService.getFollowingIds(userId);
            // Add followings who liked first
            for (Long id : likerIds) {
                if (followingIds.contains(id) && !sampleIds.contains(id)) {
                    sampleIds.add(id);
                    if (sampleIds.size() >= 3) break;
                }
            }
            // If less than 3, fill with others
            if (sampleIds.size() < 3) {
                for (Long id : likerIds) {
                    if (!sampleIds.contains(id)) {
                        sampleIds.add(id);
                        if (sampleIds.size() >= 3) break;
                    }
                }
            }
        } else {
            // No user context, just take up to 3 likers
            for (Long id : likerIds) {
                sampleIds.add(id);
                if (sampleIds.size() >= 3) break;
            }
        }
        List<UserProfile> sampleLikers = sampleIds.isEmpty() ? new ArrayList<>() : userProfileRepository.findByUserIdIn(sampleIds);
        response.setSampleLikers(sampleLikers);
        // --- End sampleLikers logic ---

        response.setPostType(post.getPostType());

        if (post.getPostType() == PostType.POLL) {
            Long myVoteOptionId = userId == null ? null
                : pollVoteRepository.findByPostIdAndUserId(post.getId(), userId)
                    .map(PollVote::getOptionId).orElse(null);
            boolean hasVoted = myVoteOptionId != null;

            List<PollOption> options = pollOptionRepository.findByPostIdOrderByDisplayOrderAsc(post.getId());
            List<PollOptionResponse> optionResponses = options.stream()
                .map(o -> new PollOptionResponse(
                    o.getId(),
                    o.getOptionText(),
                    pollVoteRepository.countByPostIdAndOptionId(post.getId(), o.getId()),
                    hasVoted && Boolean.TRUE.equals(o.getIsCorrect())))
                .collect(Collectors.toList());
            response.setPollOptions(optionResponses);
            response.setMyPollVoteOptionId(myVoteOptionId);
        } else if (post.getPostType() == PostType.EVENT) {
            response.setEventStartTime(post.getEventStartTime());
            response.setEventLocation(post.getEventLocation());
            Map<String, Long> counts = new HashMap<>();
            for (com.socialmedia.social.entity.EventRsvp.RsvpStatus s : com.socialmedia.social.entity.EventRsvp.RsvpStatus.values()) {
                counts.put(s.name(), eventRsvpRepository.countByPostIdAndStatus(post.getId(), s));
            }
            response.setEventRsvpCounts(counts);
            if (userId != null) {
                eventRsvpRepository.findByPostIdAndUserId(post.getId(), userId)
                    .ifPresent(r -> response.setMyRsvpStatus(r.getStatus().name()));
            }
        }

        return response;
    }

    // ✅ UNIFIED VISIBILITY RULE: Single method for all post visibility checks
    private boolean isPostVisibleToUser(Post post, Long userId) {
        // Always show user's own posts regardless of visibility
        if (post.getUserId().equals(userId)) {
            return true;
        }
        
        // For posts from others, check visibility rules
        if (post.getVisibility() == PostVisibility.PUBLIC) {
            return true;
        }
        
        if (post.getVisibility() == PostVisibility.CLOSE_FRIENDS) {
            // Show if current user is in the post owner's close friends list
            return closeFriendService.isCloseFriend(post.getUserId(), userId);
        }
        
        return false;
    }
}
