# Read Receipt Debugging - Step by Step Fix

## Issue: One device shows ✓, other shows ✓✓ 

### Root Cause Analysis

The problem is likely one of these:

1. **Message IDs don't match**
   - Device A sends message with server ID = 123
   - Device B receives same message but with different ID or no ID
   - Read receipt references message 123, but Device A doesn't find it

2. **Message status not updating**
   - Read receipt is received correctly
   - But message isn't found in the messages list
   - Or status update isn't triggering UI rebuild

3. **Database sync issues**
   - Message saved to SQLite on one device
   - But not on another after reload
   - Each device has different view of "read" status

### Debugging Steps

#### Step 1: Verify Message IDs Are Consistent

Add logging to chat_websocket_service.dart - when message is received:
```dart
void addIncomingMessage(Message msg) {
  print('[WebSocket] ✅ Message received: id=${msg.id}, clientId=${msg.clientMessageId}');
}
```

Add logging to markMessagesAsReadByRecipient:
```dart
void markMessagesAsReadByRecipient(int otherUserId, List<int> messageIds) {
  final messages = _messagesByUser[otherUserId];
  print('[CHATSTORE] Trying to mark IDs: $messageIds');
  print('[CHATSTORE] Available message IDs: ${messages?.map((m) => m.id).toList()}');
  // ... rest of logic
}
```

#### Step 2: Verify Read Receipt Is Being Received

In chat_websocket_service.dart `_handleReadReceipt`:
```dart
print('[ChatWebSocketService] 📖 Received read receipt for IDs: $messageIds');
print('[ChatWebSocketService] 📖 Will try to mark as read for otherUserId: $fromUserId');
```

#### Step 3: Verify Database Persistence

After `markMessagesAsReadByRecipient` completes:
```dart
final markedMessages = messages.where((m) => m.status == MessageStatus.read).toList();
print('[CHATSTORE] Messages now marked as read: ${markedMessages.map((m) => m.id).toList()}');
```

### Critical Implementation Points

#### Backend: Correct Read Receipt Response

```java
@MessageMapping("/chat.read")
public void handleReadReceiptViaWebSocket(@Payload Map<String, Object> payload, SimpMessageHeaderAccessor headerAccessor) {
    // userId = person who is READING (e.g., Device B user)
    Long userId = getUserIdFromSession(headerAccessor);
    
    // otherUserId = person being sent to (e.g., Device A user)
    Long otherUserId = ((Number) payload.get("otherUserId")).longValue();
    
    // messageIds = IDs of messages that are being read
    List<Long> messageIds = extractMessageIds(payload);
    
    // STEP 1: Mark in database
    messageService.markMessagesAsRead(messageIds, userId);
    
    // STEP 2: Send response back to SENDER (otherUserId)
    Map<String, Object> response = new HashMap<>();
    response.put("type", "read_receipt");
    response.put("fromUserId", userId);      // WHO read it (Device B user)
    response.put("toUserId", otherUserId);   // WHO should receive this (Device A user)
    response.put("messageIds", messageIds);  // WHICH messages
    response.put("timestamp", now());
    
    // CRITICAL: Send to otherUserId (the sender), not userId
    messagingTemplate.convertAndSendToUser(
        otherUserId.toString(),  // Device A user
        "/queue/read-receipts",
        response
    );
}
```

#### Frontend: Correctly Handle Read Receipt

```dart
void _handleReadReceipt(Map<String, dynamic> data) {
    final messageIds = data['messageIds'] as List?;
    final fromUserId = data['fromUserId'] as int?;
    
    // fromUserId = person who read it
    // In this conversation with fromUserId, mark our sent messages as read
    
    if (_chatStore != null) {
        print('[WebSocket] 📖 Marking messages as read: $messageIds from user $fromUserId');
        _chatStore!.markMessagesAsReadByRecipient(fromUserId, messageIds.cast<int>());
    }
}
```

#### ChatStore: Match Messages and Update

```dart
void markMessagesAsReadByRecipient(int otherUserId, List<int> messageIds) {
    final messages = _messagesByUser[otherUserId];
    if (messages == null) return;
    
    final idsSet = Set<int>.from(messageIds);
    final updated = messages.map((m) {
        // Only update if:
        // 1. ID matches one we're looking for
        // 2. We sent it (senderId == currentUserId)
        // 3. Not already marked as read
        
        if (idsSet.contains(m.id) && 
            m.senderId == _currentUserId && 
            m.status != MessageStatus.read) {
            
            return m.copyWith(
                status: MessageStatus.read,
                isRead: true,
                readAt: DateTime.now().toUtc()
            );
        }
        return m;
    }).toList();
    
    _messagesByUser[otherUserId] = updated;
    notifyListeners();  // CRITICAL: Trigger UI rebuild
}
```

### Testing Procedure

1. **Device A** sends message → shows ✓
2. **Device B** opens chat → should show ✓ (unread)
3. **Wait 2 seconds** (for read receipt to be sent)
4. **Device A** should now show ✓✓

If not:
- Check Device A logs for "READ_RECEIPT RECEIVED"
- Check if message IDs match in both logs
- Check if `markMessagesAsReadByRecipient` is being called

### Common Issues and Fixes

**Issue 1: Message ID mismatch**
- Device A creates message with clientMessageId only
- Server returns message with server ID
- Device B receives server ID
- Read receipt references server ID, but Device A only has clientId

**Fix**: Store both clientMessageId AND server ID in message

**Issue 2: Status not updating in UI**
- Read receipt received and ChatStore updated
- But UI doesn't rebuild

**Fix**: Ensure `notifyListeners()` is called after update

**Issue 3: Database not persisting**
- Read receipt updates in memory only
- Closing app loses the status

**Fix**: Ensure `_persistence.saveMessage()` is called for each updated message

### Verification Checklist

- [  ] Backend sends read receipt to SENDER (otherUserId)
- [  ] Read receipt includes correct messageIds
- [  ] Frontend receives read receipt in `_handleReadReceipt`
- [  ] `markMessagesAsReadByRecipient` finds matching messages
- [  ] Message status is updated to `MessageStatus.read`
- [  ] `notifyListeners()` is called to trigger UI rebuild
- [  ] Message is persisted to SQLite with new status
- [  ] App restart shows persisted ✓✓ status
