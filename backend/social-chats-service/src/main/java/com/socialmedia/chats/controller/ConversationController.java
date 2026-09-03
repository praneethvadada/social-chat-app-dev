package com.socialmedia.chats.controller;

import com.socialmedia.chats.dto.CreateGroupRequest;
import com.socialmedia.chats.dto.GroupDtos.AddMembersRequest;
import com.socialmedia.chats.dto.GroupDtos.AddMembersResult;
import com.socialmedia.chats.dto.GroupDtos.GroupMemberInfo;
import com.socialmedia.chats.dto.GroupDtos.RoleChangeRequest;
import com.socialmedia.chats.dto.GroupDtos.TransferOwnerRequest;
import com.socialmedia.chats.dto.GroupDtos.UpdateGroupInfoRequest;
import com.socialmedia.chats.dto.GroupMessageRequest;
import com.socialmedia.chats.dto.GroupSummary;
import com.socialmedia.chats.dto.MessageResponse;
import com.socialmedia.chats.entity.ConversationMember;
import com.socialmedia.chats.service.ConversationService;
import com.socialmedia.chats.service.MessageService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

/**
 * G1: group conversation REST API.
 * Reached through the gateway as /api/social/conversations/** (StripPrefix=2).
 */
@RestController
@RequestMapping("/conversations")
@RequiredArgsConstructor
public class ConversationController {

    private final ConversationService conversationService;
    private final MessageService messageService;

    @PostMapping("/group")
    public ResponseEntity<GroupSummary> createGroup(
            @Valid @RequestBody CreateGroupRequest request,
            @RequestAttribute("userId") Long userId) {
        return ResponseEntity.ok(conversationService.createGroup(userId, request));
    }

    @GetMapping("/groups")
    public ResponseEntity<List<GroupSummary>> myGroups(@RequestAttribute("userId") Long userId) {
        return ResponseEntity.ok(conversationService.getGroupsForUser(userId));
    }

    @PostMapping("/{conversationId}/read")
    public ResponseEntity<Void> markRead(
            @PathVariable Long conversationId,
            @RequestAttribute("userId") Long userId) {
        conversationService.assertMember(conversationId, userId);
        conversationService.markRead(conversationId, userId);
        return ResponseEntity.ok().build();
    }

    @GetMapping("/{conversationId}/members")
    public ResponseEntity<List<ConversationMember>> members(
            @PathVariable Long conversationId,
            @RequestAttribute("userId") Long userId) {
        conversationService.assertMember(conversationId, userId);
        return ResponseEntity.ok(conversationService.getMembers(conversationId));
    }

    /**
     * Phase 4: incremental sync - everything newer than {@code cursor} (a
     * previously-returned message id). Works for both DIRECT and GROUP
     * conversations since both carry a real conversationId (G0). Requires a
     * cursor - a client syncing for the first time should call
     * {@code /messages} (below) instead and seed its cursor from what it sees
     * there.
     */
    @GetMapping("/{conversationId}/sync")
    public ResponseEntity<com.socialmedia.chats.dto.ConversationSyncResponse> sync(
            @PathVariable Long conversationId,
            @RequestParam Long cursor,
            @RequestParam(defaultValue = "200") int limit,
            @RequestAttribute("userId") Long userId) {
        return ResponseEntity.ok(messageService.syncConversation(conversationId, userId, cursor, limit));
    }

    @GetMapping("/{conversationId}/messages")
    public ResponseEntity<Page<MessageResponse>> messages(
            @PathVariable Long conversationId,
            @RequestAttribute("userId") Long userId,
            @RequestParam(defaultValue = "0") int page,
            @RequestParam(defaultValue = "50") int size) {
        return ResponseEntity.ok(
                messageService.getGroupMessages(conversationId, userId, PageRequest.of(page, size)));
    }

    @PostMapping("/{conversationId}/messages")
    public ResponseEntity<MessageResponse> send(
            @PathVariable Long conversationId,
            @Valid @RequestBody GroupMessageRequest request,
            @RequestAttribute("userId") Long userId) {
        return ResponseEntity.ok(
                messageService.sendGroupMessage(conversationId, userId, request));
    }

    // ---------------- G2: roles & member management ----------------

    @GetMapping("/{conversationId}/member-infos")
    public ResponseEntity<List<GroupMemberInfo>> memberInfos(
            @PathVariable Long conversationId,
            @RequestAttribute("userId") Long userId) {
        return ResponseEntity.ok(conversationService.getMemberInfos(conversationId, userId));
    }

    @PostMapping("/{conversationId}/members")
    public ResponseEntity<AddMembersResult> addMembers(
            @PathVariable Long conversationId,
            @Valid @RequestBody AddMembersRequest request,
            @RequestAttribute("userId") Long userId) {
        return ResponseEntity.ok(
                conversationService.addMembers(conversationId, userId, request.getMemberIds()));
    }

    @DeleteMapping("/{conversationId}/members/{targetId}")
    public ResponseEntity<Void> removeMember(
            @PathVariable Long conversationId,
            @PathVariable Long targetId,
            @RequestAttribute("userId") Long userId) {
        conversationService.removeMember(conversationId, userId, targetId);
        return ResponseEntity.ok().build();
    }

    @PostMapping("/{conversationId}/leave")
    public ResponseEntity<Void> leave(
            @PathVariable Long conversationId,
            @RequestAttribute("userId") Long userId) {
        conversationService.leaveGroup(conversationId, userId);
        return ResponseEntity.ok().build();
    }

    @PutMapping("/{conversationId}/members/{targetId}/role")
    public ResponseEntity<Void> changeRole(
            @PathVariable Long conversationId,
            @PathVariable Long targetId,
            @RequestBody RoleChangeRequest request,
            @RequestAttribute("userId") Long userId) {
        conversationService.changeRole(conversationId, userId, targetId, request.getRole());
        return ResponseEntity.ok().build();
    }

    @PutMapping("/{conversationId}/transfer-owner")
    public ResponseEntity<Void> transferOwner(
            @PathVariable Long conversationId,
            @RequestBody TransferOwnerRequest request,
            @RequestAttribute("userId") Long userId) {
        conversationService.transferOwnership(conversationId, userId, request.getNewOwnerId());
        return ResponseEntity.ok().build();
    }

    @PutMapping("/{conversationId}/info")
    public ResponseEntity<GroupSummary> updateInfo(
            @PathVariable Long conversationId,
            @Valid @RequestBody UpdateGroupInfoRequest request,
            @RequestAttribute("userId") Long userId) {
        return ResponseEntity.ok(conversationService.updateGroupInfo(
                conversationId, userId, request.getName(),
                request.getDescription(), request.getPhotoUrl()));
    }

    // ---------------- G4: reply / react / pin / delete / search ----------------

    @PostMapping("/messages/{messageId}/reaction")
    public ResponseEntity<Void> reactToMessage(
            @PathVariable Long messageId,
            @RequestBody Map<String, String> body,
            @RequestAttribute("userId") Long userId) {
        messageService.reactToMessage(messageId, userId, body.get("reaction"));
        return ResponseEntity.ok().build();
    }

    @GetMapping("/messages/{messageId}/reactions")
    public ResponseEntity<List<Map<String, Object>>> messageReactions(
            @PathVariable Long messageId,
            @RequestAttribute("userId") Long userId) {
        return ResponseEntity.ok(messageService.getMessageReactions(messageId, userId));
    }

    @PutMapping("/messages/{messageId}/pin")
    public ResponseEntity<Void> pin(
            @PathVariable Long messageId,
            @RequestBody(required = false) Map<String, Boolean> body,
            @RequestAttribute("userId") Long userId) {
        boolean pinned = body == null || body.get("pinned") == null || body.get("pinned");
        messageService.setPinned(messageId, userId, pinned);
        return ResponseEntity.ok().build();
    }

    @GetMapping("/{conversationId}/pinned")
    public ResponseEntity<List<MessageResponse>> pinned(
            @PathVariable Long conversationId,
            @RequestAttribute("userId") Long userId) {
        return ResponseEntity.ok(messageService.getPinned(conversationId, userId));
    }

    /** Delete for everyone: own message, or any message if you moderate. */
    @DeleteMapping("/messages/{messageId}")
    public ResponseEntity<Void> deleteMessage(
            @PathVariable Long messageId,
            @RequestAttribute("userId") Long userId) {
        messageService.deleteForEveryone(messageId, userId);
        return ResponseEntity.ok().build();
    }

    /** GAP-3: forward a message into another conversation. */
    @PostMapping("/messages/{messageId}/forward")
    public ResponseEntity<MessageResponse> forward(
            @PathVariable Long messageId,
            @RequestBody Map<String, Object> body,
            @RequestAttribute("userId") Long userId) {
        Long target = ((Number) body.get("targetConversationId")).longValue();
        return ResponseEntity.ok(
                messageService.forwardMessage(messageId, userId, target));
    }

    @GetMapping("/{conversationId}/search")
    public ResponseEntity<List<MessageResponse>> search(
            @PathVariable Long conversationId,
            @RequestParam String q,
            @RequestAttribute("userId") Long userId) {
        return ResponseEntity.ok(messageService.searchInConversation(conversationId, userId, q));
    }

    // ---------------- G5: permissions / invites / join requests / notifications ----------------

    @PutMapping("/{conversationId}/permissions")
    public ResponseEntity<GroupSummary> updatePermissions(
            @PathVariable Long conversationId,
            @RequestBody Map<String, Object> body,
            @RequestAttribute("userId") Long userId) {
        return ResponseEntity.ok(conversationService.updatePermissions(
                conversationId, userId,
                (String) body.get("whoCanSend"),
                (String) body.get("whoCanEditInfo"),
                (String) body.get("whoCanAddMembers"),
                (String) body.get("whoCanPin"),
                (Boolean) body.get("approveNewMembers")));
    }

    /** Current invite link, created on first request. */
    @GetMapping("/{conversationId}/invite")
    public ResponseEntity<Map<String, Object>> invite(
            @PathVariable Long conversationId,
            @RequestAttribute("userId") Long userId) {
        return ResponseEntity.ok(inviteBody(
                conversationService.getOrCreateInvite(conversationId, userId)));
    }

    /** Invalidate the old link and mint a new code (spec §O). */
    @PostMapping("/{conversationId}/invite/reset")
    public ResponseEntity<Map<String, Object>> resetInvite(
            @PathVariable Long conversationId,
            @RequestAttribute("userId") Long userId) {
        return ResponseEntity.ok(inviteBody(
                conversationService.resetInvite(conversationId, userId)));
    }

    /** What someone sees before joining. */
    @GetMapping("/invite/{code}")
    public ResponseEntity<GroupSummary> previewInvite(
            @PathVariable String code,
            @RequestAttribute("userId") Long userId) {
        return ResponseEntity.ok(conversationService.previewInvite(code, userId));
    }

    /** Join (or request to join, when approval is on). */
    @PostMapping("/invite/{code}/join")
    public ResponseEntity<Map<String, String>> joinByInvite(
            @PathVariable String code,
            @RequestAttribute("userId") Long userId) {
        return ResponseEntity.ok(
                Map.of("result", conversationService.joinByInvite(code, userId)));
    }

    @GetMapping("/{conversationId}/join-requests")
    public ResponseEntity<List<GroupMemberInfo>> joinRequests(
            @PathVariable Long conversationId,
            @RequestAttribute("userId") Long userId) {
        return ResponseEntity.ok(
                conversationService.getPendingRequests(conversationId, userId));
    }

    @PostMapping("/{conversationId}/join-requests/{targetId}")
    public ResponseEntity<Void> decideJoinRequest(
            @PathVariable Long conversationId,
            @PathVariable Long targetId,
            @RequestBody Map<String, Boolean> body,
            @RequestAttribute("userId") Long userId) {
        conversationService.decideJoinRequest(conversationId, userId, targetId,
                Boolean.TRUE.equals(body.get("accept")));
        return ResponseEntity.ok().build();
    }

    /** My own notification preference for this group (spec §U). */
    @PutMapping("/{conversationId}/notifications")
    public ResponseEntity<Void> setNotifications(
            @PathVariable Long conversationId,
            @RequestBody Map<String, Object> body,
            @RequestAttribute("userId") Long userId) {
        Object hours = body.get("muteHours");
        conversationService.setNotificationLevel(conversationId, userId,
                (String) body.get("level"),
                hours == null ? null : ((Number) hours).intValue());
        return ResponseEntity.ok().build();
    }

    private Map<String, Object> inviteBody(com.socialmedia.chats.entity.GroupInvite invite) {
        Map<String, Object> m = new java.util.HashMap<>();
        m.put("code", invite.getCode());
        m.put("createdAt", invite.getCreatedAt());
        m.put("expiresAt", invite.getExpiresAt());
        return m;
    }

    // ---------------- G3: group ban (independent of personal blocking) ----------------

    /** Ban = remove + prevent rejoin. Distinct from DELETE members/{id} (§15). */
    @PostMapping("/{conversationId}/bans/{targetId}")
    public ResponseEntity<Void> ban(
            @PathVariable Long conversationId,
            @PathVariable Long targetId,
            @RequestBody(required = false) Map<String, String> body,
            @RequestAttribute("userId") Long userId) {
        conversationService.banMember(conversationId, userId, targetId,
                body == null ? null : body.get("reason"));
        return ResponseEntity.ok().build();
    }

    /** Lift a ban. Does not re-add the user - they must be invited again. */
    @DeleteMapping("/{conversationId}/bans/{targetId}")
    public ResponseEntity<Void> unban(
            @PathVariable Long conversationId,
            @PathVariable Long targetId,
            @RequestAttribute("userId") Long userId) {
        conversationService.unbanMember(conversationId, userId, targetId);
        return ResponseEntity.ok().build();
    }

    @GetMapping("/{conversationId}/bans")
    public ResponseEntity<List<GroupMemberInfo>> bans(
            @PathVariable Long conversationId,
            @RequestAttribute("userId") Long userId) {
        return ResponseEntity.ok(conversationService.getActiveBans(conversationId, userId));
    }

    /** Non-members get a neutral 403 - membership, not block state, is the reason given. */
    @ExceptionHandler(ConversationService.NotAMemberException.class)
    public ResponseEntity<Map<String, String>> handleNotAMember(ConversationService.NotAMemberException e) {
        return ResponseEntity.status(HttpStatus.FORBIDDEN)
                .body(Map.of("error", "You are not a member of this conversation"));
    }

    @ExceptionHandler(IllegalArgumentException.class)
    public ResponseEntity<Map<String, String>> handleBadRequest(IllegalArgumentException e) {
        return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
    }

    /** Permission failures carry the rule that failed, never block/user state. */
    @ExceptionHandler(ConversationService.NotPermittedException.class)
    public ResponseEntity<Map<String, String>> handleNotPermitted(ConversationService.NotPermittedException e) {
        return ResponseEntity.status(HttpStatus.FORBIDDEN)
                .body(Map.of("error", e.getMessage()));
    }
}
