import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/group.dart';
import '../models/message.dart';
import 'api_service.dart';

/// REST client for GROUP conversations (G1).
/// All routes go through the gateway: /api/social/conversations/** -> chats-service.
class GroupApi {
  static String get _base => '${ApiConfig.baseUrl}/social/conversations';

  static Future<Map<String, String>> _headers() async {
    final token = await ApiService.getToken();
    if (token == null) throw Exception('Not authenticated');
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  /// Create a group. Members with a block relationship are silently skipped
  /// by the backend (their ids come back in skippedMemberIds, reason never given).
  static Future<GroupSummary> createGroup({
    required String name,
    String? description,
    required List<int> memberIds,
  }) async {
    final response = await http.post(
      Uri.parse('$_base/group'),
      headers: await _headers(),
      body: jsonEncode({
        'name': name,
        if (description != null && description.isNotEmpty)
          'description': description,
        'memberIds': memberIds,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to create group (${response.statusCode})');
    }
    return GroupSummary.fromJson(jsonDecode(response.body));
  }

  static Future<List<GroupSummary>> fetchMyGroups() async {
    final response =
        await http.get(Uri.parse('$_base/groups'), headers: await _headers());
    if (response.statusCode != 200) {
      throw Exception('Failed to load groups (${response.statusCode})');
    }
    final list = jsonDecode(response.body) as List;
    return list
        .map((e) => GroupSummary.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Marks the group read for the current user — clears its unread badge.
  static Future<void> markRead(int conversationId) async {
    await http.post(
      Uri.parse('$_base/$conversationId/read'),
      headers: await _headers(),
    );
  }

  /// Newest-first page of group messages.
  static Future<List<Message>> fetchMessages(int conversationId,
      {int page = 0, int size = 50}) async {
    final response = await http.get(
      Uri.parse('$_base/$conversationId/messages?page=$page&size=$size'),
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to load messages (${response.statusCode})');
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final content = body['content'] as List? ?? [];
    return content
        .map((e) => Message.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Phase 4: incremental catch-up since [cursor] (a previously-returned
  /// message id). Works for both DIRECT and GROUP conversations - both carry
  /// a real conversationId. [cursor] must be a positive id; a conversation
  /// with no prior cursor should use [fetchMessages]/[ApiService.getConversation]
  /// for its one-time initial load instead, then start syncing from there.
  static Future<ConversationSyncResult> sync(int conversationId, int cursor,
      {int limit = 200}) async {
    final response = await http.get(
      Uri.parse('$_base/$conversationId/sync?cursor=$cursor&limit=$limit'),
      headers: await _headers(),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to sync conversation (${response.statusCode})');
    }
    return ConversationSyncResult.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  // ---------------- G2: roles & member management ----------------

  static Future<List<GroupMember>> fetchMembers(int conversationId) async {
    final response = await http.get(
        Uri.parse('$_base/$conversationId/member-infos'),
        headers: await _headers());
    if (response.statusCode != 200) {
      throw Exception('Failed to load members (${response.statusCode})');
    }
    return (jsonDecode(response.body) as List)
        .map((e) => GroupMember.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Returns the ids that could NOT be added (reason never disclosed).
  static Future<List<int>> addMembers(
      int conversationId, List<int> memberIds) async {
    final response = await http.post(
      Uri.parse('$_base/$conversationId/members'),
      headers: await _headers(),
      body: jsonEncode({'memberIds': memberIds}),
    );
    if (response.statusCode != 200) {
      throw Exception(_errorOf(response));
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['skippedMemberIds'] as List? ?? [])
        .map((e) => e as int)
        .toList();
  }

  static Future<void> removeMember(int conversationId, int targetId) async {
    final response = await http.delete(
        Uri.parse('$_base/$conversationId/members/$targetId'),
        headers: await _headers());
    if (response.statusCode != 200) throw Exception(_errorOf(response));
  }

  static Future<void> changeRole(
      int conversationId, int targetId, String role) async {
    final response = await http.put(
      Uri.parse('$_base/$conversationId/members/$targetId/role'),
      headers: await _headers(),
      body: jsonEncode({'role': role}),
    );
    if (response.statusCode != 200) throw Exception(_errorOf(response));
  }

  static Future<void> transferOwnership(
      int conversationId, int newOwnerId) async {
    final response = await http.put(
      Uri.parse('$_base/$conversationId/transfer-owner'),
      headers: await _headers(),
      body: jsonEncode({'newOwnerId': newOwnerId}),
    );
    if (response.statusCode != 200) throw Exception(_errorOf(response));
  }

  static Future<void> leaveGroup(int conversationId) async {
    final response = await http.post(Uri.parse('$_base/$conversationId/leave'),
        headers: await _headers());
    if (response.statusCode != 200) throw Exception(_errorOf(response));
  }

  static Future<GroupSummary> updateInfo(
    int conversationId, {
    String? name,
    String? description,
  }) async {
    final response = await http.put(
      Uri.parse('$_base/$conversationId/info'),
      headers: await _headers(),
      body: jsonEncode({
        if (name != null) 'name': name,
        if (description != null) 'description': description,
      }),
    );
    if (response.statusCode != 200) throw Exception(_errorOf(response));
    return GroupSummary.fromJson(jsonDecode(response.body));
  }

  // ---------------- G4: reply / react / pin / delete / search ----------------

  /// Toggle a reaction on a message (same key removes it).
  static Future<void> reactToMessage(int messageId, String? reaction) async {
    final response = await http.post(
      Uri.parse('$_base/messages/$messageId/reaction'),
      headers: await _headers(),
      body: jsonEncode({'reaction': reaction ?? ''}),
    );
    if (response.statusCode != 200) throw Exception(_errorOf(response));
  }

  /// Who reacted, and with what.
  static Future<List<Map<String, dynamic>>> fetchMessageReactions(
      int messageId) async {
    final response = await http.get(
        Uri.parse('$_base/messages/$messageId/reactions'),
        headers: await _headers());
    if (response.statusCode != 200) throw Exception(_errorOf(response));
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  static Future<void> setPinned(int messageId, bool pinned) async {
    final response = await http.put(
      Uri.parse('$_base/messages/$messageId/pin'),
      headers: await _headers(),
      body: jsonEncode({'pinned': pinned}),
    );
    if (response.statusCode != 200) throw Exception(_errorOf(response));
  }

  static Future<List<Message>> fetchPinned(int conversationId) async {
    final response = await http.get(
        Uri.parse('$_base/$conversationId/pinned'),
        headers: await _headers());
    if (response.statusCode != 200) throw Exception(_errorOf(response));
    return (jsonDecode(response.body) as List)
        .map((e) => Message.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Delete for everyone (own message, or any message if you moderate).
  static Future<void> deleteMessage(int messageId) async {
    final response = await http.delete(
        Uri.parse('$_base/messages/$messageId'),
        headers: await _headers());
    if (response.statusCode != 200) throw Exception(_errorOf(response));
  }

  static Future<List<Message>> searchMessages(
      int conversationId, String query) async {
    final response = await http.get(
      Uri.parse('$_base/$conversationId/search?q=${Uri.encodeQueryComponent(query)}'),
      headers: await _headers(),
    );
    if (response.statusCode != 200) throw Exception(_errorOf(response));
    return (jsonDecode(response.body) as List)
        .map((e) => Message.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // ---------------- G5: permissions / invites / requests / notifications ----------------

  static Future<GroupSummary> updatePermissions(
    int conversationId, {
    String? whoCanSend,
    String? whoCanEditInfo,
    String? whoCanAddMembers,
    String? whoCanPin,
    bool? approveNewMembers,
  }) async {
    final response = await http.put(
      Uri.parse('$_base/$conversationId/permissions'),
      headers: await _headers(),
      body: jsonEncode({
        if (whoCanSend != null) 'whoCanSend': whoCanSend,
        if (whoCanEditInfo != null) 'whoCanEditInfo': whoCanEditInfo,
        if (whoCanAddMembers != null) 'whoCanAddMembers': whoCanAddMembers,
        if (whoCanPin != null) 'whoCanPin': whoCanPin,
        if (approveNewMembers != null) 'approveNewMembers': approveNewMembers,
      }),
    );
    if (response.statusCode != 200) throw Exception(_errorOf(response));
    return GroupSummary.fromJson(jsonDecode(response.body));
  }

  /// Current invite code (created on first call).
  static Future<String> fetchInviteCode(int conversationId) async {
    final response = await http.get(Uri.parse('$_base/$conversationId/invite'),
        headers: await _headers());
    if (response.statusCode != 200) throw Exception(_errorOf(response));
    return (jsonDecode(response.body) as Map<String, dynamic>)['code'].toString();
  }

  static Future<String> resetInviteCode(int conversationId) async {
    final response = await http.post(
        Uri.parse('$_base/$conversationId/invite/reset'),
        headers: await _headers());
    if (response.statusCode != 200) throw Exception(_errorOf(response));
    return (jsonDecode(response.body) as Map<String, dynamic>)['code'].toString();
  }

  /// Join via code. Returns JOINED / REQUESTED / ALREADY_MEMBER.
  static Future<String> joinByInvite(String code) async {
    final response = await http.post(Uri.parse('$_base/invite/$code/join'),
        headers: await _headers());
    if (response.statusCode != 200) throw Exception(_errorOf(response));
    return (jsonDecode(response.body) as Map<String, dynamic>)['result'].toString();
  }

  static Future<List<GroupMember>> fetchJoinRequests(int conversationId) async {
    final response = await http.get(
        Uri.parse('$_base/$conversationId/join-requests'),
        headers: await _headers());
    if (response.statusCode != 200) throw Exception(_errorOf(response));
    return (jsonDecode(response.body) as List)
        .map((e) => GroupMember.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> decideJoinRequest(
      int conversationId, int userId, bool accept) async {
    final response = await http.post(
      Uri.parse('$_base/$conversationId/join-requests/$userId'),
      headers: await _headers(),
      body: jsonEncode({'accept': accept}),
    );
    if (response.statusCode != 200) throw Exception(_errorOf(response));
  }

  static Future<void> setNotifications(int conversationId,
      {String? level, int? muteHours}) async {
    final response = await http.put(
      Uri.parse('$_base/$conversationId/notifications'),
      headers: await _headers(),
      body: jsonEncode({
        if (level != null) 'level': level,
        if (muteHours != null) 'muteHours': muteHours,
      }),
    );
    if (response.statusCode != 200) throw Exception(_errorOf(response));
  }

  // ---------------- G3: group ban (separate from personal block) ----------------

  /// Ban = remove + prevent rejoin. Distinct from [removeMember].
  static Future<void> banMember(int conversationId, int targetId,
      {String? reason}) async {
    final response = await http.post(
      Uri.parse('$_base/$conversationId/bans/$targetId'),
      headers: await _headers(),
      body: jsonEncode({if (reason != null) 'reason': reason}),
    );
    if (response.statusCode != 200) throw Exception(_errorOf(response));
  }

  /// Lift a ban. Does NOT re-add the user - they must be invited again.
  static Future<void> unbanMember(int conversationId, int targetId) async {
    final response = await http.delete(
        Uri.parse('$_base/$conversationId/bans/$targetId'),
        headers: await _headers());
    if (response.statusCode != 200) throw Exception(_errorOf(response));
  }

  static Future<List<GroupMember>> fetchBans(int conversationId) async {
    final response = await http.get(Uri.parse('$_base/$conversationId/bans'),
        headers: await _headers());
    if (response.statusCode != 200) {
      throw Exception('Failed to load bans (${response.statusCode})');
    }
    return (jsonDecode(response.body) as List)
        .map((e) => GroupMember.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// GAP-3: copy a message into another conversation.
  static Future<Message> forwardMessage(
      int messageId, int targetConversationId) async {
    final response = await http.post(
      Uri.parse('$_base/messages/$messageId/forward'),
      headers: await _headers(),
      body: jsonEncode({'targetConversationId': targetConversationId}),
    );
    if (response.statusCode != 200) throw Exception(_errorOf(response));
    return Message.fromJson(jsonDecode(response.body));
  }

  /// Surface the backend's permission message ("Admins only", etc.) verbatim.
  static String _errorOf(http.Response response) {
    try {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return body['error']?.toString() ?? 'Action failed';
    } catch (_) {
      return 'Action failed';
    }
  }

  static Future<Message> sendMessage(
    int conversationId, {
    required String content,
    String? clientMessageId,
    int? replyToMessageId,
    String? mediaUrl,
    String? mediaType,
    String? mediaName,
  }) async {
    final response = await http.post(
      Uri.parse('$_base/$conversationId/messages'),
      headers: await _headers(),
      body: jsonEncode({
        'content': content,
        if (clientMessageId != null) 'clientMessageId': clientMessageId,
        if (replyToMessageId != null) 'replyToMessageId': replyToMessageId,
        if (mediaUrl != null) 'mediaUrl': mediaUrl,
        if (mediaType != null) 'mediaType': mediaType,
        if (mediaName != null) 'mediaName': mediaName,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Failed to send (${response.statusCode})');
    }
    return Message.fromJson(jsonDecode(response.body));
  }
}
