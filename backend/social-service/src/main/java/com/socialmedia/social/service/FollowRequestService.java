package com.socialmedia.social.service;

import com.socialmedia.social.dto.FollowRequestResponse;
import com.socialmedia.social.dto.RequesterInfo;
import com.socialmedia.social.entity.FollowRequest;
import com.socialmedia.social.repository.FollowRequestRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageImpl;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class FollowRequestService {

    private final FollowRequestRepository followRequestRepository;
    private final FollowerService followerService;
    private final UserProfileService userProfileService;
    private final NotificationService notificationService;
    private final FCMService fcmService;
    private final BlockService blockService;

    @Transactional
    public void sendFollowRequest(Long requesterId, Long targetId) {
        if (requesterId.equals(targetId)) {
            throw new IllegalArgumentException("Cannot request to follow yourself");
        }
        
        // ✅ BLOCKING FIX: Check if either user has blocked the other
        if (blockService.isEitherBlocked(requesterId, targetId)) {
            throw new IllegalArgumentException("Cannot send follow request to this user");
        }

        if (followerService.isFollowing(requesterId, targetId)) {
            throw new IllegalArgumentException("Already following this user");
        }

        if (followRequestRepository.existsByRequesterIdAndReceiverId(requesterId, targetId)) {
            throw new IllegalArgumentException("Follow request already sent");
        }

        FollowRequest fr = new FollowRequest(requesterId, targetId);
        followRequestRepository.save(fr);

        // Send notification to the target user (owner of private account)
        String body = "sent you a follow request";
        notificationService.createNotification(targetId, "follow_request_received", requesterId, targetId, body);
        
        // Send push notification
        fcmService.onFollowRequestReceived(targetId, requesterId);
    }

    @Transactional(readOnly = true)
    public Page<FollowRequestResponse> getIncomingRequests(Long targetId, Pageable pageable) {
        Page<FollowRequest> page = followRequestRepository.findByReceiverIdOrderByCreatedAtDesc(targetId, pageable);

        List<Long> requesterIds = page.getContent().stream().map(FollowRequest::getRequesterId).collect(Collectors.toList());
        final var profiles = userProfileService.getUserProfilesByIds(requesterIds, targetId);

        List<FollowRequestResponse> responses = page.getContent().stream().map(fr -> {
            FollowRequestResponse r = new FollowRequestResponse();
            r.setId(fr.getId());
            // find the profile info
            var profile = profiles.stream().filter(p -> p.getUserId().equals(fr.getRequesterId())).findFirst().orElse(null);
            RequesterInfo reqInfo = new RequesterInfo();
            reqInfo.setUserId(fr.getRequesterId());
            if (profile != null) {
                reqInfo.setUsername(profile.getUsername());
                reqInfo.setFullName(profile.getFullName());
                reqInfo.setProfilePictureUrl(profile.getProfilePictureUrl());
            }
            r.setRequester(reqInfo);
            r.setCreatedAt(fr.getCreatedAt());
            return r;
        }).collect(Collectors.toList());

        return new PageImpl<>(responses, pageable, page.getTotalElements());
    }

    @Transactional
    public void acceptRequest(Long requestId, Long targetId) {
        FollowRequest fr = followRequestRepository.findById(requestId).orElseThrow(() -> new RuntimeException("Follow request not found"));
        if (!fr.getReceiverId().equals(targetId)) {
            throw new IllegalArgumentException("Not authorized to accept this request");
        }

        Long requesterId = fr.getRequesterId();
        // Use createFollowerRelationship to bypass privacy checks since request was already approved
        followerService.createFollowerRelationship(requesterId, targetId);
        followRequestRepository.delete(fr);

        // Send notification to the requester (who sent the follow request)
        String body = "accepted your follow request";
        notificationService.createNotification(requesterId, "follow_request_accepted", targetId, requesterId, body);
        
        // Send push notification
        fcmService.onUserFollowed(requesterId, targetId);
    }

    @Transactional
    public void declineRequest(Long requestId, Long targetId) {
        FollowRequest fr = followRequestRepository.findById(requestId).orElseThrow(() -> new RuntimeException("Follow request not found"));
        if (!fr.getReceiverId().equals(targetId)) {
            throw new IllegalArgumentException("Not authorized to decline this request");
        }
        followRequestRepository.delete(fr);
    }

    @Transactional(readOnly = true)
    public boolean hasPendingRequest(Long requesterId, Long targetId) {
        boolean exists = followRequestRepository.existsByRequesterIdAndReceiverId(requesterId, targetId);
        System.out.println("[FOLLOW REQUEST CHECK] requesterId: " + requesterId + ", targetId: " + targetId + ", hasPending: " + exists);
        return exists;
    }
}
