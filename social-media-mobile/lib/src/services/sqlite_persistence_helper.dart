import 'dart:async';
import '../models/message.dart';
import '../database/local_chat_repository.dart';

/// SQLitePersistenceHelper - PASSIVE write-behind cache
/// 
/// This helper does ONE job ONLY:
/// Listen to existing realtime streams and save final state to SQLite.
/// 
/// ARCHITECTURE:
/// Realtime Logic (ChatService) → Streams → UI + SQLite (passively)
/// 
/// This service:
/// ✅ Has NO business logic
/// ✅ Has NO control flow
/// ✅ Has NO listeners or streams of its own
/// ✅ ONLY writes to SQLite after realtime logic completes
/// ✅ Can be removed without breaking realtime features
class SQLitePersistenceHelper {
  static final SQLitePersistenceHelper _instance =
      SQLitePersistenceHelper._internal();

  final LocalChatRepository _repo = LocalChatRepository();
  final List<StreamSubscription> _subscriptions = [];

  factory SQLitePersistenceHelper() {
    return _instance;
  }

  SQLitePersistenceHelper._internal() {
    print('[SQLITE_HELPER] Initialized (write-behind cache)');
  }

  /// Attach to existing ChatService streams
  /// Call this ONCE during app initialization
  void attachToChatService(
    Stream<Message> messageStream,
    Stream<dynamic> readReceiptStream,
  ) {
    print('[SQLITE_HELPER] Attaching to ChatService streams...');

    // Listen to message stream and save to SQLite AFTER realtime logic
    _subscriptions.add(
      messageStream.listen(
        (message) {
          _persistMessage(message);
        },
        onError: (error) {
          print('[SQLITE_HELPER] Error on message stream: $error');
        },
      ),
    );

    // Listen to read receipt stream
    _subscriptions.add(
      readReceiptStream.listen(
        (receipt) {
          _persistReadReceipt(receipt);
        },
        onError: (error) {
          print('[SQLITE_HELPER] Error on read receipt stream: $error');
        },
      ),
    );

    print('[SQLITE_HELPER] ✅ Attached to all streams (passive listening)');
  }

  /// Save message to SQLite (called from stream listener)
  void _persistMessage(Message message) {
    try {
      // Use stable chatId that matches how loader filters messages
      // Always use smaller ID for consistent grouping
      final chatId = message.senderId < message.recipientId 
          ? message.senderId 
          : message.recipientId;
      
      final sqliteMsg = SQLiteMessage(
        clientMessageId: message.clientMessageId,
        chatId: chatId,
        senderId: message.senderId,
        receiverId: message.recipientId,
        content: message.content,
        createdAt: message.createdAt.millisecondsSinceEpoch,
        readAt: message.readAt?.millisecondsSinceEpoch,  // ✅ FIXED: Persist actual readAt
        status: _statusToString(message.status),
      );

      _repo.insertMessage(sqliteMsg);

      // ✅ FIXED: Create conversation if it doesn't exist
      _ensureConversationExists(chatId);

      // Also update conversation metadata
      _updateConversationLastMessage(
        chatId: chatId,
        message: message.content,
        timestamp: message.createdAt.millisecondsSinceEpoch,
      );
    } catch (e) {
      print('[SQLITE_HELPER] Error persisting message: $e');
    }
  }

  /// Save read receipt to SQLite
  void _persistReadReceipt(dynamic receipt) {
    try {
      // receipt is a ReadReceipt object
      if (receipt.runtimeType.toString().contains('ReadReceipt')) {
        final messageIds = receipt.messageIds as List<int>?;
        if (messageIds != null && messageIds.isNotEmpty) {
          for (int msgId in messageIds) {
            _repo.updateMessageStatus('$msgId', 'READ');
          }
        }
      }
    } catch (e) {
      print('[SQLITE_HELPER] Error persisting read receipt: $e');
    }
  }

  /// Ensure conversation exists in SQLite (create if needed)
  void _ensureConversationExists(int chatId) {
    try {
      _repo.ensureConversationExists(chatId);
    } catch (e) {
      print('[SQLITE_HELPER] Error ensuring conversation exists: $e');
    }
  }

  /// Update conversation last message (or create if it doesn't exist)
  void _updateConversationLastMessage({
    required int chatId,
    required String message,
    required int timestamp,
  }) {
    try {
      // ✅ FIX: Ensure conversation exists before updating
      final conv = SQLiteConversation(
        chatId: chatId,
        otherUserId: chatId,  // chatId is otherUserId in this context
        otherUserName: null,
        otherUserProfilePic: null,
        lastMessage: message,
        lastMessageTime: timestamp,
        unreadCount: 0,
      );
      _repo.upsertConversation(conv);
    } catch (e) {
      print('[SQLITE_HELPER] Error upserting conversation: $e');
    }
  }

  /// Update message status when server ACKs
  void updateMessageStatus(String clientMessageId, MessageStatus status) {
    try {
      _repo.updateMessageStatus(clientMessageId, _statusToString(status));
    } catch (e) {
      print('[SQLITE_HELPER] Error updating message status: $e');
    }
  }

  /// Create or update conversation
  void saveConversation({
    required int chatId,
    required int otherUserId,
    String? otherUserName,
    String? otherUserProfilePic,
    String? lastMessage,
    int? lastMessageTime,
    required int unreadCount,
  }) {
    try {
      final conv = SQLiteConversation(
        chatId: chatId,
        otherUserId: otherUserId,
        otherUserName: otherUserName,
        otherUserProfilePic: otherUserProfilePic,
        lastMessage: lastMessage,
        lastMessageTime: lastMessageTime,
        unreadCount: unreadCount,
      );

      _repo.upsertConversation(conv);
    } catch (e) {
      print('[SQLITE_HELPER] Error saving conversation: $e');
    }
  }

  /// Helper to convert MessageStatus enum to string
  String _statusToString(MessageStatus status) {
    switch (status) {
      case MessageStatus.sending:
        return 'SENDING';
      case MessageStatus.sent:
        return 'SENT';
      case MessageStatus.read:
        return 'READ';
      case MessageStatus.uploading:
        return 'UPLOADING';
      case MessageStatus.failed:
        return 'FAILED';
    }
  }

  /// Cleanup on app shutdown
  void dispose() {
    print('[SQLITE_HELPER] Cleaning up...');
    for (var subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
    print('[SQLITE_HELPER] ✅ Cleaned up');
  }
}
