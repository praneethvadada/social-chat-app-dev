import '../database/local_chat_repository.dart';
import '../state/chat_store.dart';
import '../models/message.dart';

/// SQLiteLoaderService - Restores chat data from SQLite on app startup
/// 
/// This service:
/// 1. Loads messages from SQLite
/// 2. Loads conversations from SQLite
/// 3. Populates ChatStore with this data
/// 4. Enables offline access to chats
class SQLiteLoaderService {
  final LocalChatRepository _repo = LocalChatRepository();

  /// Load all chat data from SQLite and populate ChatStore
  /// currentUserId is needed to properly distinguish sent vs received messages
  Future<void> loadChatDataFromSQLite(ChatStore chatStore, int currentUserId) async {
    print('[SQLITE_LOADER] ========== LOADING CHAT DATA FROM SQLite ==========');
    print('[SQLITE_LOADER] Current User ID: $currentUserId');

    try {
      // Step 1: Load all conversations
      print('[SQLITE_LOADER] 1️⃣ Loading conversations from SQLite...');
      final conversations = await _repo.loadAllConversations();
      print('[SQLITE_LOADER] ✅ Loaded ${conversations.length} conversations');

      // Step 2: Load all messages
      print('[SQLITE_LOADER] 2️⃣ Loading messages from SQLite...');
      final allMessages = await _repo.loadAllMessages();
      print('[SQLITE_LOADER] ✅ Loaded ${allMessages.length} messages total');

      // Step 3: Convert SQLite models to API models and populate ChatStore
      print('[SQLITE_LOADER] 3️⃣ Populating ChatStore with loaded data...');

      // For each conversation, load its messages
      for (final conv in conversations) {
        final otherUserId = conv.otherUserId;

        // Get messages for this conversation
        final convMessages = allMessages
            .where((m) =>
                (m.senderId == otherUserId || m.receiverId == otherUserId))
            .toList();

        // Convert SQLite messages to API Message objects
        final apiMessages = convMessages.map((sqliteMsg) {
          return Message(
            id: sqliteMsg.id ?? 0,
            clientMessageId: sqliteMsg.clientMessageId,
            senderId: sqliteMsg.senderId,
            senderName: (sqliteMsg.senderId == otherUserId) ? conv.otherUserName ?? 'Unknown' : 'You',
            senderProfilePic: (sqliteMsg.senderId == otherUserId) ? conv.otherUserProfilePic : null,
            recipientId: sqliteMsg.receiverId,
            content: sqliteMsg.content,
            mediaUrl: null,
            status: _stringToMessageStatus(sqliteMsg.status),
            createdAt:
                DateTime.fromMillisecondsSinceEpoch(sqliteMsg.createdAt),
            isRead: sqliteMsg.readAt != null,  // ✅ FIXED: Check actual readAt, not status
            readAt: sqliteMsg.readAt != null
                ? DateTime.fromMillisecondsSinceEpoch(sqliteMsg.readAt!)
                : null,  // ✅ FIXED: Use actual readAt timestamp from database
          );
        }).toList();

        // Add conversation to ChatStore
        if (apiMessages.isNotEmpty) {
          // Sort by timestamp
          apiMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          
          // Count sent vs received
          int sentCount = apiMessages.where((m) => m.senderId == currentUserId).length;
          int receivedCount = apiMessages.length - sentCount;
          
          // ✅ NEW: Count unread messages for badge
          int unreadCount = apiMessages.where((m) => 
            m.senderId != currentUserId &&  // Messages from other user
            m.readAt == null                // Not read by me
          ).length;
          
          print('[SQLITE_LOADER]    ├─ Conv with user=$otherUserId: ${apiMessages.length} messages');
          print('[SQLITE_LOADER]    │  ├─ Sent (senderId=$currentUserId): $sentCount messages');
          print('[SQLITE_LOADER]    │  ├─ Received (senderId=$otherUserId): $receivedCount messages');
          print('[SQLITE_LOADER]    │  └─ Unread: $unreadCount ← BADGE');
          
          chatStore.loadConversationFromSQLite(otherUserId, apiMessages);
        }
      }

      print('[SQLITE_LOADER] ✅ ChatStore populated from SQLite');
      print(
          '[SQLITE_LOADER] ========== CHAT DATA LOADED SUCCESSFULLY ==========');
    } catch (e, stack) {
      print('[SQLITE_LOADER] ❌ Error loading chat data: $e');
      print('[SQLITE_LOADER] Stack: $stack');
    }
  }

  /// Convert SQLite status string to MessageStatus enum
  MessageStatus _stringToMessageStatus(String status) {
    switch (status.toUpperCase()) {
      case 'SENDING':
        return MessageStatus.sending;
      case 'SENT':
        return MessageStatus.sent;
      case 'READ':
        return MessageStatus.read;
      case 'FAILED':
        return MessageStatus.failed;
      default:
        return MessageStatus.sent;
    }
  }
}
