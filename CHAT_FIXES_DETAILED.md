# Chat System - Detailed Fix Guide

## ISSUE #1 & #2: Message Status & Read Receipts (CRITICAL)

### Problem Summary
- Single tick (✓) doesn't appear immediately after sending
- Double ticks (✓✓) never appear when message is read
- Backend sends correct data but frontend doesn't process it

### Fix 1A: Backend - Ensure Status is Sent

**File:** `backend/social-service/src/main/java/com/socialmedia/social/dto/MessageResponse.java`

**Current State:**
```java
@Data
@NoArgsConstructor
@AllArgsConstructor
public class MessageResponse {
    private Long id;
    private Long senderId;
    private String senderName;
    private String senderProfilePictureUrl;
    private Long receiverId;
    private String content;
    private String mediaUrl;
    private Boolean isRead;
    private LocalDateTime readAt;
    private LocalDateTime createdAt;
    private String clientMessageId;
}
```

**Action:** Add explicit status field:
```java
@Data
@NoArgsConstructor
@AllArgsConstructor
public class MessageResponse {
    // ... existing fields ...
    private String status;  // ADD: "sending", "sent", or "read"
}
```

**Then in MessageService.java mapToResponse() method, add:**
```java
// Set status based on message state
if (message.getIsRead()) {
    response.setStatus("read");
} else if (message.getId() != null && message.getId() > 0) {
    response.setStatus("sent");
} else {
    response.setStatus("sending");
}
```

---

### Fix 1B: Frontend - Read Status from Backend

**File:** `social-media-mobile/lib/src/models/message.dart`

**Current Code (Lines 63-92):**
```dart
MessageStatus status = MessageStatus.sent;

final serverId = json['id'] as int? ?? 0;
final clientId = (json['messageId'] ?? json['clientMessageId'])?.toString();

if (serverId == 0 && clientId != null) {
  status = MessageStatus.sending;
} else if (json['isRead'] == true) {
  status = MessageStatus.read;
} else {
  status = MessageStatus.sent;
}
```

**Change To:**
```dart
MessageStatus status = MessageStatus.sent;

// First, try to use explicit status from backend
final statusStr = json['status'] as String?;
if (statusStr != null) {
  switch (statusStr.toLowerCase()) {
    case 'sending':
      status = MessageStatus.sending;
      break;
    case 'read':
      status = MessageStatus.read;
      break;
    case 'sent':
    default:
      status = MessageStatus.sent;
  }
} else {
  // Fallback: infer from other fields
  final serverId = json['id'] as int? ?? 0;
  final clientId = (json['messageId'] ?? json['clientMessageId'])?.toString();
  
  if (serverId == 0 && clientId != null) {
    status = MessageStatus.sending;
  } else if (json['isRead'] == true) {
    status = MessageStatus.read;
  } else {
    status = MessageStatus.sent;
  }
}
```

---

### Fix 2: Frontend - Handle Read Receipt Notifications

**File:** `social-media-mobile/lib/src/services/chat_websocket_service.dart`

**Current Code (Lines 348-365):**
```dart
void _onNotificationReceived(StompFrame frame) {
  try {
    final data = jsonDecode(frame.body ?? '{}') as Map<String, dynamic>;
    print('[ChatWebSocketService] NOTIFICATION_RECEIVED: type=${data["type"]}, actor=${data["actorId"]}');
    
    // Broadcast to all notification listeners
    for (var listener in _notificationListeners) {
      listener(data);
    }
    
    // Also emit to the stream for other services (CallSignalingService, etc)
    _notificationController.add(data);
  } catch (e) {
    print('[ChatWebSocketService] Error parsing notification: $e');
  }
}
```

**Add After (Before the closing brace):**
```dart
void _onNotificationReceived(StompFrame frame) {
  try {
    final data = jsonDecode(frame.body ?? '{}') as Map<String, dynamic>;
    final notificationType = data["type"] as String? ?? '';
    
    print('[ChatWebSocketService] NOTIFICATION_RECEIVED: type=$notificationType');
    
    // Handle read receipts
    if (notificationType == 'read_receipt' || notificationType == 'read_receipts') {
      print('[ChatWebSocketService] 📖 Read receipt received');
      _handleReadReceipt(data);
      return; // Don't broadcast to listeners, handle internally
    }
    
    // Broadcast other notifications to listeners
    for (var listener in _notificationListeners) {
      listener(data);
    }
    
    // Also emit to the stream for other services (CallSignalingService, etc)
    _notificationController.add(data);
  } catch (e) {
    print('[ChatWebSocketService] Error parsing notification: $e');
  }
}

/// Handle read receipts from server
void _handleReadReceipt(Map<String, dynamic> notification) {
  try {
    final messageIds = (notification['messageIds'] as List?)
        ?.map((id) => (id as num?)?.toInt() ?? 0)
        .where((id) => id > 0)
        .toList() ?? [];
    
    final fromUserId = (notification['fromUserId'] as num?)?.toInt();
    
    print('[ChatWebSocketService] 📖 Processing read receipt from user=$fromUserId for ${messageIds.length} messages');
    
    if (fromUserId != null && fromUserId > 0 && messageIds.isNotEmpty && _chatStore != null) {
      // Mark messages as read in ChatStore
      _chatStore!.markMessagesRead(
        fromUserId,
        messageIds: messageIds,
        currentUserId: _currentUserId,
      );
      print('[ChatWebSocketService] ✅ Read receipt processed and messages marked');
    }
  } catch (e) {
    print('[ChatWebSocketService] ❌ Error handling read receipt: $e');
  }
}
```

---

### Fix 3: Backend - Fix Typing Indicator Routing

**File:** `backend/social-service/src/main/java/com/socialmedia/social/controller/MessageController.java`

**Current Code (Lines 160-177):**
```java
@MessageMapping("/chat.typing")
public void handleTypingViaWebSocket(@Payload com.socialmedia.social.dto.TypingRequest request,
                                     SimpMessageHeaderAccessor headerAccessor) {
  try {
    // ... code ...
    
    // Forward typing event to the recipient's notifications queue
    try {
        messagingTemplate.convertAndSendToUser(
            request.getReceiverId().toString(),
            "/queue/notifications",  // ❌ WRONG QUEUE!
            payload);
```

**Change To:**
```java
    // Forward typing event to the recipient's typing queue
    try {
        messagingTemplate.convertAndSendToUser(
            request.getReceiverId().toString(),
            "/queue/typing",  // ✅ CORRECT QUEUE
            payload);
```

---

## ISSUE #3: Own Messages Showing as Unread

### Problem Summary
When you send a message to someone, it shows as unread badge on your chat card

### Fix: Verify Backend Sends Correct RecipientId

**File:** `backend/social-service/src/main/java/com/socialmedia/social/service/MessageService.java`

**Check mapToResponse() method (Lines 306-340):**
```java
private MessageResponse mapToResponse(Message message) {
    MessageResponse response = new MessageResponse();
    response.setId(message.getId());
    response.setSenderId(message.getSenderId());
    response.setReceiverId(message.getReceiverId());  // ✅ MUST BE SET
    // ... rest of fields ...
}
```

**Also verify in getConversations() method (Line 297-298):**
```java
// The unreadCount calculation is CORRECT:
Long unreadCount = messageRepository.countUnreadMessagesBetween(userId, partnerId);
// This only counts messages where recipientId == userId AND isRead == false
```

If the issue still exists after this, check that:
1. Database actually stores correct `receiverId` values
2. Frontend is reading `receiverId` from the response

---

## ISSUE #4: Read Messages Still Show Badge Count

### Problem Summary
Even after you read messages, the unread count badge still shows

### Fix 1: Send Message IDs When Marking as Read

**File:** `social-media-mobile/lib/src/state/chat_store.dart`

**Current Code (Lines 309-313):**
```dart
if (changed) {
  _messagesByUser[otherUserId] = newList..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  print('[CHATSTORE] markMessagesRead applied...');
  
  // Send read receipt to server via WebSocket
  try {
    final wsService = ChatWebSocketService();
    if (wsService.isConnected && idsSet.isNotEmpty) {
      wsService.sendReadReceipt(otherUserId, idsSet.toList());
    }
```

**Change To:**
```dart
if (changed) {
  _messagesByUser[otherUserId] = newList..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  print('[CHATSTORE] markMessagesRead applied...');
  
  // Collect ALL message IDs that were marked (whether explicit or all unread)
  List<int> allMarkedIds = newList
      .where((m) => m.readAt != null && m.recipientId == effCurrentUserId)
      .map((m) => m.id)
      .where((id) => id > 0)
      .toList();
  
  print('[CHATSTORE] Marked ${allMarkedIds.length} messages as read, sending to backend');
  
  // Send read receipt to server via WebSocket
  try {
    final wsService = ChatWebSocketService();
    if (wsService.isConnected && allMarkedIds.isNotEmpty) {
      wsService.sendReadReceipt(otherUserId, allMarkedIds);
    }
  } catch (e) {
    print('[CHATSTORE] Failed to send read receipt: $e');
  }
```

---

## ISSUE #5: Wrong Message Timestamps

### Problem Summary
Message times are wrong, don't update correctly, show stale times

### Fix 1: Never Fallback to Current Time

**File:** `social-media-mobile/lib/src/models/message.dart`

**Current Code (Lines 89-92):**
```dart
createdAt: json['createdAt'] != null
    ? DateTime.parse(json['createdAt'] as String)
    : DateTime.now().toUtc(),  // ❌ WRONG FALLBACK!
```

**Change To:**
```dart
createdAt: json['createdAt'] != null
    ? DateTime.parse(json['createdAt'] as String)
    : DateTime(1970, 1, 1).toUtc(),  // Fallback to epoch (1970) instead of "now"
    // This way, messages with missing timestamps appear at the bottom chronologically
```

### Fix 2: Handle Timezone Properly

**Current Code (Lines 113-122):**
```dart
String get timeAgo {
  final now = DateTime.now().toUtc();
  final messageTime = createdAt.isUtc ? createdAt : createdAt.toUtc();
  // ...
}
```

**This is actually correct!** But make sure `createdAt` is always UTC from backend.

### Fix 3: Backend Must Always Send createdAt

**File:** `backend/social-service/src/main/java/com/socialmedia/social/entity/Message.java`

**Check that createdAt is set (Lines 47-49):**
```java
@CreationTimestamp
@Column(nullable = false, updatable = false)
private LocalDateTime createdAt;  // ✅ @CreationTimestamp auto-sets on insert
```

This should auto-set to current database time. Verify in database configuration that timezone is UTC.

---

## ISSUE #6: No Typing Indicators (Already Fixed Above)
See Fix 3 in Issue #1 section

---

## ISSUE #7: No Online Status Indicator

### Root Cause
No presence/online service implemented

### Quick Fix (Workaround)
```dart
// In chat_websocket_service.dart, add method:
void sendPresenceUpdate(bool isOnline) {
  if (!_isConnected) return;
  
  try {
    _stompClient.send(
      destination: '/app/presence.update',
      body: jsonEncode({
        'userId': _currentUserId,
        'isOnline': isOnline,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      }),
      headers: {'content-type': 'application/json'},
    );
    print('[ChatWebSocketService] ✅ Presence update sent: isOnline=$isOnline');
  } catch (e) {
    print('[ChatWebSocketService] ❌ Error sending presence: $e');
  }
}
```

Then call:
- `sendPresenceUpdate(true)` when app enters foreground
- `sendPresenceUpdate(false)` when app enters background

---

## ISSUE #8: Message Status Not Persisted

### Root Cause
No status field in database

### Long-term Fix (Database Migration)
```sql
-- Add status column to messages table
ALTER TABLE messages ADD COLUMN status VARCHAR(50) DEFAULT 'sent';

-- Update existing rows
UPDATE messages SET status = 'read' WHERE isRead = true;
UPDATE messages SET status = 'sent' WHERE isRead = false;
```

### Backend Update
```java
// In Message.java entity, add:
@Column(length = 50)
private String status = "sent";  // or use enum

// In MessageService.java, set when creating:
message.setStatus("sent");
// When marking as read:
message.setStatus("read");
```

---

## Testing Checklist

- [ ] Send message → single tick appears immediately (Issue #1)
- [ ] Recipient reads message → double ticks appear (Issue #2)
- [ ] Open chat with unread → badge clears immediately (Issue #4)
- [ ] Typing indicator shows "User is typing..." (Issue #6)
- [ ] Messages show correct timestamps (Issue #5)
- [ ] Own messages don't show badge on your side (Issue #3)
- [ ] Online status indicator shows (Issue #7)

