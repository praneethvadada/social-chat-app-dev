# Chat System - Comprehensive Fix Implementation Plan

## Phase 1: Critical Fixes (Issues #1, #2, #3)

### Fix 1.1: Add Local Persistence Layer with Hive

**Why:** Messages currently lost on app restart or when offline

**What:** Add Hive database to persist all messages locally

**Step 1: Add dependency to pubspec.yaml**
```yaml
dependencies:
  hive: ^2.2.3
  hive_flutter: ^1.1.0
dev_dependencies:
  hive_generator: ^2.0.0
  build_runner: ^2.4.0
```

**Step 2: Create MessageBox adapter (lib/src/services/message_persistence.dart)**
```dart
import 'package:hive_flutter/hive_flutter.dart';
import '../models/message.dart';

class MessagePersistenceService {
  static const String _boxName = 'messages';
  static final MessagePersistenceService _instance = 
      MessagePersistenceService._internal();

  late Box<Message> _messageBox;
  bool _initialized = false;

  factory MessagePersistenceService() {
    return _instance;
  }

  MessagePersistenceService._internal();

  /// Initialize Hive database
  Future<void> initialize() async {
    if (_initialized) return;

    await Hive.initFlutter();
    
    // Register Message adapter if needed
    // If Message is not a HiveType, you'll need to create a custom adapter
    
    _messageBox = await Hive.openBox<Message>(_boxName);
    _initialized = true;
    print('[PERSISTENCE] Hive initialized with ${_messageBox.length} messages');
  }

  /// Save or update a message
  Future<void> saveMessage(Message msg, int otherUserId) async {
    final key = '${otherUserId}_${msg.id}_${msg.clientMessageId}';
    await _messageBox.put(key, msg);
    print('[PERSISTENCE] Saved message: $key');
  }

  /// Get all messages for a conversation
  List<Message> getMessagesForUser(int otherUserId) {
    final prefix = '${otherUserId}_';
    return _messageBox.values
        .where((msg) {
          final key = _messageBox.keys.firstWhere(
            (k) => _messageBox.get(k) == msg,
            orElse: () => '',
          );
          return key.toString().startsWith(prefix);
        })
        .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  /// Clear messages for a conversation
  Future<void> clearConversation(int otherUserId) async {
    final prefix = '${otherUserId}_';
    final keysToDelete = _messageBox.keys
        .where((k) => k.toString().startsWith(prefix))
        .toList();
    
    for (final key in keysToDelete) {
      await _messageBox.delete(key);
    }
  }

  /// Clear all messages
  Future<void> clearAll() async {
    await _messageBox.clear();
    print('[PERSISTENCE] All messages cleared');
  }
}
```

**Step 3: Integrate with ChatStore**
```dart
// In chat_store.dart
import '../services/message_persistence.dart';

class ChatStore extends ChangeNotifier {
  final MessagePersistenceService _persistence = MessagePersistenceService();
  
  /// Load messages from local cache on startup
  Future<void> loadCachedMessages() async {
    try {
      // For each user we have messages for, load from Hive
      for (final otherUserId in _messagesByUser.keys.toList()) {
        final cached = _persistence.getMessagesForUser(otherUserId);
        if (cached.isNotEmpty) {
          _messagesByUser[otherUserId] = cached;
          print('[CHATSTORE] Loaded ${cached.length} cached messages for user=$otherUserId');
        }
      }
      notifyListeners();
    } catch (e) {
      print('[CHATSTORE] Error loading cached messages: $e');
    }
  }

  /// Override addIncomingMessage to also persist
  void addIncomingMessage(Message msg, int currentUserId) {
    // ... existing code ...
    
    // After notifyListeners(), also save to persistence:
    _persistence.saveMessage(msg, otherUserId).catchError((e) {
      print('[CHATSTORE] Failed to persist message: $e');
    });
  }
}
```

---

### Fix 1.2: Fix Timestamp Calculation

**Why:** Messages show wrong time (5h, 8h instead of minutes)

**What:** Verify server timestamp generation and fix timezone handling

**Step 1: Check Java Backend (Backend Investigation)**

In `backend/src/main/java/com/yourapp/service/MessageService.java`:

```java
// CURRENT (BUGGY?) - check if it's doing this:
message.setCreatedAt(LocalDateTime.now());  // ❌ Local timezone

// SHOULD BE:
message.setCreatedAt(LocalDateTime.now(ZoneId.of("UTC")));  // ✅ UTC

// Or better:
message.setCreatedAt(OffsetDateTime.now(ZoneOffset.UTC).toLocalDateTime());
```

**Step 2: Fix Flutter Message Parsing**

In `lib/src/models/message.dart`:

```dart
factory Message.fromJson(Map<String, dynamic> json) {
  // Parse createdAt with proper timezone handling
  DateTime parseTimestamp(dynamic ts) {
    if (ts == null) {
      print('[MESSAGE] ⚠️ createdAt is null, using now()');
      return DateTime.now().toUtc();
    }
    
    try {
      if (ts is String) {
        // Handle ISO 8601 format (with or without Z)
        final parsed = DateTime.parse(ts);
        // Ensure it's UTC
        return parsed.isUtc ? parsed : parsed.toUtc();
      }
    } catch (e) {
      print('[MESSAGE] ❌ Failed to parse timestamp: $ts error: $e');
      return DateTime.now().toUtc();
    }
    return DateTime.now().toUtc();
  }

  final createdAtParsed = parseTimestamp(json['createdAt']);
  print('[MESSAGE] 📅 Parsed timestamp: $createdAtParsed (isUtc=${createdAtParsed.isUtc})');

  return Message(
    // ... other fields ...
    createdAt: createdAtParsed,
    // ... rest ...
  );
}

// Also fix timeAgo calculation
String get timeAgo {
  final now = DateTime.now().toUtc();
  final msgTime = createdAt.isUtc ? createdAt : createdAt.toUtc();
  
  // ⚠️ Debug negative difference
  final diff = now.difference(msgTime);
  
  if (diff.inSeconds < 0) {
    print('[MESSAGE] ⚠️ Future message! now=$now, msgTime=$msgTime');
    return 'now';
  }
  
  if (diff.inSeconds < 60) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  
  // Format date
  final formatter = DateFormat('MMM d');
  return formatter.format(msgTime);
}
```

---

### Fix 1.3: Process Offline Queue on Reconnect

**Why:** Messages sent while offline are queued but never sent

**What:** Add logic to send queued messages when WebSocket reconnects

**In chat_websocket_service.dart:**

```dart
void _onConnect(StompFrame frame) {
  print('\n\n🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢');
  print('[ChatWebSocketService] ✅ CONNECTED TO STOMP BROKER');
  
  _isConnected = true;
  _isConnecting = false;
  
  _connectCompleter?.complete();
  _notifyConnectionListeners(true);
  
  // Subscribe to all topics...
  _subscribeToMessageQueue();
  _subscribeToTypingIndicators();
  _subscribeToNotifications();
  _subscribeToIncomingCalls();
  
  // ✅ NEW: SEND ANY QUEUED MESSAGES
  _processOfflineQueue();  // Add this line
  
  print('[ChatWebSocketService] ✅ ALL SUBSCRIPTIONS REGISTERED');
}

/// Process messages queued while offline
void _processOfflineQueue() {
  if (_offlineQueue.isEmpty) {
    print('[ChatWebSocketService] ✅ No offline messages to process');
    return;
  }

  print('[ChatWebSocketService] 📤 Processing ${_offlineQueue.length} offline messages...');
  
  final queue = List.from(_offlineQueue);  // Copy to avoid modification during iteration
  _offlineQueue.clear();

  for (final msgData in queue) {
    try {
      final destination = msgData['destination'] as String;
      final body = msgData['body'] as String;
      
      print('[ChatWebSocketService] 📤 Sending queued message to $destination');
      
      _stompClient.send(
        destination: destination,
        body: body,
        headers: {'content-type': 'application/json'},
      );
      
      print('[ChatWebSocketService] ✅ Queued message sent: $destination');
    } catch (e) {
      print('[ChatWebSocketService] ❌ Failed to send queued message: $e');
      // Re-queue on failure
      _offlineQueue.add(msgData);
    }
  }

  if (_offlineQueue.isNotEmpty) {
    print('[ChatWebSocketService] ⚠️ ${_offlineQueue.length} messages still queued after processing');
  }
}
```

---

## Phase 2: High Priority Fixes (Issues #4, #5)

### Fix 2.1: Add Presence Subscription

**Why:** Offline status showing even when both users are chatting

**What:** Subscribe to real-time presence updates

**In chat_websocket_service.dart:**

```dart
void _onConnect(StompFrame frame) {
  // ... existing subscriptions ...
  
  // ✅ NEW: Subscribe to presence updates
  _subscribeToPresenceUpdates();
  
  print('[ChatWebSocketService] ✅ ALL SUBSCRIPTIONS REGISTERED');
}

/// Subscribe to presence updates: /user/queue/presence
void _subscribeToPresenceUpdates() {
  final topic = '/user/queue/presence';
  if (_activeSubscriptions.contains(topic)) {
    print('[ChatWebSocketService] Already subscribed to $topic');
    return;
  }

  print('[ChatWebSocketService] 👤 SUBSCRIBING to presence updates at $topic...');
  
  try {
    _stompClient.subscribe(
      destination: topic,
      callback: (frame) {
        print('[ChatWebSocketService] 👤 PRESENCE UPDATE RECEIVED');
        try {
          _onPresenceUpdate(frame);
        } catch (e) {
          print('[ChatWebSocketService] ❌ ERROR processing presence: $e');
        }
      },
      headers: {'id': 'sub-presence', 'ack': 'auto'},
    );
    
    _activeSubscriptions.add(topic);
    print('[ChatWebSocketService] ✅ Subscribed to $topic - Presence updates active');
  } catch (e) {
    print('[ChatWebSocketService] ❌ ERROR SUBSCRIBING to presence: $e');
  }
}

/// Handle presence updates (online/offline status)
void _onPresenceUpdate(StompFrame frame) {
  try {
    final data = jsonDecode(frame.body ?? '{}') as Map<String, dynamic>;
    print('[ChatWebSocketService] 👤 Presence update: $data');
    
    final userId = data['userId'] as int?;
    final isOnline = data['isOnline'] as bool?;
    
    if (userId != null && isOnline != null) {
      _chatStore?.setUserOnline(userId, isOnline);
      print('[ChatWebSocketService] 👤 User $userId now ${isOnline ? "ONLINE" : "OFFLINE"}');
    }
  } catch (e) {
    print('[ChatWebSocketService] ❌ ERROR in _onPresenceUpdate: $e');
  }
}

/// Send presence update to server when app comes to foreground
void notifyPresenceUpdate(bool isOnline) {
  if (!_isConnected) {
    print('[ChatWebSocketService] Not connected, cannot send presence update');
    return;
  }

  try {
    _stompClient.send(
      destination: '/app/presence.update',
      body: jsonEncode({'isOnline': isOnline}),
      headers: {'content-type': 'application/json'},
    );
    print('[ChatWebSocketService] 👤 Sent presence update: isOnline=$isOnline');
  } catch (e) {
    print('[ChatWebSocketService] ❌ ERROR sending presence update: $e');
  }
}
```

---

### Fix 2.2: Display Typing Indicators in UI

**Why:** Typing state is tracked but UI not showing it

**What:** Add TypingIndicator widget to ChatDetailScreen

**Create lib/src/widgets/typing_indicator.dart:**

```dart
import 'package:flutter/material.dart';

class TypingIndicator extends StatefulWidget {
  final String userName;
  
  const TypingIndicator({
    Key? key,
    required this.userName,
  }) : super(key: key);

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with TickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${widget.userName} is typing',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(width: 4),
          _buildDot(0),
          _buildDot(1),
          _buildDot(2),
        ],
      ),
    );
  }

  Widget _buildDot(int index) {
    final animation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Interval(
          index * 0.2,
          0.6 + index * 0.2,
          curve: Curves.easeInOut,
        ),
      ),
    );

    return ScaleTransition(
      scale: animation,
      child: Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: Colors.grey[400],
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
```

**In lib/src/screens/chats/chat_detail_screen.dart (or wherever messages are displayed):**

```dart
@override
Widget build(BuildContext context) {
  return Consumer<ChatStore>(builder: (context, store, _) {
    final messages = store.messagesForUser(otherUserId);
    final isTyping = store.isUserTyping(otherUserId);  // ✅ GET TYPING STATE
    
    return Scaffold(
      // ... AppBar, etc ...
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: messages.isEmpty
                ? Center(child: Text('No messages yet'))
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      return MessageBubble(message: messages[index]);
                    },
                  ),
          ),
          
          // ✅ NEW: Typing indicator
          if (isTyping)
            TypingIndicator(userName: otherUserName),
          
          // Message input
          MessageInputField(
            onSend: (content) => _sendMessage(content),
          ),
        ],
      ),
    );
  });
}
```

---

## Phase 3: Medium Priority Fixes (Issues #6, #7)

### Fix 3.1: Auto-Scroll to New Messages

**Why:** New messages appear but user doesn't see them (message above viewport)

**What:** Scroll to bottom when new message arrives

**In chat_detail_screen.dart:**

```dart
class ChatDetailScreen extends StatefulWidget {
  // ... existing code ...
  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  late ScrollController _scrollController;
  
  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatStore>(builder: (context, store, _) {
      // ✅ NEW: Scroll to bottom when messages change
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });

      final messages = store.messagesForUser(otherUserId);
      
      return ListView.builder(
        controller: _scrollController,
        itemCount: messages.length,
        itemBuilder: (context, index) {
          return MessageBubble(message: messages[index]);
        },
      );
    });
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.offset;
      
      // Only auto-scroll if user is near the bottom (within 100px)
      if (maxScroll - currentScroll < 100) {
        _scrollController.animateTo(
          maxScroll,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }
  }
}
```

---

### Fix 3.2: Optimistic Message Updates

**Why:** Message appears delayed because we wait for server confirmation

**What:** Show message immediately in UI, then reconcile when server responds

**The Flow:**

```
User types "Hello" and sends
  ↓
1. Create Message with clientMessageId (UUID), status=sending
2. Add to ChatStore IMMEDIATELY (addOutgoingMessage)
3. ✅ UI shows message in list with "⏱" (sending) icon
4. Meanwhile: Send to server
5. Server processes and responds
6. Match by clientMessageId and reconcile
7. ✅ UI updates message status to "✓" (sent)
```

**This is already partially implemented in your code!** But let's ensure the UI displays the status correctly:

**In message_bubble.dart (or your message display widget):**

```dart
class MessageBubble extends StatelessWidget {
  final Message message;
  
  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: message.senderId == currentUserId 
          ? Alignment.centerRight 
          : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: message.senderId == currentUserId 
                    ? Colors.blue[100]
                    : Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(message.content),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message.timeAgo,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(width: 4),
                
                // ✅ Show status indicator
                if (message.senderId == currentUserId) ...[
                  if (message.status == MessageStatus.sending)
                    Icon(Icons.schedule, size: 14, color: Colors.grey)
                  else if (message.status == MessageStatus.sent)
                    Icon(Icons.done, size: 14, color: Colors.grey)
                  else if (message.status == MessageStatus.read)
                    Icon(Icons.done_all, size: 14, color: Colors.blue)
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
```

---

## Implementation Priority

### ✅ **Do IMMEDIATELY (Critical):**
1. Fix timestamp parsing (1.2)
2. Process offline queue on reconnect (1.3)
3. Add message persistence (1.1)

### ⚡ **Do Next (High):**
4. Add presence subscription (2.1)
5. Display typing indicators in UI (2.2)

### 📋 **Do After (Medium):**
6. Auto-scroll to new messages (3.1)
7. Ensure optimistic updates are displayed (3.2)

---

## Testing Checklist

After implementing each phase, test:

### Phase 1 Tests:
- [ ] Send message → app restart → messages persist
- [ ] Send message offline → go online → message arrives
- [ ] Check timestamp: newly sent message shows "now" not "5h"

### Phase 2 Tests:
- [ ] User B comes online → User A sees green dot
- [ ] User A types → User B sees "User A is typing..."
- [ ] After 3 seconds of no typing → typing indicator disappears

### Phase 3 Tests:
- [ ] Send message → scrolls to bottom automatically
- [ ] Message appears with ⏱ → changes to ✓ → changes to ✓✓
- [ ] No message scroll delay

---

## Summary

You have **7 distinct issues** caused by:
- Missing persistence layer
- Timezone bugs in timestamp parsing
- Missing WebSocket subscriptions (presence)
- UI not consuming available state (typing)
- Missing optimistic update UX

The **Medium article's Firebase approach** handles these automatically, but Spring Boot + STOMP CAN work too with proper:
1. Local persistence (Hive)
2. Real-time subscriptions (presence, typing)
3. Active UI listeners (StreamBuilders or Providers)
4. Optimistic update display

This implementation plan fixes all 7 issues and brings your system to feature-parity with Firebase approach!
