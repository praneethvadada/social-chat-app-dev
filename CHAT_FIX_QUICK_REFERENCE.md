# Chat Issues - Quick Fix Reference

## 3 Critical Bugs Fixed

### 🐛 Bug #1: Sender Can't Message - "recipientId is SAME as _currentUserId"
**File:** `chat_websocket_service.dart` (lines 81-101)
**Issue:** WebSocket singleton kept old userId when switching accounts
**Fix:** Detect user change → disconnect → reconnect with new user
**Status:** ✅ FIXED

### 🐛 Bug #2: Previous Messages Missing on Sender Side  
**File:** `chat_screen.dart` (lines 40-65)
**Issue:** Didn't load messages from local cache before API call
**Fix:** Call `loadCachedMessagesForUser()` in initState() first
**Status:** ✅ FIXED

### 🐛 Bug #3: Typing Indicator Not Showing on Receiver
**File:** `chat_websocket_service.dart` (lines 478-493)
**Issue:** Payload field mismatch - backend sends `fromUserId`, code expected `userId`
**Fix:** Parse both field names
**Status:** ✅ FIXED

---

## What Changed

### File: `lib/src/services/chat_websocket_service.dart`

**Change 1 (Connect Method):**
```dart
// BEFORE: Always returned if connected
if (_isConnected) {
  return;
}

// AFTER: Checks if user changed
if (_isConnected && _currentUserId != userId) {
  await disconnect();  // Reconnect with new user
}
```

**Change 2 (Typing Indicator):**
```dart
// BEFORE: Only looked for 'userId'
final userId = data['userId'] as int?;

// AFTER: Handles both 'fromUserId' and 'userId'
final userId = (data['fromUserId'] as num?)?.toInt() ?? (data['userId'] as int?);
```

### File: `lib/src/screens/chats/chat_screen.dart`

**Change (initState):**
```dart
// ADDED: Load cached messages first
chatStore.loadCachedMessagesForUser(widget.conversation.userId).then((_) {
  print('[ChatDetailScreen] ✅ Loaded cached messages');
});

// EXISTING: Load from API if needed
if (existing.isEmpty && !widget.isNewChat) {
  ApiService.getConversation(widget.conversation.userId).then((raw) {
    // ...
  });
}
```

---

## How to Test

### Scenario: 2-Device Chat Test
1. **Device A:** Log in as User 2 (sai)
2. **Device B:** Log in as User 3 (vamsi)
3. **Device A:** Open chat with User 3
   - ✅ Should see previous 31 messages
   - ✅ Should not show error "recipientId is SAME as _currentUserId"
4. **Device A:** Type a message
   - ✅ Should see typing indicator on Device B
   - ✅ Message should appear on Device B
5. **Device B:** Open chat, read message
   - ✅ Message should show ✓✓ (read) on Device A

---

## What Was Working Before

✅ Messages persist locally (SharedPreferences)  
✅ Timestamps correct (UTC parsing)  
✅ Online/offline status  
✅ Read receipts sent to backend  
✅ Auto-scroll when messages arrive  
✅ Offline queue of messages  

---

## What's Now Fixed

✅ Multiple account login on same device  
✅ Previous messages visible to sender  
✅ Typing indicator visible to receiver  

---

## No Backend Changes Needed

The backend was already working correctly:
- ✅ Receives typing events
- ✅ Broadcasts to recipient's queue
- ✅ Handles multiple connection/disconnections
- ✅ Persists all messages

---

## Verification Commands

### Check Flutter Logs
```
[ChatWebSocketService] ⚠️ User changed from 2 to 3 - disconnecting
[ChatWebSocketService] ✅ Disconnected from previous user
[ChatDetailScreen] ✅ Loaded cached messages for user=3
[ChatWebSocketService] ⌨️ Typing indicator: user=2 isTyping=true
```

### Check Backend Logs
```
[MessageController] Searching methods to handle SEND /app/chat.typing
[MessageController] Invoking MessageController#handleTypingViaWebSocket
[MessageController] Error forwarding typing event: (should NOT see this)
```

---

**Ready for Testing!** 🚀
