import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/message.dart';
import '../services/chat_websocket_service.dart';
import '../database/local_chat_repository.dart';  // ✅ NEW: For SQLite updates

/// Global reactive state store for chat messages, presence, and typing indicators.
/// WebSocketService updates this store; UI consumes via ChangeNotifier/Provider.
class ChatStore extends ChangeNotifier {
  // Map from otherUserId to their conversation messages
  final Map<int, List<Message>> _messagesByUser = {};
  
  // Maximum messages to keep per conversation (prevent memory leaks)
  static const int _maxMessagesPerConversation = 500;

  // Map from userId to online status
  final Map<int, bool> _onlineStatus = {};

  // Map from otherUserId to typing status
  final Map<int, bool> _typingStatus = {};
  
  // Typing indicator timeout timers
  final Map<int, Timer> _typingTimers = {};

  // ✅ NEW: Cache of unread counts per conversation (for fast badge display)
  final Map<int, int> _unreadCountCache = {};

  // ✅ NEW: SQLite repository for durable persistence
  final LocalChatRepository _localRepo = LocalChatRepository();

  // Currently open/active chat otherUserId. UI (ChatDetailScreen) sets this
  // when the chat view is visible; the store will not auto-mark incoming
  // messages as read — reads are applied explicitly via `markMessagesRead`.
  int? activeChatUserId;
  // Record when a conversation became active (opened) so we only auto-mark
  // messages that arrived while the chat was visible.
  final Map<int, DateTime> _activeSinceByUser = {};

  /// Mark a conversation as active (user opened chat). Use this instead of
  /// setting `activeChatUserId` directly so we record an active timestamp.
  void setActiveChat(int otherUserId) {
    activeChatUserId = otherUserId;
    _activeSinceByUser[otherUserId] = DateTime.now().toUtc();
    print('[ChatStore] 📖 setActiveChat: activeChatUserId=$otherUserId');
    notifyListeners();
  }

  /// Clear the active chat marker for the current UI.
  void clearActiveChat() {
    if (activeChatUserId != null) {
      print('[ChatStore] 📖 clearActiveChat: was=$activeChatUserId, now=null');
      _activeSinceByUser.remove(activeChatUserId);
      activeChatUserId = null;
      notifyListeners();
    }
  }

  /// Return the UTC timestamp when `otherUserId` conversation became active,
  /// or null if it is not active.
  DateTime? activeSinceFor(int otherUserId) => _activeSinceByUser[otherUserId];
  int? _currentUserId;

  /// Provide the id of the currently authenticated user so the store can
  /// perform user-scoped operations (like marking messages addressed to
  /// the current user as read when no explicit ids are supplied).
  void setCurrentUserId(int id) {
    _currentUserId = id;
  }

  // loadCachedMessagesForUser/loadAllCachedConversations (SharedPreferences-
  // backed) removed during Phase 2's local-database consolidation — bulk
  // startup load is SQLiteLoaderService's job (already runs before the UI
  // needs this data), and reloading per-conversation from a second, looser
  // cache on every chat-open risked silently overwriting already-correct
  // in-memory state (e.g. read status) with stale data. See
  // local_chat_repository.dart for the single remaining local store.

  bool _sameMessage(Message a, Message b) {
    // Prefer clientMessageId for reconciliation
    if (a.clientMessageId != null &&
        b.clientMessageId != null &&
        a.clientMessageId == b.clientMessageId) {
      return true;
    }

    // Fallback to server id
    if (a.id != 0 && b.id != 0 && a.id == b.id) {
      return true;
    }

    return false;
  }

  MessageStatus _resolveStatus(Message m) {
    if (m.status == MessageStatus.uploading) return MessageStatus.uploading;
    if (m.readAt != null) return MessageStatus.read;
    if (m.id != 0) return MessageStatus.sent;
    return MessageStatus.sending;
  }

  /// Get messages for a specific user conversation
  List<Message> messagesForUser(int otherUserId) {
    final msgs = _messagesByUser[otherUserId] ?? [];
    if (msgs.isNotEmpty) {
      print('[CHATSTORE] ✅ messagesForUser($otherUserId): returning ${msgs.length} messages');
      print('[CHATSTORE]    ├─ First: id=${msgs.first.id}, clientId=${msgs.first.clientMessageId}');
      print('[CHATSTORE]    ├─ Last: id=${msgs.last.id}, clientId=${msgs.last.clientMessageId}');
      print('[CHATSTORE]    └─ createdAt range: ${msgs.first.createdAt} → ${msgs.last.createdAt}');
    }
    return msgs;
  }

  /// Get all conversations (map of otherUserId → messages)
  Map<int, List<Message>> get allConversations =>
      Map.unmodifiable(_messagesByUser);

  /// Get online status for a user
  bool isUserOnline(int userId) {
    return _onlineStatus[userId] ?? false;
  }

  /// Get online status map snapshot
  Map<int, bool> get onlineStatus => Map.unmodifiable(_onlineStatus);

  /// Get typing status for a conversation
  bool isUserTyping(int otherUserId) {
    final status = _typingStatus[otherUserId] ?? false;
    if (status) {
      print('[CHATSTORE] 🔤 isUserTyping($otherUserId) = TRUE ← typing in progress');
    }
    return status;
  }

  /// Add an incoming message (from WebSocket or REST)
  void addIncomingMessage(Message msg, int currentUserId) {
    // Compute otherUserId: if we sent it, otherId = receiver; else otherId = sender
    final otherUserId =
        (msg.senderId == currentUserId) ? msg.recipientId : msg.senderId;

    final messages = _messagesByUser.putIfAbsent(otherUserId, () => []);

    // Reconcile message: find existing by id or clientMessageId
    int existingIndex = -1;
    for (var i = 0; i < messages.length; i++) {
      if (_sameMessage(messages[i], msg)) {
        existingIndex = i;
        break;
      }
    }

    // If we didn't find a match but incoming has a clientMessageId, try to
    // find an optimistic message previously inserted with that
    // clientMessageId and reconcile it. This covers server frames that echo
    // the client id (with or without server id).
    if (existingIndex < 0 && msg.clientMessageId != null) {
      for (var i = 0; i < messages.length; i++) {
        final m = messages[i];
        if (m.clientMessageId != null && m.clientMessageId == msg.clientMessageId) {
          existingIndex = i;
          break;
        }
      }
    }

    // Prepare incoming message with explicit resolved status. Do NOT auto-mark
    // as read here; read receipts are applied explicitly by the UI when the
    // chat is visible (via `markMessagesRead`).
    Message incoming = msg.copyWith(status: _resolveStatus(msg));

    // If we are reconciling an optimistic message (existingIndex >= 0),
    // preserve the optimistic `clientMessageId` if server payload omitted it
    // and ensure the status transitions to `sent` when server id is present.
    if (existingIndex >= 0) {
      final existing = messages[existingIndex];
      if ((incoming.clientMessageId == null || incoming.clientMessageId!.isEmpty) &&
          existing.clientMessageId != null && existing.clientMessageId!.isNotEmpty) {
        incoming = incoming.copyWith(clientMessageId: existing.clientMessageId);
      }
      // If server acknowledged with id, move to sent
      if (incoming.id != 0) {
        incoming = incoming.copyWith(status: MessageStatus.sent);
      }
    }

    if (existingIndex >= 0) {
      // Replace existing message (reconciliation)
      messages[existingIndex] = incoming;
      final senderLabel = (incoming.senderId == currentUserId) ? 'SENDER' : 'RECEIVER';
      print('[$senderLabel] [ChatStore] 🔄 RECONCILE message');
      print('[$senderLabel] [ChatStore]  ├─ otherUser: $otherUserId');
      print('[$senderLabel] [ChatStore]  ├─ clientId: ${incoming.clientMessageId}');
      print('[$senderLabel] [ChatStore]  ├─ serverId: ${incoming.id}');
      print('[$senderLabel] [ChatStore]  └─ status: ${incoming.status} (updated ⏱ → ✓)');
    } else {
      // Insert new message only if not present
      messages.add(incoming);
      final senderLabel = (incoming.senderId == currentUserId) ? 'SENDER' : 'RECEIVER';
      print('[$senderLabel] [ChatStore] ✅ INSERT new message');
      print('[$senderLabel] [ChatStore]  ├─ otherUser: $otherUserId');
      print('[$senderLabel] [ChatStore]  ├─ clientId: ${incoming.clientMessageId}');
      print('[$senderLabel] [ChatStore]  ├─ serverId: ${incoming.id}');
      print('[$senderLabel] [ChatStore]  └─ status: ${incoming.status}');
    }

    // After any modification, sort by createdAt ascending
    messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    
    // Enforce message limit to prevent memory leaks
    if (messages.length > _maxMessagesPerConversation) {
      final excess = messages.length - _maxMessagesPerConversation;
      messages.removeRange(0, excess);
      print('[CHATSTORE] Trimmed $excess old messages for user=$otherUserId');
    }

    // Do not mutate read state here. The UI (ChatDetailScreen) is responsible
    // for calling `markMessagesRead` when the conversation becomes visible.

    // Local persistence for this message happens via SQLitePersistenceHelper,
    // which listens to the same WebSocket stream independently (see
    // main.dart) — no separate write needed here. (Removed a redundant
    // SharedPreferences-backed cache during Phase 2's local-database
    // consolidation; see local_chat_repository.dart.)

    // ✅ SMART: Auto-read receipt ONLY if chat is ALREADY active
    // If user is actively viewing ChatDetailScreen and new message arrives, mark as read immediately
    // If user is on HomeScreen/CallScreen, DON'T mark as read (wait until they open the chat)
    _sendReadReceiptIfChatActive(incoming, otherUserId, currentUserId);

    // ✅ Unread accounting: increment rather than recompute.
    // _messagesByUser is frequently PARTIAL - a conversation that was never
    // opened starts as an empty list, and old messages get trimmed - so
    // recomputing here would clobber the accurate backend-seeded count with a
    // smaller one. Incrementing is both correct and O(1).
    _applyUnreadForIncoming(
      incoming: incoming,
      otherUserId: otherUserId,
      currentUserId: currentUserId,
      isNewInsert: existingIndex < 0,
    );

    notifyListeners();
    final senderLabel = (msg.senderId == currentUserId) ? 'SENDER' : 'RECEIVER';
    print('[$senderLabel] [ChatStore] 📢 notifyListeners() called (UI will rebuild)');
    // Debug: report unread count for this conversation for current user
    try {
      final uc = (_currentUserId != null && _currentUserId != 0) ? _currentUserId! : null;
      final ucount = unreadCountForConversation(otherUserId, uc);
      print('[$senderLabel] [ChatStore] 📊 Unread count for user=$otherUserId: $ucount');
    } catch (_) {}
  }

  /// Add an outgoing message (optimistic or confirmed)
  void addOutgoingMessage(Message msg, int currentUserId) {
    // Optimistic insert: ensure status is sending and id==0
    final optimistic = msg.copyWith(
        status: MessageStatus.sending, id: msg.id == 0 ? 0 : msg.id);
    // Insert or reconcile optimistically
    addIncomingMessage(optimistic, currentUserId);
  }

  /// Add multiple initial messages (from REST load)
  void addInitialMessages(int otherUserId, List<Message> messages) {
    final buf = _messagesByUser.putIfAbsent(otherUserId, () => []);
    var changed = false;
    for (var msg in messages) {
      // Use reconciliation: replace if exists (by identity), insert otherwise
      int existingIndex = -1;
      for (var i = 0; i < buf.length; i++) {
        if (_sameMessage(buf[i], msg)) {
          existingIndex = i;
          break;
        }
      }
      Message incoming = msg.copyWith(status: _resolveStatus(msg));
      if (existingIndex >= 0) {
        buf[existingIndex] = incoming;
        changed = true;
      } else {
        buf.add(incoming);
        changed = true;
      }
    }
    if (changed) {
      buf.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      notifyListeners();
    }
  }
  
  /// Remove a message (for reverting failed optimistic sends)
  void removeMessage(int otherUserId, String clientMessageId) {
    final messages = _messagesByUser[otherUserId];
    if (messages == null) return;
    
    final initialLength = messages.length;
    messages.removeWhere((m) => m.clientMessageId == clientMessageId);
    
    if (messages.length != initialLength) {
      print('[CHATSTORE] Removed failed message: clientId=$clientMessageId');
      notifyListeners();
    }
  }

  /// ✅ NEW: Send read receipt in real-time if this chat is currently active
  void _sendReadReceiptIfChatActive(Message msg, int otherUserId, int currentUserId) {
    try {
      // CRITICAL: Only send read receipt if ALL these conditions are met:
      // 1. Message is from the OTHER user (not my own message)
      // 2. Message is UNREAD (not already marked as read)
      // 3. Chat is currently ACTIVE (user is viewing this conversation RIGHT NOW)
      
      // Condition 1: Check if message is from other user
      if (msg.senderId != otherUserId) {
        return;  // This is my own message, don't send read receipt
      }

      // Condition 2: Check if message is UNREAD
      if (msg.isRead) {
        return;  // Already read, don't send read receipt again
      }

      // Condition 3: Check if this chat is currently active
      final isActive = activeChatUserId == otherUserId;
      
      if (!isActive) {
        print('[ChatStore] 📖 Chat NOT active - skipping read receipt (activeChatUserId=$activeChatUserId, otherUserId=$otherUserId)');
        return;  // Chat is not active, don't send read receipt
      }
      
      // All conditions met - send read receipt
      print('[ChatStore] 📖 Conditions met - sending real-time read receipt for message ${msg.id}');
      
      // ✅ Mark message as read locally FIRST
      if (msg.id != 0) {
        print('[ChatStore] 📖 Marking message ${msg.id} as read locally');
        markMessagesRead(otherUserId, messageIds: [msg.id], currentUserId: currentUserId);
      }
      
      // Then send the read receipt to server
      final wsService = ChatWebSocketService();
      wsService.sendReadReceipt(otherUserId, [msg.id]);
      print('[ChatStore] ✅ Read receipt sent and message marked as read');
      
    } catch (e, st) {
      print('[ChatStore] ❌ Error in _sendReadReceiptIfChatActive: $e\n$st');
    }
  }

  /// Update message status by clientMessageId (for fallback confirmation)
  void updateMessageStatus(int otherUserId, String clientMessageId, MessageStatus newStatus) {
    final messages = _messagesByUser[otherUserId];
    if (messages == null) return;
    
    for (int i = 0; i < messages.length; i++) {
      if (messages[i].clientMessageId == clientMessageId) {
        final oldStatus = messages[i].status;
        messages[i] = messages[i].copyWith(status: newStatus);
        print('[CHATSTORE] ✅ Updated message status: $oldStatus → $newStatus');
        print('[CHATSTORE]    └─ clientId: $clientMessageId');
        
        // SQLite is updated independently by MessageQueueService, which
        // listens to the same underlying message-ack/read-receipt streams
        // (see message_queue_service.dart's _updateMessageStatus).

        notifyListeners();
        return;
      }
    }
    print('[CHATSTORE] ⚠️ Message not found for status update: $clientMessageId');
  }

  /// Mark messages as read in the store (update isRead flag)
  /// ✅ NOW ASYNC: Waits for SQLite updates to persist before returning
  Future<void> markMessagesRead(int otherUserId,
      {List<int>? messageIds, List<String>? clientMessageIds, int? currentUserId}) async {
    final messages = _messagesByUser[otherUserId];
    if (messages == null || messages.isEmpty) return;

    final now = DateTime.now().toUtc();
    bool changed = false;

    final idsSet = (messageIds != null) ? Set<int>.from(messageIds) : <int>{};
    final clientIdsSet = (clientMessageIds != null) ? Set<String>.from(clientMessageIds) : <String>{};

    // Determine effective current user id: prefer explicit param, otherwise stored value
    final effCurrentUserId = currentUserId ?? _currentUserId;

    if (effCurrentUserId == null) {
      // Without a known current user we cannot safely mark messages as read.
      print('[CHATSTORE] markMessagesRead called without currentUserId — no action taken');
      return;
    }

    int markedCount = 0;
    final markedMessageIds = <int>[];  // COLLECT ALL MARKED IDs
    final sqliteUpdateFutures = <Future>[]; // ✅ NEW: Collect all SQLite updates
    
    final newList = messages.map((m) {
      bool shouldMark = false;

      // If specific ids provided, mark only those matching messages (by id or client id)
      if (idsSet.isNotEmpty || clientIdsSet.isNotEmpty) {
        final matchesId = idsSet.isNotEmpty && idsSet.contains(m.id);
        final matchesClientId = clientIdsSet.isNotEmpty && m.clientMessageId != null && clientIdsSet.contains(m.clientMessageId);
        // Mark if it matches AND is unread
        shouldMark = (matchesId || matchesClientId) && m.readAt == null;
      } else {
        // No ids provided: mark ALL unread messages in this conversation
        // that were addressed to the current user (received messages only).
        shouldMark = (m.recipientId == effCurrentUserId && m.readAt == null);
      }

      if (shouldMark) {
        changed = true;
        markedCount += 1;
        markedMessageIds.add(m.id);
        print('[CHATSTORE] 📖 Marking message as read: id=${m.id}, senderId=${m.senderId}, recipientId=${m.recipientId}');
        final updatedMsg = m.copyWith(isRead: true, readAt: now, status: MessageStatus.read);

        // ✅ CRITICAL: Update SQLite and COLLECT the Future to await later
        if (m.id != 0) {
          sqliteUpdateFutures.add(
            _localRepo.updateMessageReadStatus(m.id, now.millisecondsSinceEpoch)
          );
        }
        
        return updatedMsg;
      }
      return m;
    }).toList();

    if (changed) {
      _messagesByUser[otherUserId] = newList..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      print('[CHATSTORE] 📖 Updated ${markedCount} messages in memory');
      
      // ✅ CRITICAL FIX: AWAIT all SQLite updates before proceeding
      if (sqliteUpdateFutures.isNotEmpty) {
        print('[CHATSTORE] ⏳ Waiting for ${sqliteUpdateFutures.length} SQLite updates...');
        try {
          await Future.wait(sqliteUpdateFutures);
          print('[CHATSTORE] ✅ SQLite updates COMPLETED - status now durable');
        } catch (e) {
          print('[CHATSTORE] ❌ SQLite update failed: $e');
        }
      }
      
      print('[CHATSTORE] markMessagesRead applied for otherUserId=$otherUserId marked=$markedCount ids=${markedMessageIds.length}');
      
      // Send read receipt to server via WebSocket with ALL marked message IDs

      try {
        final wsService = ChatWebSocketService();
        if (wsService.isConnected && markedMessageIds.isNotEmpty) {
          wsService.sendReadReceipt(otherUserId, markedMessageIds);  // Send collected IDs
          print('[CHATSTORE] ✅ Sent read receipts for ${markedMessageIds.length} messages');
        }
      } catch (e) {
        print('[CHATSTORE] Failed to send read receipt: $e');
      }
      
      // ✅ Unread accounting after marking as read.
      // Same reasoning as on insert: never recompute from the (partial) local
      // list. Marking the whole conversation read means zero by definition;
      // marking specific ids decrements by however many actually changed.
      if (idsSet.isEmpty && clientIdsSet.isEmpty) {
        _unreadCountCache[otherUserId] = 0;
        print('[CHATSTORE] 🔻 Unread cleared for user=$otherUserId (whole conversation read)');
      } else {
        final current = _unreadCountCache[otherUserId] ?? 0;
        final updated = (current - markedCount).clamp(0, current);
        _unreadCountCache[otherUserId] = updated;
        print('[CHATSTORE] 🔻 Unread -$markedCount for user=$otherUserId → $updated');
      }

      notifyListeners();
    }
  }

  /// Mark messages as read by recipient (for incoming read receipts)
  /// This is called when WE (the sender) receive a read receipt from the OTHER user
  /// It marks OUR SENT messages as READ (double tick)
  void markMessagesAsReadByRecipient(int otherUserId, List<int> messageIds) {
    final messages = _messagesByUser[otherUserId];
    if (messages == null || messages.isEmpty) {
      print('[CHATSTORE] ⚠️ No messages found for user=$otherUserId');
      return;
    }
    
    print('[CHATSTORE] 🔍 DEBUG: Attempting to mark messages as read');
    print('[CHATSTORE]    ├─ otherUserId: $otherUserId');
    print('[CHATSTORE]    ├─ currentUserId: $_currentUserId');
    print('[CHATSTORE]    ├─ Incoming message IDs to mark: $messageIds');
    print('[CHATSTORE]    ├─ Total messages available: ${messages.length}');
    
    // Print all available message IDs for debugging
    final availableIds = messages.map((m) => 'id=${m.id} senderId=${m.senderId} status=${m.status}').join(', ');
    print('[CHATSTORE]    └─ Available messages: [$availableIds]');
    
    final now = DateTime.now().toUtc();
    final idsSet = Set<int>.from(messageIds);
    bool changed = false;
    int markedCount = 0;
    
    final newList = messages.map((m) {
      // Check all conditions separately for debugging
      final idMatches = idsSet.contains(m.id);
      final sentByUs = m.senderId == _currentUserId;
      final notAlreadyRead = m.status != MessageStatus.read;
      
      if (idMatches) {
        print('[CHATSTORE]    • Found message id=${m.id}: sentByUs=$sentByUs, notAlreadyRead=$notAlreadyRead');
      }
      
      // Mark if: message ID matches AND it was sent BY US (we are the sender)
      if (idMatches && sentByUs && notAlreadyRead) {
        changed = true;
        markedCount++;
        print('[CHATSTORE] ✅✅ Marking as READ (double tick): id=${m.id}, content="${m.content.substring(0, m.content.length > 20 ? 20 : m.content.length)}..."');
        final updatedMsg = m.copyWith(isRead: true, readAt: now, status: MessageStatus.read);

        // SQLite is updated independently via SQLitePersistenceHelper's own
        // readReceiptStream listener (see main.dart).

        return updatedMsg;
      }
      return m;
    }).toList();
    
    if (changed) {
      _messagesByUser[otherUserId] = newList..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      print('[CHATSTORE] 📖📖 Read receipt applied: $markedCount messages now show double ticks');
      notifyListeners();
    } else {
      print('[CHATSTORE] ⚠️ No messages were updated by read receipt - checking why:');
      for (final id in messageIds) {
        final found = messages.any((m) => m.id == id);
        final msgWithId = messages.where((m) => m.id == id).firstOrNull;
        final sentByUs = msgWithId?.senderId == _currentUserId;
        print('[CHATSTORE]    ├─ ID=$id found=$found sentByUs=$sentByUs');
      }
    }
  }

  /// Return unread count for a conversation (from cache)
  int unreadCountForConversation(int otherUserId, [int? currentUserId]) {
    // Simple: just return cached count
    final cached = _unreadCountCache[otherUserId] ?? 0;
    if (cached > 0) {
      print('[CHATSTORE] 📊 BADGE: userId=$otherUserId unread=$cached (from cache)');
    }
    return cached;
  }

  /// Total unread messages across every conversation.
  /// Drives the badge on the Chats tab in the bottom navigation bar.
  int get totalUnreadCount {
    var total = 0;
    for (final count in _unreadCountCache.values) {
      total += count;
    }
    return total;
  }

  /// Whether there are any unread messages at all (cheap check for a dot badge).
  bool get hasUnreadMessages => totalUnreadCount > 0;

  /// Seed many unread counts at once (e.g. from the conversations API).
  ///
  /// Notifies a single time instead of once per conversation, which avoids
  /// rebuilding the whole conversation list N times on every load.
  void seedUnreadCounts(Map<int, int> countsByUserId) {
    var changed = false;
    countsByUserId.forEach((userId, count) {
      if (_unreadCountCache[userId] != count) {
        _unreadCountCache[userId] = count;
        changed = true;
      }
    });

    if (changed) {
      print('[CHATSTORE] 🌱 Seeded ${countsByUserId.length} unread counts (total=$totalUnreadCount)');
      notifyListeners();
    }
  }

  /// Update unread count cache (called when loading or when message status changes)
  void updateUnreadCountCache(int otherUserId, int count) {
    final previous = _unreadCountCache[otherUserId];
    if (previous == count) return; // No change - avoid redundant rebuilds

    _unreadCountCache[otherUserId] = count;
    print('[CHATSTORE] 🔄 Updated unread count cache: userId=$otherUserId count=$count');

    // Notify so the Chats tab badge reflects counts seeded from the backend
    // (e.g. on app start) and not just counts derived from live messages.
    notifyListeners();
  }

  /// Apply the unread-count delta for a newly arrived message.
  ///
  /// Deliberately incremental: it never reads _messagesByUser, because that list
  /// is often partial and a recompute would undercount. Only a genuinely new
  /// message that THIS user received, has not read, and is not currently looking
  /// at can raise the badge.
  void _applyUnreadForIncoming({
    required Message incoming,
    required int otherUserId,
    required int currentUserId,
    required bool isNewInsert,
  }) {
    // Reconciling an existing/optimistic message must never change the count.
    if (!isNewInsert) return;

    // Never count our own sent messages - this is what previously leaked the
    // sender's pending messages into the sender's own badge.
    if (incoming.senderId == currentUserId) return;
    if (incoming.recipientId != currentUserId) return;

    // Already read, or the user is viewing this conversation right now.
    if (incoming.isRead || incoming.readAt != null) return;
    if (activeChatUserId == otherUserId) return;

    _unreadCountCache[otherUserId] = (_unreadCountCache[otherUserId] ?? 0) + 1;
    print('[CHATSTORE] 🔺 Unread +1 for user=$otherUserId → ${_unreadCountCache[otherUserId]}');
  }

  /// Recalculate unread count for a user (called after messages change).
  ///
  /// Only messages the current user RECEIVED and has not read count as unread.
  /// A message the current user sent is never unread for them, no matter whether
  /// the recipient has read it yet.
  int recalculateUnreadCount(int otherUserId, [int? currentUserId]) {
    final effCurrentUserId = currentUserId ?? _currentUserId;

    // Identity unknown (null or 0): we cannot tell sent from received, so leave
    // the existing (backend-seeded) value alone rather than computing a wrong one.
    if (effCurrentUserId == null || effCurrentUserId == 0) {
      print('[CHATSTORE] ⚠️ currentUserId unknown in recalculateUnreadCount - keeping cached value');
      return _unreadCountCache[otherUserId] ?? 0;
    }

    final msgs = _messagesByUser[otherUserId];
    if (msgs == null || msgs.isEmpty) {
      _unreadCountCache[otherUserId] = 0;
      return 0;
    }

    // A message is unread only if THIS user is the recipient and hasn't read it.
    // Checking recipientId (not just "senderId != me") is what keeps the sender's
    // own pending messages out of their own badge.
    // `isRead` is the authoritative flag; `readAt` is only a timestamp and can be
    // null even for an already-read message. Requiring both to indicate "unread"
    // avoids counting messages that were in fact already read.
    final unreadMsgs = msgs
        .where((m) =>
            m.recipientId == effCurrentUserId &&
            m.senderId != effCurrentUserId &&
            !m.isRead &&
            m.readAt == null)
        .toList();
    
    final count = unreadMsgs.length;
    _unreadCountCache[otherUserId] = count;
    
    if (count > 0) {
      print('[CHATSTORE] 📊 Recalculated unread: userId=$otherUserId count=$count');
      for (final m in unreadMsgs.take(2)) {
        print('[CHATSTORE]    • id=${m.id} from=${m.senderId} readAt=${m.readAt}');
      }
    }
    
    return count;
  }

  /// Set user online/offline status
  void setUserOnline(int userId, bool isOnline) {
    print('[CHATSTORE] 🟢 setUserOnline CALLED: userId=$userId isOnline=$isOnline');
    final prev = _onlineStatus[userId];
    print('[CHATSTORE]    ├─ Previous status: ${prev ?? "not set"}');
    _onlineStatus[userId] = isOnline;
    if (prev != isOnline) {
      if (isOnline) {
        print('[CHATSTORE] ✅ userId=$userId changed to ONLINE');
      } else {
        print('[CHATSTORE] ⚫ userId=$userId changed to OFFLINE');
      }
      print('[CHATSTORE]    └─ Calling notifyListeners()...');
      notifyListeners();
      print('[CHATSTORE]    └─ notifyListeners() COMPLETE');
    } else {
      print('[CHATSTORE]    └─ Status unchanged, NOT calling notifyListeners()');
    }
  }

  /// Set typing status for a conversation
  void setTyping(int otherUserId, bool isTyping) {
    print('[CHATSTORE] 🔤 setTyping CALLED: user=$otherUserId isTyping=$isTyping');
    print('[CHATSTORE]    ├─ Before: _typingStatus=$_typingStatus');
    
    // Cancel existing timer
    _typingTimers[otherUserId]?.cancel();
    
    if (isTyping) {
      if (_typingStatus[otherUserId] != true) {
        _typingStatus[otherUserId] = true;
        print('[CHATSTORE] ✅ Typing status SET to TRUE for user=$otherUserId');
        print('[CHATSTORE]    └─ After: _typingStatus=$_typingStatus');
        notifyListeners();
        print('[CHATSTORE] 📢 notifyListeners() called');
      }
      
      // Auto-clear typing indicator after 3 seconds if no update
      _typingTimers[otherUserId] = Timer(const Duration(seconds: 3), () {
        if (_typingStatus[otherUserId] == true) {
          _typingStatus.remove(otherUserId);
          print('[CHATSTORE] ⏱️ Typing indicator auto-cleared for user=$otherUserId (3s timeout)');
          print('[CHATSTORE]    └─ After clear: _typingStatus=$_typingStatus');
          notifyListeners();
        }
      });
    } else {
      if (_typingStatus.remove(otherUserId) != null) {
        print('[CHATSTORE] ✅ Typing status CLEARED for user=$otherUserId');
        print('[CHATSTORE]    └─ After: _typingStatus=$_typingStatus');
        notifyListeners();
        print('[CHATSTORE] 📢 notifyListeners() called');
      }
    }
  }

  /// ✅ NEW: Load conversation from SQLite (for offline loading)
  void loadConversationFromSQLite(int otherUserId, List<Message> messages) {
    _messagesByUser[otherUserId] = messages;
    print('[CHATSTORE] 📂 loadConversationFromSQLite: Loaded ${messages.length} messages for user=$otherUserId');
    
    // ✅ SIMPLE: Calculate and cache unread count immediately
    recalculateUnreadCount(otherUserId);
    
    notifyListeners();
  }

  /// Ensure a conversation exists for a user (called when new conversation notification arrives)
  /// This creates an empty conversation if it doesn't exist, so it appears in the chat list
  void ensureConversation(int otherUserId) {
    if (!_messagesByUser.containsKey(otherUserId)) {
      _messagesByUser[otherUserId] = [];
      print('[CHATSTORE] ensureConversation created empty conversation with $otherUserId');
      notifyListeners();
    }
  }

  /// Clear all state (for logout or testing)
  void clear() {
    _messagesByUser.clear();
    _onlineStatus.clear();
    _typingStatus.clear();
    // Unread counts and identity are user-scoped: leaving them behind would leak
    // the previous user's badge counts into the next session.
    _unreadCountCache.clear();
    _currentUserId = null;
    // Cancel all typing timers
    for (var timer in _typingTimers.values) {
      timer.cancel();
    }
    _typingTimers.clear();
    notifyListeners();
  }
  
  @override
  void dispose() {
    // Clean up all typing indicator timers
    for (var timer in _typingTimers.values) {
      timer.cancel();
    }
    _typingTimers.clear();
    super.dispose();
  }
}
