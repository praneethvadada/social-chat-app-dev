package com.socialmedia.social.service;

import com.socialmedia.social.dto.StatusDtos.*;
import com.socialmedia.social.entity.Status;
import com.socialmedia.social.entity.StatusAudience;
import com.socialmedia.social.entity.StatusView;
import com.socialmedia.social.entity.UserProfile;
import com.socialmedia.social.repository.BlockedUserRepository;
import com.socialmedia.social.repository.FollowerRepository;
import com.socialmedia.social.repository.StatusRepository;
import com.socialmedia.social.repository.StatusAudienceRepository;
import com.socialmedia.social.repository.StatusViewRepository;
import com.socialmedia.social.repository.UserProfileRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.*;
import java.util.stream.Collectors;

/**
 * 24-hour status (S1).
 *
 * Privacy is enforced HERE, not in the UI (spec §S):
 *  - expiry  : every read filters expiresAt > now
 *  - audience: S1 = people you follow (plus yourself)
 *  - blocking: a block in EITHER direction hides statuses both ways (§9-10),
 *              and takes effect immediately because it is evaluated per request
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class StatusService {

    private final StatusRepository statusRepository;
    private final StatusViewRepository statusViewRepository;
    private final StatusAudienceRepository statusAudienceRepository;
    private final FollowerRepository followerRepository;
    private final BlockedUserRepository blockedUserRepository;
    private final UserProfileRepository userProfileRepository;

    @Value("${aws.s3.bucket-name:social-media-gidut-54513}")
    private String bucketName;

    @Value("${aws.s3.region:us-east-1}")
    private String region;

    private static LocalDateTime nowUtc() {
        return LocalDateTime.now(ZoneId.of("UTC"));
    }

    @Transactional
    public StatusItem create(Long userId, CreateStatusRequest request) {
        boolean hasText = request.getContent() != null && !request.getContent().trim().isEmpty();
        boolean hasMedia = request.getMediaUrl() != null && !request.getMediaUrl().isEmpty();
        if (!hasText && !hasMedia) {
            throw new IllegalArgumentException("Status needs text or media");
        }

        // Cap how many statuses one user can have live at once. Enforced here,
        // not in the UI, so it holds for any client.
        long activeCount = statusRepository.findActiveByUser(userId, nowUtc()).size();
        if (activeCount >= Status.MAX_ACTIVE_PER_USER) {
            throw new IllegalArgumentException(
                    "You can have at most " + Status.MAX_ACTIVE_PER_USER
                    + " active statuses. Delete one or wait for it to expire.");
        }

        Status s = new Status();
        s.setUserId(userId);
        s.setType(request.getType() == null ? Status.Type.TEXT : request.getType());
        s.setContent(request.getContent());
        s.setMediaUrl(request.getMediaUrl());
        s.setThumbnailUrl(request.getThumbnailUrl());
        s.setBackgroundColor(request.getBackgroundColor());
        Status.PrivacyType privacy = request.getPrivacyType() == null
                ? Status.PrivacyType.CONTACTS : request.getPrivacyType();
        s.setPrivacyType(privacy);
        s.setAllowReplies(request.getAllowReplies() == null || request.getAllowReplies());
        s.setAllowReactions(request.getAllowReactions() == null || request.getAllowReactions());

        Status saved = statusRepository.save(s);

        // S4: persist the audience list. ONLY -> allow-list, EXCEPT -> deny-list.
        // CONTACTS keeps no rows at all.
        if (privacy != Status.PrivacyType.CONTACTS
                && request.getAudienceUserIds() != null
                && !request.getAudienceUserIds().isEmpty()) {
            StatusAudience.Permission permission = privacy == Status.PrivacyType.ONLY
                    ? StatusAudience.Permission.ALLOW
                    : StatusAudience.Permission.DENY;
            for (Long audienceUserId : new LinkedHashSet<>(request.getAudienceUserIds())) {
                if (audienceUserId.equals(userId)) continue; // never list yourself
                StatusAudience entry = new StatusAudience();
                entry.setStatusId(saved.getId());
                entry.setUserId(audienceUserId);
                entry.setPermission(permission);
                statusAudienceRepository.save(entry);
            }
            log.info("[Status] status {} privacy={} audience={} users",
                    saved.getId(), privacy, request.getAudienceUserIds().size());
        }
        log.info("[Status] user={} posted {} status {} expiring {}",
                userId, saved.getType(), saved.getId(), saved.getExpiresAt());
        return toItem(saved, true, 0);
    }

    /**
     * Status home feed: my own statuses + those of people I follow, excluding
     * anyone in a block relationship with me (either direction) and anything
     * expired.
     */
    @Transactional(readOnly = true)
    public StatusFeedResponse getFeed(Long viewerId) {
        LocalDateTime now = nowUtc();

        Set<Long> authors = new LinkedHashSet<>(followerRepository.findFollowingIdsByUserId(viewerId));
        authors.removeAll(blockedUserRepository.findBlockedIdsByBlockerId(viewerId));   // I blocked them
        authors.removeAll(blockedUserRepository.findBlockerIdsByBlockedId(viewerId));   // they blocked me
        authors.remove(viewerId);

        StatusFeedResponse response = new StatusFeedResponse();

        // --- my own statuses (always visible to me) ---
        List<Status> mine = statusRepository.findActiveByUser(viewerId, now);
        if (!mine.isEmpty()) {
            UserStatusGroup myGroup = buildGroup(viewerId, mine, viewerId);
            myGroup.setAllSeen(true); // own statuses never render as "unseen"
            response.setMyStatus(myGroup);
        }

        // --- others ---
        List<UserStatusGroup> groups = new ArrayList<>();
        if (!authors.isEmpty()) {
            List<Status> all = statusRepository.findActiveByAuthors(new ArrayList<>(authors), now);

            // S4: apply per-status audience. Load every audience row for these
            // statuses in ONE query, then filter in memory.
            List<Long> statusIds = all.stream().map(Status::getId).collect(Collectors.toList());
            Map<Long, List<StatusAudience>> audienceByStatus = statusIds.isEmpty()
                    ? Map.of()
                    : statusAudienceRepository.findByStatusIdIn(statusIds).stream()
                            .collect(Collectors.groupingBy(StatusAudience::getStatusId));
            all = all.stream()
                    .filter(s -> audienceAllows(s, viewerId, audienceByStatus))
                    .collect(Collectors.toList());

            Map<Long, List<Status>> byAuthor = all.stream()
                    .collect(Collectors.groupingBy(Status::getUserId, LinkedHashMap::new, Collectors.toList()));
            for (Map.Entry<Long, List<Status>> e : byAuthor.entrySet()) {
                groups.add(buildGroup(e.getKey(), e.getValue(), viewerId));
            }
        }

        // Unseen rings first, then most recent activity.
        groups.sort(Comparator
                .comparing(UserStatusGroup::isAllSeen)
                .thenComparing(UserStatusGroup::getLatestAt, Comparator.reverseOrder()));
        response.setRecent(groups);
        return response;
    }

    /** Record that the viewer saw this status. Idempotent; owner views aren't counted. */
    @Transactional
    public void markViewed(Long statusId, Long viewerId) {
        Status status = statusRepository.findById(statusId)
                .orElseThrow(() -> new IllegalArgumentException("Status not found"));

        if (!canView(status, viewerId)) {
            throw new SecurityException("Status unavailable");
        }
        if (status.getUserId().equals(viewerId)) {
            return; // don't count the owner as a viewer
        }
        if (statusViewRepository.existsByStatusIdAndViewerId(statusId, viewerId)) {
            return;
        }
        StatusView v = new StatusView();
        v.setStatusId(statusId);
        v.setViewerId(viewerId);
        statusViewRepository.save(v);
    }

    /**
     * S3: set or clear this viewer's reaction to a status.
     *
     * The reaction lives on the view row, so reacting also counts as viewing.
     * Passing null/blank clears it. The owner cannot react to their own status
     * (they are never a "viewer"), and the same visibility rules as viewing
     * apply - expired/blocked statuses are unreactable.
     */
    @Transactional
    public void react(Long statusId, Long viewerId, String reaction) {
        Status status = statusRepository.findById(statusId)
                .orElseThrow(() -> new IllegalArgumentException("Status not found"));

        if (!canView(status, viewerId)) {
            throw new SecurityException("Status unavailable");
        }
        if (status.getUserId().equals(viewerId)) {
            throw new SecurityException("Cannot react to your own status");
        }
        if (!Boolean.TRUE.equals(status.getAllowReactions())) {
            throw new SecurityException("Reactions are turned off for this status");
        }

        String emoji = (reaction == null || reaction.trim().isEmpty())
                ? null : reaction.trim();

        StatusView view = statusViewRepository
                .findByStatusIdAndViewerId(statusId, viewerId)
                .orElseGet(() -> {
                    StatusView v = new StatusView();
                    v.setStatusId(statusId);
                    v.setViewerId(viewerId);
                    return v;
                });
        view.setReaction(emoji);
        statusViewRepository.save(view);
        log.info("[Status] user={} reacted '{}' to status {}", viewerId, emoji, statusId);
    }

    /** Viewers of my own status. Only the owner may read this. */
    @Transactional(readOnly = true)
    public List<StatusViewerInfo> getViewers(Long statusId, Long requesterId) {
        Status status = statusRepository.findById(statusId)
                .orElseThrow(() -> new IllegalArgumentException("Status not found"));
        if (!status.getUserId().equals(requesterId)) {
            throw new SecurityException("Not your status");
        }
        return statusViewRepository.findByStatusIdOrderByViewedAtDesc(statusId).stream()
                .map(v -> {
                    StatusViewerInfo info = new StatusViewerInfo();
                    info.setUserId(v.getViewerId());
                    info.setViewedAt(v.getViewedAt());
                    info.setReaction(v.getReaction());
                    userProfileRepository.findByUserId(v.getViewerId()).ifPresent(p -> {
                        info.setUsername(p.getUsername());
                        info.setFullName(p.getFullName());
                        info.setProfilePictureUrl(fullUrl(p.getProfilePictureUrl()));
                    });
                    return info;
                })
                .collect(Collectors.toList());
    }

    /**
     * S4 (§R): the owner's expired statuses.
     *
     * Strictly owner-scoped - archiving must never make a status public again,
     * so there is deliberately no way to read anyone else's archive.
     */
    @Transactional(readOnly = true)
    public List<StatusItem> getArchive(Long userId) {
        return statusRepository.findExpiredByUser(userId, nowUtc()).stream()
                .map(s -> toItem(s, true, statusViewRepository.countByStatusId(s.getId())))
                .collect(Collectors.toList());
    }

    /** Soft-delete own status; it disappears for everyone immediately (§P). */
    @Transactional
    public void delete(Long statusId, Long requesterId) {
        Status status = statusRepository.findById(statusId)
                .orElseThrow(() -> new IllegalArgumentException("Status not found"));
        if (!status.getUserId().equals(requesterId)) {
            throw new SecurityException("Not your status");
        }
        status.setIsDeleted(true);
        statusRepository.save(status);
    }

    /**
     * Authorization for a single status (used by markViewed and any direct fetch).
     * Mirrors the feed rules so there is no way to read a status by guessing an id.
     */
    private boolean canView(Status status, Long viewerId) {
        if (Boolean.TRUE.equals(status.getIsDeleted())) return false;
        if (status.getExpiresAt().isBefore(nowUtc())) return false;
        if (status.getUserId().equals(viewerId)) return true;
        // A block always wins - being on an ONLY list never beats it (§9).
        if (blockedUserRepository.isEitherBlocked(status.getUserId(), viewerId)) return false;
        // Base rule: viewer must follow the author.
        if (!followerRepository.findFollowingIdsByUserId(viewerId).contains(status.getUserId())) {
            return false;
        }
        // S4: then narrow by the per-status audience.
        return audienceAllows(status, viewerId);
    }

    /**
     * S4 audience check for a single status. CONTACTS lets every contact
     * through; ONLY requires an explicit allow row; EXCEPT rejects deny rows.
     */
    private boolean audienceAllows(Status status, Long viewerId) {
        return switch (status.getPrivacyType()) {
            case ONLY -> statusAudienceRepository.isAllowed(status.getId(), viewerId);
            case EXCEPT -> !statusAudienceRepository.isDenied(status.getId(), viewerId);
            case CONTACTS -> true;
        };
    }

    /**
     * Fetch a single status the caller is allowed to see, wrapped in its
     * author group so the viewer screen has the author's name/avatar too.
     *
     * Used when tapping the status reference on a chat bubble. Distinguishes
     * "gone" from "not yours to see": an expired or deleted status is a 404 so
     * the client can say so plainly, while a live status you have no right to
     * is a 403.
     */
    @Transactional(readOnly = true)
    public UserStatusGroup getOne(Long statusId, Long viewerId) {
        Status status = statusRepository.findById(statusId)
                .orElseThrow(() -> new StatusGoneException("This status is no longer available"));

        if (Boolean.TRUE.equals(status.getIsDeleted())
                || status.getExpiresAt().isBefore(nowUtc())) {
            throw new StatusGoneException("This status is no longer available");
        }
        if (!canView(status, viewerId)) {
            throw new SecurityException("Status unavailable");
        }
        return buildGroup(status.getUserId(), List.of(status), viewerId);
    }

    /** Thrown when a status exists no more (expired/deleted) - maps to 404. */
    public static class StatusGoneException extends RuntimeException {
        public StatusGoneException(String message) { super(message); }
    }

    /** Batch variant used by the feed so filtering isn't one query per status. */
    private boolean audienceAllows(Status status, Long viewerId,
                                   Map<Long, List<StatusAudience>> byStatus) {
        if (status.getPrivacyType() == Status.PrivacyType.CONTACTS) return true;
        List<StatusAudience> rows = byStatus.getOrDefault(status.getId(), List.of());
        boolean listed = rows.stream().anyMatch(a -> a.getUserId().equals(viewerId));
        return status.getPrivacyType() == Status.PrivacyType.ONLY ? listed : !listed;
    }

    private UserStatusGroup buildGroup(Long authorId, List<Status> statuses, Long viewerId) {
        UserStatusGroup group = new UserStatusGroup();
        group.setUserId(authorId);
        userProfileRepository.findByUserId(authorId).ifPresent(p -> {
            group.setUsername(p.getUsername());
            group.setFullName(p.getFullName());
            group.setProfilePictureUrl(fullUrl(p.getProfilePictureUrl()));
        });

        List<Long> ids = statuses.stream().map(Status::getId).collect(Collectors.toList());
        Set<Long> seen = new HashSet<>(statusViewRepository.findSeenStatusIds(viewerId, ids));

        boolean isOwner = authorId.equals(viewerId);
        List<StatusItem> items = statuses.stream()
                .map(s -> {
                    StatusItem item = toItem(s, seen.contains(s.getId()),
                            isOwner ? statusViewRepository.countByStatusId(s.getId()) : 0);
                    if (isOwner) {
                        // Owner sees the aggregate; viewers see only their own.
                        Map<String, Long> counts = new LinkedHashMap<>();
                        for (Object[] row : statusViewRepository.countReactionsByStatus(s.getId())) {
                            counts.put((String) row[0], (Long) row[1]);
                        }
                        item.setReactionCounts(counts);
                    } else {
                        statusViewRepository.findByStatusIdAndViewerId(s.getId(), viewerId)
                                .ifPresent(v -> item.setMyReaction(v.getReaction()));
                    }
                    return item;
                })
                .collect(Collectors.toList());

        group.setStatuses(items);
        group.setAllSeen(items.stream().allMatch(StatusItem::isSeen));
        group.setLatestAt(statuses.get(statuses.size() - 1).getCreatedAt());
        return group;
    }

    private StatusItem toItem(Status s, boolean seen, long viewCount) {
        StatusItem item = new StatusItem();
        item.setId(s.getId());
        item.setType(s.getType().name());
        item.setContent(s.getContent());
        item.setMediaUrl(fullUrl(s.getMediaUrl()));
        item.setThumbnailUrl(fullUrl(s.getThumbnailUrl()));
        item.setBackgroundColor(s.getBackgroundColor());
        item.setCreatedAt(s.getCreatedAt());
        item.setExpiresAt(s.getExpiresAt());
        item.setSeen(seen);
        item.setViewCount(viewCount);
        item.setAllowReplies(Boolean.TRUE.equals(s.getAllowReplies()));
        item.setAllowReactions(Boolean.TRUE.equals(s.getAllowReactions()));
        item.setPrivacyType(s.getPrivacyType() != null ? s.getPrivacyType().name() : "CONTACTS");
        return item;
    }

    /** Build a full S3 URL from a stored key (no-op when already absolute/empty). */
    private String fullUrl(String keyOrUrl) {
        if (keyOrUrl == null || keyOrUrl.isEmpty()) return keyOrUrl;
        if (keyOrUrl.startsWith("http://") || keyOrUrl.startsWith("https://")) return keyOrUrl;
        return String.format("https://%s.s3.%s.amazonaws.com/%s", bucketName, region, keyOrUrl);
    }
}
