# QUICK FIX GUIDE - Top 5 Bugs

## BUG #1: STOMP Subscription Not Firing (CRITICAL)

### Status: 🔴 BLOCKING - No messages received

### Suspected Root Cause
The `stomp_dart_client` library's callback may not be firing because:
1. Session ID / User ID mismatch between WebSocket and message routing
2. STOMP destination format issue (should be `/user/queue/messages`, not `/user/{userId}/queue/messages`)

### Immediate Test
Add this logging to verify subscription is even being attempted:

**File**: `chat_websocket_service.dart` lines 177-193

```dart
void _subscribeToMessageQueue() {
  final topic = '/user/queue/messages';
  
  print('═' * 50);
  print('[TEST] Attempting subscription to: $topic');
  print('[TEST] WebSocket connected: $_isConnected');
  print('[TEST] Current userId: $_currentUserId');
  print('[TEST] StompClient active: ${_stompClient.connected}');
  print('═' * 50);
  
  if (_activeSubscriptions.contains(topic)) {
    print('[ChatWebSocketService] Already subscribed to $topic');
    return;
  }

  try {
    _stompClient.subscribe(
      destination: topic,
      callback: (StompFrame frame) {
        print('\n🔥🔥🔥🔥🔥 CALLBACK FIRED! 🔥🔥🔥🔥🔥');
        print('Frame: ${frame.toString()}');
        _onMessageReceived(frame);
      },
      headers: {'id': 'sub-messages', 'ack': 'auto'},
    );
    
    _activeSubscriptions.add(topic);
    print('[SUCCESS] Subscribed to $topic');
  } catch (e) {
    print('[FAILED] Error: $e');
  }
}
```

### Backend Verification
**File**: `MessageService.java` lines 57-61

Add before sending:
```java
System.out.println("════════════════════════════════════════");
System.out.println("[SEND DEBUG] Sender ID: " + senderId);
System.out.println("[SEND DEBUG] Destination: /queue/messages");
System.out.println("[SEND DEBUG] User target: /user/" + senderId + "/queue/messages");
System.out.println("[SEND DEBUG] Response: " + response.toString());
System.out.println("════════════════════════════════════════");

messagingTemplate.convertAndSendToUser(
    senderId.toString(),
    "/queue/messages",
    response
);
```

### Action
1. Hot reload Flutter
2. Send a test message
3. **Post the full logs here** - they will reveal the exact issue

---

## BUG #2: ChatsScreen Not Updating (CRITICAL)

### Status: 🔴 BLOCKING - Conversations list never updates

### Problem Code
`chats_screen.dart` lines 35-61:
```dart
FutureBuilder<List<Conversation>>(
  future: _conversationsFuture,  // ← Loaded ONCE, never updates
  builder: (context, snapshot) { ... }
)
```

### Fix Code
```dart
Widget _buildConversationsList() {
  return Consumer<ChatStore>(
    builder: (context, chatStore, child) {
      // This rebuilds whenever chatStore.notifyListeners() is called
      return FutureBuilder<List<Conversation>>(
        future: _conversationsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(child: CircularProgressIndicator());
          }
          
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          
          final conversations = snapshot.data ?? [];
          if (conversations.isEmpty) {
            return Center(child: Text('No conversations yet'));
          }
          
          return ListView.builder(
            itemCount: conversations.length,
            itemBuilder: (context, index) {
              final conv = conversations[index];
              return _buildConversationTile(conv);
            },
          );
        },
      );
    },
  );
}
```

### Integration in Build
```dart
@override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(title: Text('Chats')),
    body: _buildConversationsList(),  // ← Use this method
    floatingActionButton: FloatingActionButton(
      onPressed: () { /* start new chat */ },
      child: Icon(Icons.message),
    ),
  );
}
```

---

## BUG #3: Message Sides Reversed (CRITICAL)

### Status: 🔴 - Sent messages show on left (receiver side)

### Location
`chat_screen.dart` - message bubble alignment

### Problem Code (Likely)
```dart
// WRONG - aligns backwards
alignment: message.senderId == currentUserId 
    ? Alignment.bottomLeft   // ❌ MY message on LEFT
    : Alignment.bottomRight  // ❌ THEIR message on RIGHT
```

### Fix Code
```dart
// CORRECT - align properly
crossAxisAlignment: message.senderId == currentUserId 
    ? CrossAxisAlignment.end     // ✅ MY message on RIGHT
    : CrossAxisAlignment.start   // ✅ THEIR message on LEFT

// OR in Align widget:
Align(
  alignment: message.senderId == currentUserId 
      ? Alignment.bottomRight   // ✅ RIGHT for sender
      : Alignment.bottomLeft,   // ✅ LEFT for receiver
  child: MessageBubble(...),
)
```

### Test
Send a message and verify:
- ✅ Your message appears on RIGHT side
- ✅ Recipient's message appears on LEFT side

---

## BUG #4: No Offline Message Persistence (MAJOR)

### Status: 🟠 - Messages lost if offline

### Problem
```dart
final List<Map<String, dynamic>> _offlineQueue = [];  // ← Cleared on app restart
```

### Fix: Use Local Database

Add to `pubspec.yaml`:
```yaml
dependencies:
  sqflite: ^2.0.0
  path_provider: ^2.0.0
```

Create new file: `lib/src/services/local_message_db.dart`

```dart
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalMessageDb {
  static const String _dbName = 'chat_messages.db';
  static const String _tableName = 'pending_messages';
  
  static Database? _database;
  
  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }
  
  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    return await openDatabase(
      join(dbPath, _dbName),
      onCreate: (db, version) {
        return db.execute(
          'CREATE TABLE $_tableName('
          'id INTEGER PRIMARY KEY,'
          'clientMessageId TEXT UNIQUE,'
          'recipientId INTEGER,'
          'content TEXT,'
          'mediaUrl TEXT,'
          'createdAt TEXT,'
          'status TEXT'
          ')',
        );
      },
      version: 1,
    );
  }
  
  Future<void> savePendingMessage({
    required String clientMessageId,
    required int recipientId,
    required String content,
    String? mediaUrl,
  }) async {
    final db = await database;
    await db.insert(
      _tableName,
      {
        'clientMessageId': clientMessageId,
        'recipientId': recipientId,
        'content': content,
        'mediaUrl': mediaUrl,
        'createdAt': DateTime.now().toIso8601String(),
        'status': 'pending',
      },
    );
  }
  
  Future<List<Map<String, dynamic>>> getPendingMessages() async {
    final db = await database;
    return await db.query(_tableName, where: 'status = ?', whereArgs: ['pending']);
  }
  
  Future<void> markMessageSent(String clientMessageId) async {
    final db = await database;
    await db.update(
      _tableName,
      {'status': 'sent'},
      where: 'clientMessageId = ?',
      whereArgs: [clientMessageId],
    );
  }
  
  Future<void> deleteMessage(String clientMessageId) async {
    final db = await database;
    await db.delete(
      _tableName,
      where: 'clientMessageId = ?',
      whereArgs: [clientMessageId],
    );
  }
}
```

### Integration in ChatWebSocketService

```dart
final LocalMessageDb _messageDb = LocalMessageDb();

@override
Future<void> connect(String token, int userId) async {
  // ... existing connection code ...
  
  // After connection succeeds, retry pending messages
  await _retryPendingMessages();
}

Future<void> _retryPendingMessages() async {
  final pending = await _messageDb.getPendingMessages();
  for (final msg in pending) {
    try {
      _sendMessageViaWebSocket(msg);
      await _messageDb.markMessageSent(msg['clientMessageId']);
    } catch (e) {
      print('[ChatWebSocketService] Failed to retry: $e');
    }
  }
}

String sendChatMessage(int recipientId, String content) {
  // ... existing code ...
  
  // Save to local DB for offline persistence
  _messageDb.savePendingMessage(
    clientMessageId: clientMessageId,
    recipientId: recipientId,
    content: content,
  );
  
  // ... rest of method ...
}
```

---

## BUG #5: No Read Receipts Processing (MAJOR)

### Status: 🟠 - Read status never updates

### Problem
Backend sends read receipts to `/queue/notifications` but frontend doesn't handle them.

### Fix: Update Notification Handler

**File**: `chat_websocket_service.dart` line 339-360

```dart
void _onNotificationReceived(StompFrame frame) {
  try {
    final data = jsonDecode(frame.body ?? '{}') as Map<String, dynamic>;
    final type = data['type'] as String?;
    
    print('[ChatWebSocketService] Notification received: type=$type');
    
    // Handle read receipts
    if (type == 'read_receipt' || type == 'read_receipts') {
      final messageIds = data['messageIds'] as List<dynamic>? ?? [];
      final fromUserId = data['fromUserId'] as int?;
      
      print('[ChatWebSocketService] ✅ Messages marked read by user $fromUserId');
      
      // Update messages in ChatStore
      if (_chatStore != null && fromUserId != null) {
        for (final msgId in messageIds) {
          _chatStore!.markMessageAsRead(fromUserId, msgId as int);
        }
      }
      
      // Notify listeners of read receipt
      _notificationController.add({
        'type': 'read_receipt',
        'messageIds': messageIds,
        'fromUserId': fromUserId,
      });
      return;
    }
    
    // Handle other notification types...
    _notificationController.add(data);
  } catch (e) {
    print('[ChatWebSocketService] Error processing notification: $e');
  }
}
```

### Add Method to ChatStore

**File**: `chat_store.dart`

```dart
void markMessageAsRead(int otherUserId, int messageId) {
  final messages = _messagesByUser[otherUserId];
  if (messages == null) return;
  
  for (var msg in messages) {
    if (msg.id == messageId) {
      final updated = msg.copyWith(
        status: MessageStatus.read,
        readAt: DateTime.now().toUtc(),
      );
      messages[messages.indexOf(msg)] = updated;
      break;
    }
  }
  
  notifyListeners();
}
```

---

## TESTING ORDER

1. ✅ Fix ChatsScreen updates (Bug #2) - easiest
2. ✅ Fix message sides (Bug #3) - quick visual check
3. ✅ Add offline persistence (Bug #4) - medium effort
4. ✅ Add read receipts (Bug #5) - medium effort
5. ❌ Debug STOMP subscription (Bug #1) - hardest, do last

Once Bug #1 is fixed, all others will work because messages will actually arrive.

