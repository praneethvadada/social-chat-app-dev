import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/message.dart';

/// Persistence layer for chat messages using SharedPreferences
/// This provides a lightweight local cache for messages to survive app restarts
class MessagePersistenceService {
  static final MessagePersistenceService _instance =
      MessagePersistenceService._internal();

  late SharedPreferences _prefs;
  bool _initialized = false;

  // Storage key prefix for messages
  static const String _messageKeyPrefix = 'messages_';
  static const String _conversationListKey = 'conversation_list';

  factory MessagePersistenceService() {
    return _instance;
  }

  MessagePersistenceService._internal();

  /// Initialize SharedPreferences
  Future<void> initialize() async {
    if (_initialized) return;

    _prefs = await SharedPreferences.getInstance();
    _initialized = true;
    print('[PERSISTENCE] Initialized');
  }

  /// Ensure initialized
  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await initialize();
    }
  }

  /// Save a message for a specific conversation
  Future<void> saveMessage(Message msg, int otherUserId) async {
    await _ensureInitialized();

    try {
      final conversationKey = _messageKeyPrefix + otherUserId.toString();
      final existing = _prefs.getStringList(conversationKey) ?? [];

      // Serialize message to JSON
      final msgJson = jsonEncode(msg.toJson());

      // Check if message already exists (by id or clientMessageId)
      final filtered = existing.where((m) {
        try {
          final decoded = jsonDecode(m) as Map<String, dynamic>;
          final msgId = decoded['id'] as int?;
          final clientId = decoded['clientMessageId'] as String?;

          // Remove if same server id or client id
          if (msgId != null && msgId == msg.id && msg.id != 0) return false;
          if (clientId != null && clientId == msg.clientMessageId) return false;
          return true;
        } catch (_) {
          return true;
        }
      }).toList();

      // Add new message
      filtered.add(msgJson);

      // Keep only last 500 messages per conversation
      final limited =
          filtered.length > 500 ? filtered.sublist(filtered.length - 500) : filtered;

      await _prefs.setStringList(conversationKey, limited);

      // Update conversation list
      await _updateConversationList(otherUserId);

      print('[PERSISTENCE] Saved message for user=$otherUserId (total: ${limited.length})');
    } catch (e) {
      print('[PERSISTENCE] Error saving message: $e');
    }
  }

  /// Get all messages for a conversation
  Future<List<Message>> getMessagesForUser(int otherUserId, int currentUserId) async {
    await _ensureInitialized();

    try {
      final conversationKey = _messageKeyPrefix + otherUserId.toString();
      final stored = _prefs.getStringList(conversationKey) ?? [];

      final messages = <Message>[];
      for (final msgJson in stored) {
        try {
          final decoded = jsonDecode(msgJson) as Map<String, dynamic>;
          final msg = Message.fromJson(decoded);
          messages.add(msg);
        } catch (e) {
          print('[PERSISTENCE] Error parsing message: $e');
        }
      }

      // Sort by createdAt ascending
      messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      print('[PERSISTENCE] Loaded ${messages.length} cached messages for user=$otherUserId');
      return messages;
    } catch (e) {
      print('[PERSISTENCE] Error loading messages: $e');
      return [];
    }
  }

  /// Get list of all conversations
  Future<List<int>> getConversationList() async {
    await _ensureInitialized();

    try {
      final stored = _prefs.getStringList(_conversationListKey) ?? [];
      return stored.map((s) {
        try {
          return int.parse(s);
        } catch (_) {
          return 0;
        }
      }).where((id) => id != 0).toList();
    } catch (e) {
      print('[PERSISTENCE] Error loading conversation list: $e');
      return [];
    }
  }

  /// Update conversation list with new conversation
  Future<void> _updateConversationList(int otherUserId) async {
    try {
      final list = _prefs.getStringList(_conversationListKey) ?? [];
      final userIdStr = otherUserId.toString();

      if (!list.contains(userIdStr)) {
        list.add(userIdStr);
        await _prefs.setStringList(_conversationListKey, list);
      }
    } catch (e) {
      print('[PERSISTENCE] Error updating conversation list: $e');
    }
  }

  /// Clear messages for a conversation
  Future<void> clearConversation(int otherUserId) async {
    await _ensureInitialized();

    try {
      final conversationKey = _messageKeyPrefix + otherUserId.toString();
      await _prefs.remove(conversationKey);
      print('[PERSISTENCE] Cleared conversation with user=$otherUserId');
    } catch (e) {
      print('[PERSISTENCE] Error clearing conversation: $e');
    }
  }

  /// Clear all messages
  Future<void> clearAll() async {
    await _ensureInitialized();

    try {
      final keys = _prefs.getKeys();
      for (final key in keys) {
        if (key.startsWith(_messageKeyPrefix)) {
          await _prefs.remove(key);
        }
      }
      await _prefs.remove(_conversationListKey);
      print('[PERSISTENCE] All messages cleared');
    } catch (e) {
      print('[PERSISTENCE] Error clearing all: $e');
    }
  }
}
