import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';

/// Models for SQLite persistence (different from API models)
class SQLiteMessage {
  final int? id;
  final String? clientMessageId;
  final int chatId;
  final int senderId;
  final int receiverId;
  final String content;
  final int createdAt;
  final int? readAt;  // ✅ NEW: Read timestamp (null if not read)
  final String status; // SENDING, SENT, DELIVERED, READ

  SQLiteMessage({
    this.id,
    this.clientMessageId,
    required this.chatId,
    required this.senderId,
    required this.receiverId,
    required this.content,
    required this.createdAt,
    this.readAt,  // ✅ NEW
    required this.status,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'client_message_id': clientMessageId,
      'chat_id': chatId,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'content': content,
      'created_at': createdAt,
      'read_at': readAt,  // ✅ FIXED: Include readAt in map
      'status': status,
    };
  }
}

class SQLiteConversation {
  final int chatId;
  final int otherUserId;
  final String? otherUserName;
  final String? otherUserProfilePic;
  final String? lastMessage;
  final int? lastMessageTime;
  final int unreadCount;

  SQLiteConversation({
    required this.chatId,
    required this.otherUserId,
    this.otherUserName,
    this.otherUserProfilePic,
    this.lastMessage,
    this.lastMessageTime,
    required this.unreadCount,
  });

  Map<String, dynamic> toMap() {
    return {
      'chat_id': chatId,
      'other_user_id': otherUserId,
      'other_user_name': otherUserName,
      'other_user_profile_pic': otherUserProfilePic,
      'last_message': lastMessage,
      'last_message_time': lastMessageTime,
      'unread_count': unreadCount,
    };
  }
}

/// LocalChatRepository - WRITE-ONLY repository for SQLite
/// 
/// RULE: This repository is ONLY called AFTER realtime logic completes.
/// It has NO listeners, streams, or business logic.
/// It is ONLY responsible for persisting final state.
class LocalChatRepository {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  /// Insert a message into SQLite (called after message sent/received)
  Future<void> insertMessage(SQLiteMessage message) async {
    try {
      final db = await _dbHelper.database;
      await db.insert(
        'messages',
        message.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      print(
          '[LOCAL_REPO] ✅ Message saved: clientId=${message.clientMessageId}, status=${message.status}');
    } catch (e) {
      print('[LOCAL_REPO] ❌ Error saving message: $e');
    }
  }

  /// Update message status (SENDING → SENT → READ)
  /// Called when server ACK received or message marked as read
  Future<void> updateMessageStatus(
    String clientMessageId,
    String newStatus,
  ) async {
    try {
      final db = await _dbHelper.database;
      await db.update(
        'messages',
        {'status': newStatus},
        where: 'client_message_id = ?',
        whereArgs: [clientMessageId],
      );
      print(
          '[LOCAL_REPO] ✅ Message status updated: clientId=$clientMessageId, status=$newStatus');
    } catch (e) {
      print('[LOCAL_REPO] ❌ Error updating message status: $e');
    }
  }

  /// ✅ NEW: Update message read status with timestamp (for SQLite persistence)
  /// Called when message is marked as read in ChatStore
  Future<void> updateMessageReadStatus(int serverId, int readAtMs) async {
    try {
      final db = await _dbHelper.database;
      await db.update(
        'messages',
        {
          'status': 'READ',
          'read_at': readAtMs,
        },
        where: 'id = ?',
        whereArgs: [serverId],
      );
      print('[LOCAL_REPO] ✅ Message read status updated: id=$serverId, read_at=$readAtMs');
    } catch (e) {
      print('[LOCAL_REPO] ❌ Error updating message read status: $e');
    }
  }

  /// Insert or update conversation metadata
  Future<void> upsertConversation(SQLiteConversation conversation) async {
    try {
      final db = await _dbHelper.database;
      await db.insert(
        'conversations',
        conversation.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      print(
          '[LOCAL_REPO] ✅ Conversation saved: chatId=${conversation.chatId}, unread=${conversation.unreadCount}');
    } catch (e) {
      print('[LOCAL_REPO] ❌ Error saving conversation: $e');
    }
  }

  /// Ensure conversation exists (create with minimal data if needed)
  Future<void> ensureConversationExists(int chatId) async {
    try {
      final db = await _dbHelper.database;
      final existing = await db.query(
        'conversations',
        where: 'chat_id = ?',
        whereArgs: [chatId],
      );
      
      if (existing.isEmpty) {
        // Create minimal conversation record
        await db.insert(
          'conversations',
          {
            'chat_id': chatId,
            'other_user_id': chatId,
            'other_user_name': null,
            'other_user_profile_pic': null,
            'last_message': null,
            'last_message_time': DateTime.now().millisecondsSinceEpoch,
            'unread_count': 0,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        print('[LOCAL_REPO] ✅ Created minimal conversation: chatId=$chatId');
      }
    } catch (e) {
      print('[LOCAL_REPO] Error ensuring conversation exists: $e');
    }
  }

  /// Update last message and timestamp
  Future<void> updateConversationLastMessage(
    int chatId,
    String? message,
    int timestamp,
  ) async {
    try {
      final db = await _dbHelper.database;
      await db.update(
        'conversations',
        {
          'last_message': message,
          'last_message_time': timestamp,
        },
        where: 'chat_id = ?',
        whereArgs: [chatId],
      );
      print('[LOCAL_REPO] ✅ Conversation updated: chatId=$chatId');
    } catch (e) {
      print('[LOCAL_REPO] ❌ Error updating conversation: $e');
    }
  }

  /// Update unread count
  Future<void> setUnreadCount(int chatId, int count) async {
    try {
      final db = await _dbHelper.database;
      await db.update(
        'conversations',
        {'unread_count': count},
        where: 'chat_id = ?',
        whereArgs: [chatId],
      );
      print(
          '[LOCAL_REPO] ✅ Unread count updated: chatId=$chatId, count=$count');
    } catch (e) {
      print('[LOCAL_REPO] ❌ Error updating unread count: $e');
    }
  }

  /// Load all messages from SQLite (called only on app startup)
  Future<List<SQLiteMessage>> loadAllMessages() async {
    try {
      final db = await _dbHelper.database;
      final maps = await db.query('messages', orderBy: 'created_at DESC');

      final messages = maps
          .map((map) => SQLiteMessage(
                id: map['id'] as int?,
                clientMessageId: map['client_message_id'] as String?,
                chatId: map['chat_id'] as int,
                senderId: map['sender_id'] as int,
                receiverId: map['receiver_id'] as int,
                content: map['content'] as String,
                createdAt: map['created_at'] as int,
                readAt: map['read_at'] as int?,  // ✅ NEW: Load actual readAt timestamp
                status: map['status'] as String,
              ))
          .toList();

      print('[LOCAL_REPO] ✅ Loaded ${messages.length} messages from SQLite');
      return messages;
    } catch (e) {
      print('[LOCAL_REPO] ❌ Error loading messages: $e');
      return [];
    }
  }

  /// Load all conversations from SQLite (called only on app startup)
  Future<List<SQLiteConversation>> loadAllConversations() async {
    try {
      final db = await _dbHelper.database;
      final maps =
          await db.query('conversations', orderBy: 'last_message_time DESC');

      final conversations = maps
          .map((map) => SQLiteConversation(
                chatId: map['chat_id'] as int,
                otherUserId: map['other_user_id'] as int,
                otherUserName: map['other_user_name'] as String?,
                otherUserProfilePic: map['other_user_profile_pic'] as String?,
                lastMessage: map['last_message'] as String?,
                lastMessageTime: map['last_message_time'] as int?,
                unreadCount: map['unread_count'] as int? ?? 0,
              ))
          .toList();

      print(
          '[LOCAL_REPO] ✅ Loaded ${conversations.length} conversations from SQLite');
      return conversations;
    } catch (e) {
      print('[LOCAL_REPO] ❌ Error loading conversations: $e');
      return [];
    }
  }

  /// Get messages for a specific chat (called only on app startup)
  Future<List<SQLiteMessage>> loadMessagesForChat(int chatId) async {
    try {
      final db = await _dbHelper.database;
      final maps = await db.query(
        'messages',
        where: 'chat_id = ?',
        whereArgs: [chatId],
        orderBy: 'created_at DESC',
      );

      return maps
          .map((map) => SQLiteMessage(
                id: map['id'] as int?,
                clientMessageId: map['client_message_id'] as String?,
                chatId: map['chat_id'] as int,
                senderId: map['sender_id'] as int,
                receiverId: map['receiver_id'] as int,
                content: map['content'] as String,
                createdAt: map['created_at'] as int,
                status: map['status'] as String,
              ))
          .toList();
    } catch (e) {
      print('[LOCAL_REPO] ❌ Error loading messages for chat $chatId: $e');
      return [];
    }
  }
}
