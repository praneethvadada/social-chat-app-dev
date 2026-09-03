import 'package:flutter/foundation.dart' show kIsWeb;

import '../models/group.dart';
import '../models/message.dart';
import '../database/local_chat_repository.dart';
import '../state/chat_store.dart';
import 'api_service.dart';
import 'group_api.dart';
import 'sqlite_persistence_helper.dart';

/// Phase 4: catches up on messages that arrived while this device was
/// offline or the app wasn't running. Called on every WebSocket connect
/// (initial connect AND every reconnect) from ChatWebSocketService.
///
/// A conversation synced before uses the cheap incremental delta
/// (GroupApi.sync, cursor-based); a conversation never synced before falls
/// back to the existing full-history fetch ONE time and seeds its cursor
/// from what that returns, so every sync after the first is incremental.
/// Mobile-only (kIsWeb guard) - matches local storage being mobile-only
/// everywhere else in the app.
///
/// GROUP conversations (Phase 4's own flagged gap, closed here): the local
/// `messages`/`conversations`/`sync_state` tables key everything by a single
/// integer "chat_id" column that, for DIRECT chats, is `min(senderId,
/// recipientId)` - a real user id, always positive. A group's real backend
/// conversationId comes from the SAME auto-increment sequence as those user
/// ids (see G0/G1), so using it as-is would risk colliding with an unrelated
/// DIRECT chat's chat_id (e.g. group id 5 colliding with the DIRECT chat_id
/// derived from user 5). Negating it (`-group.id`) guarantees zero collision
/// (DIRECT chat_ids are always positive) while staying trivially invertible
/// for the real API calls, which always use the true (positive) group id.
/// `conversations.other_user_id`/`messages.receiver_id` (both NOT NULL,
/// meaningless for a broadcast/no-single-other-party GROUP row) get `0` as
/// a sentinel - `0` is never a real user id in this system (auto-increment
/// PKs start at 1). Unlike DIRECT, GROUP has no live-WebSocket-driven writer
/// for its local `conversations` row (GroupChatScreen manages its own
/// in-memory state independently, not through ChatStore/SQLitePersistence-
/// Helper) - this sync path is the SOLE writer for GROUP's local cache, so
/// it upserts real metadata (name/photo/last message/unread) from
/// GroupSummary each pass, not just a bare placeholder row.
class ChatSyncService {
  final LocalChatRepository _repo = LocalChatRepository();

  Future<void> syncAll(ChatStore chatStore, int currentUserId) async {
    if (kIsWeb) return;

    List<Conversation> conversations = [];
    try {
      conversations = await ApiService.getConversations();
    } catch (e) {
      print('[CHAT_SYNC] ❌ Error fetching conversations to sync: $e');
      // Don't abort — a DIRECT-fetch failure shouldn't block GROUP sync below.
    }

    for (final conv in conversations) {
      try {
        await _syncOne(conv, chatStore, currentUserId);
      } catch (e) {
        print('[CHAT_SYNC] ⚠️ Error syncing conversation with user=${conv.userId}: $e');
      }
    }

    List<GroupSummary> groups = [];
    try {
      groups = await GroupApi.fetchMyGroups();
    } catch (e) {
      print('[CHAT_SYNC] ❌ Error fetching groups to sync: $e');
    }

    for (final group in groups) {
      try {
        await _syncOneGroup(group);
      } catch (e) {
        print('[CHAT_SYNC] ⚠️ Error syncing group=${group.id}: $e');
      }
    }
  }

  /// Negative-namespaced local chat_id for a GROUP conversation — see this
  /// class's own doc comment for why.
  int _groupChatId(int groupConversationId) => -groupConversationId;

  Future<void> _syncOneGroup(GroupSummary group) async {
    final chatId = _groupChatId(group.id);

    // Sole local writer for GROUP conversation rows (see class doc comment)
    // — upsert real, fresh metadata every sync pass, not just a placeholder.
    await _repo.upsertConversation(SQLiteConversation(
      chatId: chatId,
      otherUserId: 0, // sentinel: no single "other user" for a group
      otherUserName: group.name,
      otherUserProfilePic: group.photoUrl,
      lastMessage: group.lastMessageContent,
      lastMessageTime: group.lastMessageTime?.millisecondsSinceEpoch,
      unreadCount: group.unreadCount,
      conversationType: 'GROUP',
    ));

    final state = await _repo.getSyncState(chatId);
    final cursorStr = state?['last_sync_cursor'] as String?;
    final cursor = cursorStr != null ? int.tryParse(cursorStr) : null;

    if (cursor == null) {
      // Never synced this group locally before — seed with the most recent
      // page rather than DIRECT's unbounded full-history fetch (GroupApi's
      // history endpoint is page-based, not a single full-history call).
      final newestId = await _fullFetchGroup(group, chatId);
      if (newestId != null) {
        await _repo.setSyncState(chatId, cursor: newestId.toString());
      }
      return;
    }

    int currentCursor = cursor;
    while (true) {
      final delta = await GroupApi.sync(group.id, currentCursor);
      for (final msg in delta.messages) {
        await _saveGroupMessageToSQLite(msg, chatId);
      }
      if (delta.messages.isNotEmpty || delta.nextCursor != currentCursor) {
        currentCursor = delta.nextCursor;
        await _repo.setSyncState(chatId, cursor: currentCursor.toString());
      }
      if (!delta.hasMore) break;
    }
  }

  /// One-time seed fetch for a group with no prior local cursor — most
  /// recent page only (GroupApi.fetchMessages is page-based, unlike
  /// DIRECT's single unbounded full-history call). Returns the highest
  /// message id seen, to seed the cursor, or null if there's no history yet.
  Future<int?> _fullFetchGroup(GroupSummary group, int chatId) async {
    final messages = await GroupApi.fetchMessages(group.id);
    if (messages.isEmpty) return null;

    int? newestId;
    for (final msg in messages) {
      await _saveGroupMessageToSQLite(msg, chatId);
      if (newestId == null || msg.id > newestId) newestId = msg.id;
    }
    print('[CHAT_SYNC] ✅ Full-fetched ${messages.length} messages for group=${group.id}, cursor seeded at $newestId');
    return newestId;
  }

  Future<void> _saveGroupMessageToSQLite(Message msg, int chatId) async {
    try {
      final sqliteMsg = SQLiteMessage(
        id: msg.id,
        clientMessageId: msg.clientMessageId,
        chatId: chatId,
        senderId: msg.senderId,
        receiverId: 0, // sentinel: a group message has no single receiver (broadcast)
        content: msg.content,
        createdAt: msg.createdAt.millisecondsSinceEpoch,
        readAt: msg.readAt?.millisecondsSinceEpoch,
        status: _messageStatusToString(msg.status),
        mediaUrl: msg.mediaUrl,
        mediaType: msg.mediaType,
        mediaName: msg.mediaName,
        replyToMessageId: msg.replyToMessageId,
        isDeleted: msg.isDeleted,
      );
      await _repo.insertMessage(sqliteMsg);
    } catch (e) {
      print('[CHAT_SYNC] Error saving group message to SQLite: $e');
    }
  }

  Future<void> _syncOne(Conversation conv, ChatStore chatStore, int currentUserId) async {
    final chatId = conv.userId;

    if (conv.conversationId == null) {
      // Legacy conversation predating G0's conversationId stamping - no key
      // to sync incrementally off. One-off full fetch, same as before Phase 4.
      await _fullFetch(conv, chatStore, currentUserId);
      return;
    }

    final state = await _repo.getSyncState(chatId);
    final cursorStr = state?['last_sync_cursor'] as String?;
    final cursor = cursorStr != null ? int.tryParse(cursorStr) : null;

    if (cursor == null) {
      // Never synced this conversation before.
      final newestId = await _fullFetch(conv, chatStore, currentUserId);
      if (newestId != null) {
        await _repo.setSyncState(chatId, cursor: newestId.toString());
      }
      return;
    }

    // Already have a cursor - ask only for what's new since then. Loop in
    // case the delta was capped (hasMore) so a long offline gap gets fully
    // caught up in one sync pass rather than one page per reconnect.
    int currentCursor = cursor;
    while (true) {
      final delta = await GroupApi.sync(conv.conversationId!, currentCursor);
      for (final msg in delta.messages) {
        await _saveSingleMessageToSQLite(msg, currentUserId);
        chatStore.addIncomingMessage(msg, currentUserId);
      }
      if (delta.messages.isNotEmpty || delta.nextCursor != currentCursor) {
        currentCursor = delta.nextCursor;
        await _repo.setSyncState(chatId, cursor: currentCursor.toString());
      }
      if (!delta.hasMore) break;
    }
  }

  /// One-time full history fetch for a conversation with no prior cursor.
  /// Returns the highest message id seen, to seed the cursor - or null if
  /// there were no messages to seed from.
  Future<int?> _fullFetch(Conversation conv, ChatStore chatStore, int currentUserId) async {
    final messageHistory = await ApiService.getConversation(conv.userId);
    if (messageHistory.isEmpty) return null;

    final messages = messageHistory.map((json) => Message.fromJson(json)).toList();
    int? newestId;
    for (final msg in messages) {
      await _saveSingleMessageToSQLite(msg, currentUserId);
      if (newestId == null || msg.id > newestId) newestId = msg.id;
    }
    chatStore.loadConversationFromSQLite(conv.userId, messages);
    print('[CHAT_SYNC] ✅ Full-fetched ${messages.length} messages for user=${conv.userId}, cursor seeded at $newestId');
    return newestId;
  }

  Future<void> _saveSingleMessageToSQLite(Message msg, int currentUserId) async {
    try {
      final chatId = msg.senderId < msg.recipientId ? msg.senderId : msg.recipientId;

      final sqliteMsg = SQLiteMessage(
        id: msg.id,
        clientMessageId: msg.clientMessageId,
        chatId: chatId,
        senderId: msg.senderId,
        receiverId: msg.recipientId,
        content: msg.content,
        createdAt: msg.createdAt.millisecondsSinceEpoch,
        readAt: msg.readAt?.millisecondsSinceEpoch,
        status: _messageStatusToString(msg.status),
        mediaUrl: msg.mediaUrl,
        mediaType: msg.mediaType,
        mediaName: msg.mediaName,
        replyToMessageId: msg.replyToMessageId,
        isDeleted: msg.isDeleted,
      );

      await _repo.insertMessage(sqliteMsg);
      await _repo.ensureConversationExists(chatId);
    } catch (e) {
      print('[CHAT_SYNC] Error saving message to SQLite: $e');
    }
  }

  String _messageStatusToString(MessageStatus status) {
    switch (status) {
      case MessageStatus.sending:
        return 'SENDING';
      case MessageStatus.sent:
        return 'SENT';
      case MessageStatus.delivered:
        return 'DELIVERED';
      case MessageStatus.read:
        return 'READ';
      case MessageStatus.uploading:
        return 'SENDING';
      case MessageStatus.failed:
        return 'FAILED';
    }
  }
}
