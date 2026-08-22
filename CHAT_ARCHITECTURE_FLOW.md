# Chat Message Flow Architecture

## Complete Message Journey

```
┌─────────────────────────────────────────────────────────────────┐
│ STEP 1: USER INTERFACE                                          │
│ User opens ChatScreen for conversation with userId=123          │
│ Receives from ChatStore via Consumer<ChatStore>                 │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 2: USER SENDS MESSAGE                                      │
│ User types "hello" and clicks send button                       │
│ _sendMessage() is triggered                                     │
│                                                                 │
│ Logs:                                                           │
│   [Chat] 📤 SENDING MESSAGE                                    │
│   [Chat] ├─ To userId: 123                                     │
│   [Chat] ├─ WebSocket connected: true                          │
│   [Chat] └─ ChatStore: ✅ initialized                          │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 3: WEBSOCKET SERVICE RECEIVES SEND REQUEST                 │
│ _sendMessage() calls:                                           │
│   _webSocketService.sendChatMessage(                            │
│     recipientId=123,                                            │
│     content="hello"                                             │
│   )                                                             │
│                                                                 │
│ Service checks:                                                 │
│   ✅ _currentUserId > 0? (should be 456, your user)            │
│   ✅ _chatStore != null? (should be true)                      │
│   ✅ Generate unique clientMessageId (abc123_456789)           │
│                                                                 │
│ Logs:                                                           │
│   [ChatWebSocketService] ===== SEND_CHAT_MESSAGE =====         │
│   [ChatWebSocketService] ✅ Sender ID: 456                     │
│   [ChatWebSocketService] ✅ ChatStore: initialized             │
│   [ChatWebSocketService] ✅ Generated clientMessageId          │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 4: CREATE OPTIMISTIC MESSAGE                               │
│ Service creates Message object:                                 │
│   - id = 0 (not yet assigned by server)                        │
│   - clientMessageId = "abc123_456789"                          │
│   - senderId = 456 (you)                                       │
│   - recipientId = 123 (them)                                   │
│   - content = "hello"                                          │
│   - status = MessageStatus.sending (⏱)                        │
│   - createdAt = now()                                          │
│                                                                 │
│ Logs:                                                           │
│   [ChatWebSocketService] ✅ Generated clientMessageId          │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 5: ADD TO STATE MANAGEMENT (UI UPDATES IMMEDIATELY!)       │
│ Service calls:                                                  │
│   _chatStore!.addIncomingMessage(optimisticMessage, userId)   │
│                                                                 │
│ ChatStore does:                                                │
│   1. Gets otherUserId = (senderId==currentUserId)              │
│      ? recipientId : senderId = 123                            │
│   2. Gets messages list for user 123                           │
│   3. Adds optimistic message to list                           │
│   4. Calls notifyListeners() ← UI REBUILDS HERE!              │
│                                                                 │
│ Logs:                                                           │
│   [ChatWebSocketService] ✅ Optimistic message added           │
│   [ChatWebSocketService]    └─ status: sending (⏱)           │
│   [ChatStore] ✅ INSERT new message                            │
│   [ChatStore] 📢 notifyListeners() called                      │
│                                                                 │
│ UI RESULT:                                                      │
│   Consumer<ChatStore> rebuilds                                 │
│   messagesForUser(123) now includes the message                │
│   ListView rebuilds and shows:                                 │
│   💬 hello  ⏱  (clock icon = sending)                        │
│       (in blue bubble on right side, your messages)            │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 6: SEND TO BACKEND                                         │
│ Check connection status:                                        │
│   if (_isConnected == true)                                    │
│     → Send immediately                                         │
│   else                                                         │
│     → Queue for later                                          │
│                                                                 │
│ Service sends via STOMP:                                       │
│   destination: "/app/chat.send"                                │
│   body: {                                                      │
│     "clientMessageId": "abc123_456789",                        │
│     "recipientId": 123,                                        │
│     "content": "hello",                                        │
│     "timestamp": "2024-01-15T10:30:45.123Z"                   │
│   }                                                            │
│                                                                 │
│ Logs:                                                           │
│   [ChatWebSocketService] ✅ SENT to WebSocket: /app/chat.send │
│   [Chat] ✅ Message queued: clientId=abc123...               │
└─────────────────────────────────────────────────────────────────┘
                              ↓
                          ⏳ NETWORK ⏳
                    (Backend processes message)
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 7: BACKEND RECEIVES & CONFIRMS                             │
│ Backend MessageController receives at /app/chat.send:           │
│   1. Validates message format and permissions                  │
│   2. Saves to database (assigns server id = 999)              │
│   3. Sends MESSAGE_RECEIVED back to sender                    │
│      destination: "/user/456/queue/messages"                  │
│      body: {                                                   │
│        "id": 999 (NEW - server assigned),                     │
│        "clientMessageId": "abc123_456789",                    │
│        "senderId": 456,                                       │
│        "recipientId": 123,                                    │
│        "content": "hello",                                    │
│        "status": "SENT"                                       │
│      }                                                         │
│   4. Also sends to recipient at /user/123/queue/messages     │
│                                                                 │
│ Network time: ~100-500ms                                       │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 8: SENDER RECEIVES CONFIRMATION                            │
│ WebSocket subscription /user/456/queue/messages receives:       │
│   → _onMessageReceived(StompFrame) is called                   │
│   → Data contains: id=999, clientMessageId=abc123_456789      │
│                                                                 │
│ Service identifies this was OUR message because:                │
│   - clientMessageId exists in messageStates map               │
│   - Means WE sent this (tracked optimistic state)             │
│                                                                 │
│ Reconciliation happens:                                         │
│   1. Find existing message with clientId=abc123_456789         │
│   2. Replace optimistic (id=0) with confirmed (id=999)        │
│   3. Update status from "sending" to "sent"                   │
│                                                                 │
│ Logs:                                                           │
│   [ChatWebSocketService] ===== MESSAGE_RECEIVED =====          │
│   [ChatWebSocketService] ✅ Reconciled our message!            │
│   [ChatWebSocketService]    └─ status: sent (✓)              │
│   [ChatStore] 🔄 RECONCILE message                            │
│   [ChatStore] 📢 notifyListeners() called                      │
│                                                                 │
│ UI RESULT:                                                      │
│   Consumer<ChatStore> rebuilds                                 │
│   Message status changed: ⏱ → ✓                              │
│   ListView updates and shows:                                  │
│   💬 hello  ✓  (checkmark = delivered/sent)                  │
│       (still in blue bubble on right side)                     │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 9: RECIPIENT RECEIVES MESSAGE (ON OTHER DEVICE)            │
│ Meanwhile, recipient's WebSocket subscription receives:         │
│   → /user/123/queue/messages gets the message                 │
│   → _onMessageReceived(StompFrame) is called                  │
│   → Data contains: id=999, senderId=456, content="hello"      │
│                                                                 │
│ Service identifies this is FROM someone else:                  │
│   - clientMessageId present but NOT in messageStates          │
│   - Means someone ELSE sent this                              │
│                                                                 │
│ Service adds to store:                                         │
│   _chatStore!.addIncomingMessage(message, currentUserId=123)  │
│                                                                 │
│ Logs on Recipient Device:                                      │
│   [ChatWebSocketService] ===== MESSAGE_RECEIVED =====          │
│   [ChatWebSocketService] ✅ Added incoming message from 456   │
│   [ChatStore] ✅ INSERT new message                            │
│   [ChatStore] 📢 notifyListeners() called                      │
│                                                                 │
│ UI RESULT on Recipient Device:                                 │
│   Consumer<ChatStore> rebuilds                                 │
│   messagesForUser(456) now includes the message                │
│   ListView rebuilds and shows:                                 │
│   💬 hello  ✓  (checkmark = sent by them)                    │
│       (in gray bubble on LEFT side, their messages)            │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 10: PERSISTENCE & NAVIGATION                               │
│ Message is now:                                                 │
│   ✅ In database on server (persisted)                         │
│   ✅ In ChatStore._messagesByUser[123] (in memory)            │
│   ✅ Visible in UI on both devices                            │
│   ✅ Status = "SENT"/"DELIVERED"                              │
│                                                                 │
│ If user navigates back to conversations list:                  │
│   - ChatStore NOT cleared                                      │
│   - Message remains in _messagesByUser[123]                   │
│   - When opening conversation again, message appears          │
│                                                                 │
│ If app restarts:                                               │
│   - ChatStore is cleared (memory)                              │
│   - But next time chat opens, fetches from server              │
│   - Message persists because in database                       │
└─────────────────────────────────────────────────────────────────┘
```

## State Flow Diagram

```
BEFORE SEND:
  ChatStore._messagesByUser[123] = [old message 1, old message 2]
  UI shows: 2 messages

AFTER SEND (IMMEDIATELY):
  ChatStore._messagesByUser[123] = [
    old message 1,
    old message 2,
    {id:0, clientId:abc123, status:sending} ← NEW OPTIMISTIC
  ]
  UI shows: 3 messages, last one with ⏱

AFTER SERVER CONFIRMS (1-2 seconds later):
  ChatStore._messagesByUser[123] = [
    old message 1,
    old message 2,
    {id:999, clientId:abc123, status:sent} ← RECONCILED
  ]
  UI shows: 3 messages, last one with ✓ (updated)
```

## Critical Dependencies

### For Message to Appear in UI (⏱):
```
✅ _currentUserId > 0 (must be set during login via connect())
✅ _chatStore != null (must be injected in main.dart)
✅ WebSocket subscribed to /user/{id}/queue/messages
✅ Consumer<ChatStore> in build() using messagesForUser()
```

### For Message to Change to ✓:
```
✅ Server receives message at /app/chat.send
✅ Server saves to database (assigns id)
✅ Server sends MESSAGE_RECEIVED back
✅ Client receives on /user/{id}/queue/messages
✅ Message found in messageStates (tracked as ours)
✅ _chatStore.addIncomingMessage() called with new id
✅ notifyListeners() triggers rebuild
```

### For Message to Persist:
```
✅ Message in ChatStore._messagesByUser (until app restart)
✅ Message in database on server (permanent)
✅ When chat reopens, fetches from server if needed
```

## Files Involved

| Component | File | Key Method |
|-----------|------|------------|
| **UI** | chat_screen.dart | `_sendMessage()` |
| **Service** | chat_websocket_service.dart | `sendChatMessage()`, `_onMessageReceived()` |
| **State** | chat_store.dart | `addIncomingMessage()`, `messagesForUser()` |
| **Model** | message.dart | `Message.fromJson()`, `copyWith()` |
| **Backend** | MessageController.java | `sendMessage()`, sends to queue |

## When Things Go Wrong

### If ⏱ appears but never changes to ✓:
```
MESSAGE_RECEIVED not arriving → Server not responding
↓
Check: Backend logs for errors
Check: Message saved to database?
Check: WebSocket subscription active?
```

### If ⏱ never appears in UI:
```
INSERT new message not logged → ChatStore not called
↓
Check: _chatStore != null?
Check: notifyListeners() called?
Check: Consumer<ChatStore> exists in UI?
```

### If error on send:
```
ERROR: _currentUserId not set → User ID not in WebSocket
↓
Check: connect(token, userId) called?
Check: User actually logged in?
```

## Summary

The flow is:
1. **User types + clicks send** → ChatScreen._sendMessage()
2. **Validates + creates optimistic message** → ChatWebSocketService.sendChatMessage()
3. **Adds to state immediately** → ChatStore.addIncomingMessage() → UI shows ⏱
4. **Sends to backend** → STOMP /app/chat.send
5. **Backend confirms** → /user/{id}/queue/messages
6. **Reconciles with server id** → ChatStore.addIncomingMessage() again → UI shows ✓
7. **Backend sends to recipient** → /user/{recipientId}/queue/messages
8. **Recipient's ChatStore updates** → UI shows message on their device

Each step has **logging** that tells you exactly what happened. Use those logs to identify which step is broken!

