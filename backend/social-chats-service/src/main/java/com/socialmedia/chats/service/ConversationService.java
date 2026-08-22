package com.socialmedia.chats.service;

import com.socialmedia.chats.client.BlockClient;
import com.socialmedia.chats.client.UserLookupClient;
import com.socialmedia.chats.dto.CreateGroupRequest;
import com.socialmedia.chats.dto.GroupDtos.AddMembersResult;
import com.socialmedia.chats.dto.GroupDtos.GroupMemberInfo;
import com.socialmedia.chats.dto.GroupSummary;
import com.socialmedia.chats.dto.UserSummary;
import com.socialmedia.chats.entity.Conversation;
import com.socialmedia.chats.entity.GroupBan;
import com.socialmedia.chats.entity.GroupInvite;
import com.socialmedia.chats.entity.GroupJoinRequest;
import com.socialmedia.chats.entity.ConversationMember;
import com.socialmedia.chats.entity.Message;
import com.socialmedia.chats.repository.ConversationMemberRepository;
import com.socialmedia.chats.repository.ConversationRepository;
import com.socialmedia.chats.repository.GroupBanRepository;
import com.socialmedia.chats.repository.GroupInviteRepository;
import com.socialmedia.chats.repository.GroupJoinRequestRepository;
import com.socialmedia.chats.repository.MessageRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * Owns the conversation container model (G0). For now only DIRECT
 * conversations are created (stamped onto every 1:1 message); GROUP creation
 * arrives in G1 on top of this same model.
 */
@Service
@RequiredArgsConstructor
@Slf4j
public class ConversationService {

    private final ConversationRepository conversationRepository;
    private final ConversationMemberRepository memberRepository;
    private final MessageRepository messageRepository;
    private final BlockClient blockClient;
    private final UserLookupClient userLookupClient;
    private final GroupBanRepository groupBanRepository;
    private final GroupInviteRepository groupInviteRepository;
    private final GroupJoinRequestRepository joinRequestRepository;
    private final org.springframework.messaging.simp.SimpMessagingTemplate messagingTemplate;

    /**
     * Find the DIRECT conversation for a user pair, creating it (plus both
     * memberships) if absent. Race-safe: the unique direct_key means a
     * concurrent creator loses the insert and re-reads the winner's row.
     *
     * REQUIRES_NEW so a lost insert race doesn't poison the caller's
     * transaction (message send must survive it).
     */
    @Transactional(propagation = Propagation.REQUIRES_NEW)
    public Conversation findOrCreateDirect(Long userA, Long userB) {
        String key = Conversation.directKeyFor(userA, userB);

        return conversationRepository.findByDirectKey(key).orElseGet(() -> {
            try {
                Conversation c = new Conversation();
                c.setType(Conversation.Type.DIRECT);
                c.setCreatedBy(userA);
                c.setDirectKey(key);
                Conversation saved = conversationRepository.save(c);

                memberRepository.save(member(saved.getId(), userA));
                memberRepository.save(member(saved.getId(), userB));
                log.info("[Conversation] Created DIRECT conversation {} for pair {}", saved.getId(), key);
                return saved;
            } catch (DataIntegrityViolationException e) {
                // Lost the race - another request created it between our read and insert.
                log.info("[Conversation] Lost create race for {}, re-reading", key);
                return conversationRepository.findByDirectKey(key)
                        .orElseThrow(() -> e);
            }
        });
    }

    private ConversationMember member(Long conversationId, Long userId) {
        ConversationMember m = new ConversationMember();
        m.setConversationId(conversationId);
        m.setUserId(userId);
        m.setRole(ConversationMember.Role.MEMBER);
        return m;
    }

    // ------------------------------------------------------------------
    // G1: GROUP conversations
    // ------------------------------------------------------------------

    /**
     * Create a GROUP conversation. The creator becomes OWNER; everyone in
     * {@code memberIds} becomes MEMBER.
     *
     * BLOCKING RULE (spec §2-3, §25): the block check applies ONLY here, at
     * member-ADD time. Members with a block relationship to the creator are
     * silently skipped and reported back as ids only - never with a reason.
     * Group message fan-out is NEVER block-filtered.
     */
    @Transactional
    public GroupSummary createGroup(Long creatorId, CreateGroupRequest request) {
        Conversation group = new Conversation();
        group.setType(Conversation.Type.GROUP);
        group.setName(request.getName().trim());
        group.setDescription(request.getDescription());
        group.setPhotoUrl(request.getPhotoUrl());
        group.setCreatedBy(creatorId);
        Conversation saved = conversationRepository.save(group);

        ConversationMember owner = member(saved.getId(), creatorId);
        owner.setRole(ConversationMember.Role.OWNER);
        memberRepository.save(owner);

        // De-duplicate, drop the creator if present, skip blocked relationships.
        Set<Long> candidates = new LinkedHashSet<>(request.getMemberIds() == null
                ? List.of() : request.getMemberIds());
        candidates.remove(creatorId);

        List<Long> skipped = new ArrayList<>();
        int added = 0;
        for (Long memberId : candidates) {
            if (blockClient.isEitherBlocked(creatorId, memberId)) {
                skipped.add(memberId); // neutral: reason never exposed
                continue;
            }
            memberRepository.save(member(saved.getId(), memberId));
            added++;
        }
        log.info("[Conversation] Created GROUP {} '{}' owner={} members={} skipped={}",
                saved.getId(), saved.getName(), creatorId, added, skipped.size());

        GroupSummary summary = toSummary(saved, creatorId);
        summary.setSkippedMemberIds(skipped);
        return summary;
    }

    /** All GROUP conversations the user belongs to, newest activity first. */
    @Transactional(readOnly = true)
    public List<GroupSummary> getGroupsForUser(Long userId) {
        List<GroupSummary> result = new ArrayList<>();
        for (Conversation c : conversationRepository.findAllForUser(userId)) {
            if (c.getType() == Conversation.Type.GROUP) {
                result.add(toSummary(c, userId));
            }
        }
        return result;
    }

    /** Throws unless the user is OWNER/ADMIN. Public so MessageService can gate G4 actions. */
    @Transactional(readOnly = true)
    public void assertAdmin(Long conversationId, Long userId) {
        requireAdmin(conversationId, userId);
    }

    /** Throws unless the user is a member of the conversation. */
    @Transactional(readOnly = true)
    public void assertMember(Long conversationId, Long userId) {
        if (!memberRepository.existsByConversationIdAndUserId(conversationId, userId)) {
            throw new NotAMemberException("Not a member of conversation " + conversationId);
        }
    }

    @Transactional(readOnly = true)
    public List<ConversationMember> getMembers(Long conversationId) {
        return memberRepository.findByConversationId(conversationId);
    }

    /** Marks the conversation read for this member — clears their unread badge. */
    @Transactional
    public void markRead(Long conversationId, Long userId) {
        memberRepository.findByConversationIdAndUserId(conversationId, userId)
            .ifPresent(m -> {
                m.setLastReadAt(java.time.LocalDateTime.now(java.time.ZoneId.of("UTC")));
                memberRepository.save(m);
            });
    }

    /** Bump updatedAt so the group sorts to the top of the chats list. */
    @Transactional
    public void touchConversation(Long conversationId) {
        conversationRepository.findById(conversationId).ifPresent(c -> {
            c.setUpdatedAt(java.time.LocalDateTime.now(java.time.ZoneId.of("UTC")));
            conversationRepository.save(c);
        });
    }

    private GroupSummary toSummary(Conversation c, Long viewerId) {
        GroupSummary s = new GroupSummary();
        s.setId(c.getId());
        s.setName(c.getName());
        s.setDescription(c.getDescription());
        s.setPhotoUrl(c.getPhotoUrl());
        s.setMemberCount((int) memberRepository.countByConversationId(c.getId()));
        s.setCreatedAt(c.getCreatedAt());
        memberRepository.findByConversationIdAndUserId(c.getId(), viewerId)
                .ifPresent(m -> {
                    s.setMyRole(m.getRole().name());
                    s.setMyNotificationLevel(m.getNotificationLevel().name());
                    long unread = m.getLastReadAt() != null
                        ? messageRepository.countUnreadInConversationSince(c.getId(), viewerId, m.getLastReadAt())
                        : messageRepository.countUnreadInConversation(c.getId(), viewerId);
                    s.setUnreadCount(unread);
                });
        // G5 settings
        s.setWhoCanSend(c.getWhoCanSend() != null ? c.getWhoCanSend().name() : "EVERYONE");
        s.setWhoCanEditInfo(c.getWhoCanEditInfo() != null ? c.getWhoCanEditInfo().name() : "ADMINS");
        s.setWhoCanAddMembers(c.getWhoCanAddMembers() != null ? c.getWhoCanAddMembers().name() : "ADMINS");
        s.setWhoCanPin(c.getWhoCanPin() != null ? c.getWhoCanPin().name() : "ADMINS");
        s.setApproveNewMembers(Boolean.TRUE.equals(c.getApproveNewMembers()));

        Message last = messageRepository.findLastInConversation(c.getId());
        if (last != null) {
            s.setLastMessageContent(last.getContent());
            s.setLastMessageTime(last.getCreatedAt());
            try {
                UserSummary sender = userLookupClient.getUser(last.getSenderId());
                s.setLastMessageSenderName(sender != null ? sender.getUsername() : null);
            } catch (Exception ignored) {
            }
        }
        return s;
    }

    /** 404-ish domain exception for non-membership (mapped in the controller). */
    public static class NotAMemberException extends RuntimeException {
        public NotAMemberException(String msg) { super(msg); }
    }

    /** Permission failure - message is deliberately generic (§25). */
    public static class NotPermittedException extends RuntimeException {
        public NotPermittedException(String msg) { super(msg); }
    }

    // ------------------------------------------------------------------
    // G2: roles & member management
    // ------------------------------------------------------------------

    private ConversationMember requireMember(Long conversationId, Long userId) {
        return memberRepository.findByConversationIdAndUserId(conversationId, userId)
                .orElseThrow(() -> new NotAMemberException("Not a member"));
    }

    /** OWNER or ADMIN. */
    private ConversationMember requireAdmin(Long conversationId, Long userId) {
        ConversationMember m = requireMember(conversationId, userId);
        if (m.getRole() == ConversationMember.Role.MEMBER) {
            throw new NotPermittedException("Admins only");
        }
        return m;
    }

    private ConversationMember requireOwner(Long conversationId, Long userId) {
        ConversationMember m = requireMember(conversationId, userId);
        if (m.getRole() != ConversationMember.Role.OWNER) {
            throw new NotPermittedException("Owner only");
        }
        return m;
    }

    /**
     * Add members to a group (OWNER/ADMIN only).
     * Block check applies here (member-ADD), and blocked ids are skipped
     * silently - the reason is never returned (§2-3, §25).
     */
    @Transactional
    public AddMembersResult addMembers(Long conversationId, Long actorId, List<Long> memberIds) {
        // G5: configurable rather than always-admin (spec §R).
        requirePermission(conversationId, actorId, GroupAction.ADD_MEMBERS);

        List<Long> added = new ArrayList<>();
        List<Long> skipped = new ArrayList<>();
        LocalDateTime now = LocalDateTime.now(ZoneId.of("UTC"));

        for (Long candidate : new LinkedHashSet<>(memberIds == null ? List.of() : memberIds)) {
            if (memberRepository.existsByConversationIdAndUserId(conversationId, candidate)) {
                continue; // already in the group
            }
            // GROUP BAN: a group-level decision that applies to EVERY admin.
            if (groupBanRepository.isBanned(conversationId, candidate, now)) {
                skipped.add(candidate);
                continue;
            }
            // PERSONAL BLOCK: scoped to THIS actor only (§17). A different
            // admin without a block relationship can still add this person -
            // a personal block is not a group ban.
            if (blockClient.isEitherBlocked(actorId, candidate)) {
                skipped.add(candidate);
                continue;
            }
            memberRepository.save(member(conversationId, candidate));
            added.add(candidate);
            systemMessage(conversationId, "MEMBER_ADDED", actorId, candidate);
        }

        AddMembersResult result = new AddMembersResult();
        result.setAddedMemberIds(added);
        result.setSkippedMemberIds(skipped);
        result.setMemberCount((int) memberRepository.countByConversationId(conversationId));
        return result;
    }

    /**
     * Remove a member (OWNER/ADMIN only). This is group moderation and is
     * independent of personal blocking (§12-13). An ADMIN cannot remove
     * another ADMIN or the OWNER; the OWNER can remove anyone.
     */
    @Transactional
    public void removeMember(Long conversationId, Long actorId, Long targetId) {
        ConversationMember actor = requireAdmin(conversationId, actorId);
        ConversationMember target = requireMember(conversationId, targetId);

        if (target.getRole() == ConversationMember.Role.OWNER) {
            throw new NotPermittedException("Cannot remove the owner");
        }
        if (actor.getRole() == ConversationMember.Role.ADMIN
                && target.getRole() == ConversationMember.Role.ADMIN) {
            throw new NotPermittedException("Admins cannot remove other admins");
        }
        memberRepository.delete(target);
        systemMessage(conversationId, "MEMBER_REMOVED", actorId, targetId);
    }

    /** Leave a group. The OWNER must transfer ownership first (§V). */
    @Transactional
    public void leaveGroup(Long conversationId, Long userId) {
        ConversationMember me = requireMember(conversationId, userId);
        if (me.getRole() == ConversationMember.Role.OWNER
                && memberRepository.countByConversationId(conversationId) > 1) {
            throw new NotPermittedException("Transfer ownership before leaving");
        }
        memberRepository.delete(me);
        systemMessage(conversationId, "MEMBER_LEFT", userId, userId);
    }

    /** Promote to ADMIN or demote to MEMBER (OWNER only). */
    @Transactional
    public void changeRole(Long conversationId, Long actorId, Long targetId, String newRole) {
        requireOwner(conversationId, actorId);
        if (actorId.equals(targetId)) {
            throw new NotPermittedException("Cannot change your own role");
        }
        ConversationMember target = requireMember(conversationId, targetId);

        ConversationMember.Role role;
        try {
            role = ConversationMember.Role.valueOf(newRole == null ? "" : newRole.toUpperCase());
        } catch (IllegalArgumentException e) {
            throw new NotPermittedException("Invalid role");
        }
        if (role == ConversationMember.Role.OWNER) {
            throw new NotPermittedException("Use transfer ownership");
        }

        target.setRole(role);
        memberRepository.save(target);
        systemMessage(conversationId,
                role == ConversationMember.Role.ADMIN ? "ADMIN_PROMOTED" : "ADMIN_DEMOTED",
                actorId, targetId);
    }

    /** Hand ownership to another member; the old owner becomes ADMIN. */
    @Transactional
    public void transferOwnership(Long conversationId, Long actorId, Long newOwnerId) {
        ConversationMember owner = requireOwner(conversationId, actorId);
        ConversationMember newOwner = requireMember(conversationId, newOwnerId);

        owner.setRole(ConversationMember.Role.ADMIN);
        newOwner.setRole(ConversationMember.Role.OWNER);
        memberRepository.save(owner);
        memberRepository.save(newOwner);
        systemMessage(conversationId, "OWNER_TRANSFERRED", actorId, newOwnerId);
    }

    /** Edit group name/description/photo (OWNER/ADMIN only). */
    @Transactional
    public GroupSummary updateGroupInfo(Long conversationId, Long actorId,
                                        String name, String description, String photoUrl) {
        requirePermission(conversationId, actorId, GroupAction.EDIT_INFO);
        Conversation c = conversationRepository.findById(conversationId)
                .orElseThrow(() -> new NotAMemberException("Conversation not found"));

        boolean nameChanged = false, photoChanged = false;
        if (name != null && !name.trim().isEmpty() && !name.trim().equals(c.getName())) {
            c.setName(name.trim());
            nameChanged = true;
        }
        if (description != null) c.setDescription(description);
        if (photoUrl != null && !photoUrl.equals(c.getPhotoUrl())) {
            c.setPhotoUrl(photoUrl);
            photoChanged = true;
        }
        Conversation saved = conversationRepository.save(c);

        if (nameChanged) systemMessage(conversationId, "NAME_CHANGED", actorId, null);
        if (photoChanged) systemMessage(conversationId, "PHOTO_CHANGED", actorId, null);
        return toSummary(saved, actorId);
    }

    /** Members enriched with profile data (from auth-service). */
    @Transactional(readOnly = true)
    public List<GroupMemberInfo> getMemberInfos(Long conversationId, Long requesterId) {
        assertMember(conversationId, requesterId);
        List<ConversationMember> members = memberRepository.findByConversationId(conversationId);

        // Warm the lookup cache in one batch rather than N sequential calls.
        userLookupClient.getUsers(members.stream()
                .map(ConversationMember::getUserId).collect(Collectors.toList()));

        List<GroupMemberInfo> infos = new ArrayList<>();
        for (ConversationMember m : members) {
            GroupMemberInfo info = new GroupMemberInfo();
            info.setUserId(m.getUserId());
            info.setRole(m.getRole().name());
            info.setJoinedAt(m.getJoinedAt());
            UserSummary u = userLookupClient.getUser(m.getUserId());
            if (u != null) {
                info.setUsername(u.getUsername());
                info.setFullName(u.getFullName());
                info.setProfilePictureUrl(u.getProfilePictureUrl());
            }
            infos.add(info);
        }
        // OWNER, then ADMINs, then MEMBERs
        infos.sort(Comparator.comparingInt(i -> switch (i.getRole()) {
            case "OWNER" -> 0;
            case "ADMIN" -> 1;
            default -> 2;
        }));
        return infos;
    }

    // ------------------------------------------------------------------
    // G5: configurable permissions, invites, join requests, notifications
    // ------------------------------------------------------------------

    /** Which group action is being attempted (each maps to a stored setting). */
    public enum GroupAction { SEND, EDIT_INFO, ADD_MEMBERS, PIN }

    /**
     * Permission gate driven by the group's own settings rather than a
     * hard-coded role check (spec §R). OWNER/ADMIN always pass; MEMBER passes
     * only when the relevant setting is EVERYONE.
     */
    @Transactional(readOnly = true)
    public void requirePermission(Long conversationId, Long userId, GroupAction action) {
        ConversationMember me = requireMember(conversationId, userId);
        if (me.getRole() != ConversationMember.Role.MEMBER) return; // owner/admin

        Conversation c = conversationRepository.findById(conversationId)
                .orElseThrow(() -> new NotAMemberException("Conversation not found"));

        Conversation.PermissionLevel level = switch (action) {
            case SEND -> c.getWhoCanSend();
            case EDIT_INFO -> c.getWhoCanEditInfo();
            case ADD_MEMBERS -> c.getWhoCanAddMembers();
            case PIN -> c.getWhoCanPin();
        };
        if (level != Conversation.PermissionLevel.EVERYONE) {
            throw new NotPermittedException("Admins only");
        }
    }

    /** Update the group's permission settings (OWNER/ADMIN). */
    @Transactional
    public GroupSummary updatePermissions(Long conversationId, Long actorId,
                                          String send, String editInfo,
                                          String addMembers, String pin,
                                          Boolean approveNewMembers) {
        requireAdmin(conversationId, actorId);
        Conversation c = conversationRepository.findById(conversationId)
                .orElseThrow(() -> new NotAMemberException("Conversation not found"));

        if (send != null) c.setWhoCanSend(parseLevel(send));
        if (editInfo != null) c.setWhoCanEditInfo(parseLevel(editInfo));
        if (addMembers != null) c.setWhoCanAddMembers(parseLevel(addMembers));
        if (pin != null) c.setWhoCanPin(parseLevel(pin));
        if (approveNewMembers != null) c.setApproveNewMembers(approveNewMembers);

        Conversation saved = conversationRepository.save(c);
        systemMessage(conversationId, "SETTINGS_CHANGED", actorId, null);
        return toSummary(saved, actorId);
    }

    private Conversation.PermissionLevel parseLevel(String value) {
        try {
            return Conversation.PermissionLevel.valueOf(value.toUpperCase());
        } catch (Exception e) {
            throw new NotPermittedException("Invalid permission value");
        }
    }

    /** Current active invite for a group, creating one if absent. */
    @Transactional
    public GroupInvite getOrCreateInvite(Long conversationId, Long actorId) {
        requireAdmin(conversationId, actorId);
        return groupInviteRepository.findActive(conversationId).stream()
                .filter(GroupInvite::isUsable)
                .findFirst()
                .orElseGet(() -> createInvite(conversationId, actorId));
    }

    /** Reset the link: deactivate existing codes and mint a new one (§O). */
    @Transactional
    public GroupInvite resetInvite(Long conversationId, Long actorId) {
        requireAdmin(conversationId, actorId);
        for (GroupInvite old : groupInviteRepository.findActive(conversationId)) {
            old.setIsActive(false);
            groupInviteRepository.save(old);
        }
        return createInvite(conversationId, actorId);
    }

    private GroupInvite createInvite(Long conversationId, Long actorId) {
        GroupInvite invite = new GroupInvite();
        invite.setConversationId(conversationId);
        invite.setCode(java.util.UUID.randomUUID().toString().replace("-", "").substring(0, 16));
        invite.setCreatedBy(actorId);
        invite.setIsActive(true);
        return groupInviteRepository.save(invite);
    }

    /** What a prospective member sees before joining (§O). */
    @Transactional(readOnly = true)
    public GroupSummary previewInvite(String code, Long viewerId) {
        GroupInvite invite = groupInviteRepository.findByCode(code)
                .filter(GroupInvite::isUsable)
                .orElseThrow(() -> new NotPermittedException("This invite link is no longer valid"));
        Conversation c = conversationRepository.findById(invite.getConversationId())
                .orElseThrow(() -> new NotPermittedException("This invite link is no longer valid"));
        return toSummary(c, viewerId);
    }

    /**
     * Join via invite code.
     *
     * Checks in order (spec §17): invite validity, existing membership,
     * GROUP BAN (a personal block must NOT block this), then the group's
     * approval setting - which turns the join into a pending request (§P).
     *
     * @return "JOINED" or "REQUESTED"
     */
    @Transactional
    public String joinByInvite(String code, Long userId) {
        GroupInvite invite = groupInviteRepository.findByCode(code)
                .filter(GroupInvite::isUsable)
                .orElseThrow(() -> new NotPermittedException("This invite link is no longer valid"));

        Long conversationId = invite.getConversationId();
        if (memberRepository.existsByConversationIdAndUserId(conversationId, userId)) {
            return "ALREADY_MEMBER";
        }
        // Group ban blocks joining; personal blocks deliberately do not (§17).
        if (groupBanRepository.isBanned(conversationId, userId,
                LocalDateTime.now(ZoneId.of("UTC")))) {
            throw new NotPermittedException("Unable to join this group");
        }

        Conversation c = conversationRepository.findById(conversationId)
                .orElseThrow(() -> new NotPermittedException("This invite link is no longer valid"));

        if (Boolean.TRUE.equals(c.getApproveNewMembers())) {
            GroupJoinRequest request = joinRequestRepository
                    .findByConversationIdAndUserId(conversationId, userId)
                    .orElseGet(GroupJoinRequest::new);
            request.setConversationId(conversationId);
            request.setUserId(userId);
            request.setStatus(GroupJoinRequest.Status.PENDING);
            request.setDecidedAt(null);
            request.setDecidedBy(null);
            joinRequestRepository.save(request);
            return "REQUESTED";
        }

        memberRepository.save(member(conversationId, userId));
        systemMessage(conversationId, "MEMBER_JOINED", userId, userId);
        return "JOINED";
    }

    @Transactional(readOnly = true)
    public List<GroupMemberInfo> getPendingRequests(Long conversationId, Long actorId) {
        requireAdmin(conversationId, actorId);
        List<GroupJoinRequest> pending = joinRequestRepository
                .findByConversationIdAndStatusOrderByCreatedAtDesc(
                        conversationId, GroupJoinRequest.Status.PENDING);

        userLookupClient.getUsers(pending.stream()
                .map(GroupJoinRequest::getUserId).collect(Collectors.toList()));

        List<GroupMemberInfo> infos = new ArrayList<>();
        for (GroupJoinRequest r : pending) {
            GroupMemberInfo info = new GroupMemberInfo();
            info.setUserId(r.getUserId());
            info.setRole("PENDING");
            info.setJoinedAt(r.getCreatedAt());
            UserSummary u = userLookupClient.getUser(r.getUserId());
            if (u != null) {
                info.setUsername(u.getUsername());
                info.setFullName(u.getFullName());
                info.setProfilePictureUrl(u.getProfilePictureUrl());
            }
            infos.add(info);
        }
        return infos;
    }

    /** Accept or reject a pending join request (§P). */
    @Transactional
    public void decideJoinRequest(Long conversationId, Long actorId,
                                  Long targetUserId, boolean accept) {
        requireAdmin(conversationId, actorId);
        GroupJoinRequest request = joinRequestRepository
                .findByConversationIdAndUserId(conversationId, targetUserId)
                .orElseThrow(() -> new NotPermittedException("No pending request"));

        request.setStatus(accept ? GroupJoinRequest.Status.ACCEPTED
                : GroupJoinRequest.Status.REJECTED);
        request.setDecidedAt(LocalDateTime.now(ZoneId.of("UTC")));
        request.setDecidedBy(actorId);
        joinRequestRepository.save(request);

        if (accept && !memberRepository.existsByConversationIdAndUserId(conversationId, targetUserId)) {
            memberRepository.save(member(conversationId, targetUserId));
            systemMessage(conversationId, "MEMBER_JOINED", actorId, targetUserId);
        }
    }

    /** My own notification preference for this group (§U). */
    @Transactional
    public void setNotificationLevel(Long conversationId, Long userId,
                                     String level, Integer muteHours) {
        ConversationMember me = requireMember(conversationId, userId);
        if (level != null) {
            try {
                me.setNotificationLevel(
                        ConversationMember.NotificationLevel.valueOf(level.toUpperCase()));
            } catch (IllegalArgumentException e) {
                throw new NotPermittedException("Invalid notification level");
            }
        }
        me.setMutedUntil(muteHours == null || muteHours <= 0
                ? null
                : LocalDateTime.now(ZoneId.of("UTC")).plusHours(muteHours));
        memberRepository.save(me);
    }

    // ------------------------------------------------------------------
    // G3: GROUP BAN (independent of personal blocking - spec §15-17, §27)
    // ------------------------------------------------------------------

    /**
     * Ban a user from this group: removes them if present AND records a ban so
     * they cannot be re-added or rejoin.
     *
     * This is group moderation, not a personal relationship: it applies to
     * every admin, and it neither creates nor consults a personal block.
     * Same authority rules as removal - the owner is immune, and an admin
     * cannot ban another admin.
     */
    @Transactional
    public void banMember(Long conversationId, Long actorId, Long targetId, String reason) {
        ConversationMember actor = requireAdmin(conversationId, actorId);
        if (actorId.equals(targetId)) {
            throw new NotPermittedException("Cannot ban yourself");
        }

        // If they are currently a member, apply the same protections as removal.
        memberRepository.findByConversationIdAndUserId(conversationId, targetId)
                .ifPresent(target -> {
                    if (target.getRole() == ConversationMember.Role.OWNER) {
                        throw new NotPermittedException("Cannot ban the owner");
                    }
                    if (actor.getRole() == ConversationMember.Role.ADMIN
                            && target.getRole() == ConversationMember.Role.ADMIN) {
                        throw new NotPermittedException("Admins cannot ban other admins");
                    }
                    memberRepository.delete(target);
                });

        GroupBan ban = groupBanRepository
                .findByConversationIdAndUserId(conversationId, targetId)
                .orElseGet(GroupBan::new);
        ban.setConversationId(conversationId);
        ban.setUserId(targetId);
        ban.setBannedBy(actorId);
        ban.setReason(reason);
        ban.setStatus(GroupBan.Status.ACTIVE);
        ban.setLiftedAt(null);
        ban.setLiftedBy(null);
        groupBanRepository.save(ban);

        systemMessage(conversationId, "MEMBER_BANNED", actorId, targetId);
        log.info("[Conversation] user {} banned from group {} by {}", targetId, conversationId, actorId);
    }

    /** Lift a ban (OWNER/ADMIN). Does NOT re-add the user - they must be invited again. */
    @Transactional
    public void unbanMember(Long conversationId, Long actorId, Long targetId) {
        requireAdmin(conversationId, actorId);
        GroupBan ban = groupBanRepository
                .findByConversationIdAndUserId(conversationId, targetId)
                .orElseThrow(() -> new NotPermittedException("No ban found"));

        ban.setStatus(GroupBan.Status.LIFTED);
        ban.setLiftedAt(LocalDateTime.now(ZoneId.of("UTC")));
        ban.setLiftedBy(actorId);
        groupBanRepository.save(ban);
        systemMessage(conversationId, "MEMBER_UNBANNED", actorId, targetId);
    }

    /** Active bans for a group, enriched with profile data (admins only). */
    @Transactional(readOnly = true)
    public List<GroupMemberInfo> getActiveBans(Long conversationId, Long requesterId) {
        requireAdmin(conversationId, requesterId);
        List<GroupBan> bans = groupBanRepository.findActiveBans(
                conversationId, LocalDateTime.now(ZoneId.of("UTC")));

        userLookupClient.getUsers(bans.stream()
                .map(GroupBan::getUserId).collect(Collectors.toList()));

        List<GroupMemberInfo> infos = new ArrayList<>();
        for (GroupBan b : bans) {
            GroupMemberInfo info = new GroupMemberInfo();
            info.setUserId(b.getUserId());
            info.setRole("BANNED");
            info.setJoinedAt(b.getCreatedAt());
            UserSummary u = userLookupClient.getUser(b.getUserId());
            if (u != null) {
                info.setUsername(u.getUsername());
                info.setFullName(u.getFullName());
                info.setProfilePictureUrl(u.getProfilePictureUrl());
            }
            infos.add(info);
        }
        return infos;
    }

    /** Is this user banned from this group right now? (used by any join path) */
    @Transactional(readOnly = true)
    public boolean isBanned(Long conversationId, Long userId) {
        return groupBanRepository.isBanned(conversationId, userId,
                LocalDateTime.now(ZoneId.of("UTC")));
    }

    /**
     * Append a SYSTEM message describing a group event and fan it out live.
     * Best-effort: a logging failure must never roll back the actual change.
     */
    private void systemMessage(Long conversationId, String event, Long actorId, Long targetId) {
        try {
            Message m = new Message();
            m.setConversationId(conversationId);
            m.setSenderId(actorId);
            m.setReceiverId(null);
            m.setContent(""); // client renders from the event + ids
            m.setMessageType("SYSTEM");
            m.setSystemEvent(event);
            m.setSystemActorId(actorId);
            m.setSystemTargetId(targetId);
            Message saved = messageRepository.save(m);

            java.util.Map<String, Object> payload = new java.util.HashMap<>();
            payload.put("id", saved.getId());
            payload.put("conversationId", conversationId);
            payload.put("messageType", "SYSTEM");
            payload.put("systemEvent", event);
            payload.put("systemActorId", actorId);
            payload.put("systemTargetId", targetId);
            payload.put("senderId", actorId);
            payload.put("content", "");
            payload.put("createdAt", saved.getCreatedAt());
            messagingTemplate.convertAndSend("/topic/conversation." + conversationId, payload);
        } catch (Exception e) {
            log.warn("[Conversation] system message '{}' failed: {}", event, e.getMessage());
        }
    }
}
