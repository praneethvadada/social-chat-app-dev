import '../models/message.dart';
import '../database/local_chat_repository.dart';
import '../state/chat_store.dart';
import 'api_service.dart';
import 'sqlite_persistence_helper.dart';

/// ChatSyncService - Syncs conversations and messages from server to local SQLite
/// Called on app startup/login to ensure all data is available offline
class ChatSyncService {
  final LocalChatRepository _repo = LocalChatRepository();

  /// Sync all conversations from server to SQLite and ChatStore
  /// This is called on app startup to fetch any conversations/messages that arrived while offline
  Future<void> syncConversationsFromServer(ChatStore chatStore, int currentUserId) async {
    print('[CHAT_SYNC] 🔄 Starting sync from server...');
    
    try {
      // Step 1: Fetch all conversations from server
      print('[CHAT_SYNC] 📥 Fetching conversations from server...');
      final conversations = await ApiService.getConversations();
      print('[CHAT_SYNC] ✅ Fetched ${conversations.length} conversations');
      
      if (conversations.isEmpty) {
        print('[CHAT_SYNC] ℹ️  No conversations on server');
        return;
      }

      // Step 2: For each conversation, fetch message history
      for (final conv in conversations) {
        try {
          print('[CHAT_SYNC] 📨 Fetching messages for conversation with user=${conv.userId}...');
          
          // Fetch all messages for this conversation
          final messageHistory = await ApiService.getConversation(conv.userId);
          print('[CHAT_SYNC] ✅ Fetched ${messageHistory.length} messages for user=${conv.userId}');
          
          if (messageHistory.isNotEmpty) {
            //Convert to Message objects - this preserves readAt from server
            final messages = messageHistory
                .map((json) {
                  final msg = Message.fromJson(json);
                  print('[CHAT_SYNC]    Message id=${msg.id}: from=${msg.senderId} readAt=${msg.readAt} isRead=${msg.isRead}');
                  return msg;
                })
                .toList();
            
            // Save each message to SQLite (with proper readAt values)
            for (final msg in messages) {
              await _saveSingleMessageToSQLite(msg, currentUserId);
            }
            
            // Load into ChatStore - this preserves the readAt values from server
            chatStore.loadConversationFromSQLite(conv.userId, messages);
            
            print('[CHAT_SYNC] ✅ Synced ${messages.length} messages for user=${conv.userId}');
            
            // Count unread for debugging
            final unreadCount = messages.where((m) => 
              m.senderId != currentUserId && m.readAt == null
            ).length;
            print('[CHAT_SYNC]    └─ Unread: $unreadCount (senderId != $currentUserId && readAt == null)');
          }
        } catch (e) {
          print('[CHAT_SYNC] ⚠️  Error syncing conversation ${conv.userId}: $e');
          // Continue with next conversation instead of failing
        }
      }

      print('[CHAT_SYNC] ✅ Sync from server completed successfully');
    } catch (e) {
      print('[CHAT_SYNC] ❌ Error during server sync: $e');
      rethrow;
    }
  }

  /// Save a single message to SQLite (preserving readAt)
  Future<void> _saveSingleMessageToSQLite(Message msg, int currentUserId) async {
    try {
      // Calculate stable chatId
      final chatId = msg.senderId < msg.recipientId 
          ? msg.senderId 
          : msg.recipientId;
      
      final sqliteMsg = SQLiteMessage(
        id: msg.id,
        clientMessageId: msg.clientMessageId,
        chatId: chatId,
        senderId: msg.senderId,
        receiverId: msg.recipientId,
        content: msg.content,
        createdAt: msg.createdAt.millisecondsSinceEpoch,
        readAt: msg.readAt?.millisecondsSinceEpoch,  // ✅ CRITICAL: Preserve readAt from server
        status: _messageStatusToString(msg.status),
      );

      await _repo.insertMessage(sqliteMsg);
      
      // Ensure conversation exists
      await _repo.ensureConversationExists(chatId);
    } catch (e) {
      print('[CHAT_SYNC] Error saving message to SQLite: $e');
    }
  }

  /// Convert MessageStatus enum to string
  String _messageStatusToString(MessageStatus status) {
    switch (status) {
      case MessageStatus.sending:
        return 'SENDING';
      case MessageStatus.sent:
        return 'SENT';
      case MessageStatus.read:
        return 'READ';
      case MessageStatus.failed:
        return 'FAILED';
      default:
        return 'SENT';
    }
  }
}
