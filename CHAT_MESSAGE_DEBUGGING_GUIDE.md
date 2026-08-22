# Chat Message Delivery Debugging Guide

## Problem Summary
Messages show ⏱ (sending) instead of ✓ (sent), don't appear on receiver side, and disappear when navigating back.

## Message Flow Expected

```
User clicks send
↓
ChatScreen._sendMessage()
├─ Gets text from controller
├─ Calls _webSocketService.sendChatMessage(recipientId, content)
└─ Prints: "[Chat] 📤 Sending message to userId=..."
    
ChatWebSocketService.sendChatMessage()
├─ Validates _currentUserId > 0
├─ Validates _chatStore != null
├─ Creates optimistic Message (status=sending)
├─ Calls _chatStore.addIncomingMessage() → UI UPDATES IMMEDIATELY with ⏱
└─ If connected: calls _sendMessageViaWebSocket()
    └─ Sends to /app/chat.send via STOMP
    
ChatStore.addIncomingMessage()
├─ Stores message in _messagesByUser[otherUserId]
├─ Calls notifyListeners()
└─ Consumer<ChatStore> rebuilds, message appears in UI with status=sending

Server receives /app/chat.send
├─ Stores message in database
├─ Sends MESSAGE_RECEIVED back to /user/{senderId}/queue/messages
└─ Includes: id (server DB id), clientMessageId, status

ChatWebSocketService._onMessageReceived()
├─ Receives MESSAGE_RECEIVED event
├─ Finds optimistic message by clientMessageId
├─ Calls _chatStore.addIncomingMessage(message_with_server_id)
└─ ChatStore reconciles: replaces optimistic with confirmed (status=sent, id=xxx)
    
UI Updates
├─ Consumer<ChatStore> sees updated message
├─ Message now shows ✓ (sent) instead of ⏱
└─ Message persisted in ChatStore._messagesByUser

Message Delivery to Receiver
├─ Server sends message to /user/{recipientId}/queue/messages
├─ Receiver's WebSocket receives in _onMessageReceived()
├─ Receiver's ChatStore gets updated
└─ Receiver's ChatScreen shows message from otherUserId
```

## Critical Checkpoints

### Checkpoint 1: Initial Setup
- [ ] User is logged in and has a valid token
- [ ] User ID is > 0
- [ ] WebSocket connected at app startup
- [ ] ChatStore is injected into WebSocketService

### Checkpoint 2: Message Sending
- [ ] `_sendMessage()` is triggered when send button is clicked
- [ ] Message text is not empty
- [ ] `_currentUserId` in WebSocketService is > 0
- [ ] `_chatStore` in WebSocketService is not null
- [ ] `isConnected` is true

### Checkpoint 3: Optimistic Update
- [ ] Message appears in UI with ⏱ immediately after send
- [ ] Message is in ChatStore._messagesByUser[recipientId]
- [ ] ChatStore.notifyListeners() was called

### Checkpoint 4: Message Transmission
- [ ] STOMP message sent to /app/chat.send
- [ ] Server received the message (check backend logs)
- [ ] Server stored message in database

### Checkpoint 5: Server Acknowledgment
- [ ] Server sent MESSAGE_RECEIVED back to /user/{senderId}/queue/messages
- [ ] WebSocket received MESSAGE_RECEIVED event
- [ ] Message reconciled with server id
- [ ] Message status updated to ✓ (sent)

### Checkpoint 6: Persistence
- [ ] Message remains in ChatStore after navigation
- [ ] Message is still visible when returning to chat
- [ ] Message count in ChatStore is correct

### Checkpoint 7: Receiver Side
- [ ] Receiver's WebSocket received message
- [ ] Receiver's ChatStore got updated
- [ ] Receiver's UI shows message
- [ ] Receiver can see sender's id correctly

## Step-by-Step Testing

### Test 1: Run and Monitor Logs
```bash
# Terminal 1: Start the app
flutter run

# Terminal 2: Monitor logs (in another terminal)
flutter logs | grep -E "\[Chat\]|\[ChatWebSocketService\]|\[CHATSTORE\]"
```

### Test 2: Send a Message and Check Logs

**What to look for:**

1. **When you click send button:**
```
[Chat] 📤 Sending message to userId=123
[Chat] WebSocket connected: true/false
```

2. **In ChatWebSocketService:**
```
[ChatWebSocketService] ❌ ERROR: _currentUserId not set (0)   ← IF THIS APPEARS = PROBLEM #1
[ChatWebSocketService] ❌ CRITICAL ERROR: ChatStore is null  ← IF THIS APPEARS = PROBLEM #2
[ChatWebSocketService] ✅ Optimistic message added: clientId=abc123_456789, to=123, status=sending
[ChatWebSocketService] 📤 Message sent via WebSocket         ← Should appear if connected
[ChatWebSocketService] ⚠️ WebSocket not connected, message queued: abc123_456789  ← If disconnected
```

3. **In ChatStore:**
```
[CHATSTORE] insert incoming otherUserId=123 clientId=abc123_456789 id=0
```

4. **Message status update:**
```
[ChatWebSocketService] MESSAGE_RECEIVED: id, clientMessageId, recipientId, ...
[ChatWebSocketService] Reconciled optimistic message: abc123_456789
[CHATSTORE] reconcile message otherUserId=123 clientId=abc123_456789 id=999
```

### Test 3: Message Persistence
- Send a message (should show ⏱ then ✓)
- Press back button to return to conversations list
- Open the same conversation again
- **Expected**: Message should still be there with ✓ status
- **If missing**: Problem with ChatStore persistence

### Test 4: Receiver Side
- Use two devices/emulators
- Device A sends message to Device B
- Check Device B's logs for:
```
[ChatWebSocketService] MESSAGE_RECEIVED: id, clientMessageId, senderId=<Device A userId>, ...
[ChatWebSocketService] Added incoming message from user=<Device A userId>
[CHATSTORE] insert incoming otherUserId=<Device A userId> clientId=... id=999
```
- Device B should show message in chat immediately

## Possible Issues and Solutions

### Issue 1: `_currentUserId not set (0)`
**Root Cause**: WebSocket service's `_currentUserId` is 0
**Symptoms**:
- Message send button is clickable but fails silently
- Error thrown but caught (no crash)
- Log shows: `[ChatWebSocketService] ❌ ERROR: _currentUserId not set (0)`

**Solutions**:
1. Check if user is logged in (not in guest mode)
2. Verify `ChatWebSocketService().connect(token, userId)` was called in main.dart
3. Check if login flow calls the correct endpoints
4. Add log to main.dart: `print('[MAIN] ✅ WebSocket user set to: $userId')`

**Test**:
```bash
# In chat_screen.dart _sendMessage(), add before calling sendChatMessage:
print('[Chat] WebSocketService._currentUserId = ${_webSocketService._currentUserId}');  // Should be > 0
```

### Issue 2: `ChatStore is null`
**Root Cause**: ChatStore was not injected into WebSocket service
**Symptoms**:
- Message send button works but message never appears
- Log shows: `[ChatWebSocketService] ❌ CRITICAL ERROR: ChatStore is null`

**Solutions**:
1. Check main.dart line 23: `ChatWebSocketService().setChatStore(chatStore)`
2. Verify ChatStore is created BEFORE WebSocketService.setChatStore() is called
3. Check if setChatStore() was called and didn't throw

**Test**:
```bash
# Run app and check main.dart logs for:
[MAIN] ✅ ChatStore created
[MAIN] ✅ ChatStore injected into WebSocketService
```

### Issue 3: Message Shows ⏱ But Never Changes to ✓
**Root Cause**: Server not sending MESSAGE_RECEIVED back
**Symptoms**:
- Message appears with ⏱ immediately
- Message never updates to ✓
- No `[ChatWebSocketService] MESSAGE_RECEIVED:` log appears

**Solutions**:
1. Check backend server is running and accepting messages on `/app/chat.send`
2. Check backend logs show message was received and processed
3. Check backend is sending MESSAGE_RECEIVED back correctly
4. Verify WebSocket subscription to `/user/queue/messages` is active

**Test**:
```bash
# Check backend logs while sending message
# Should see: "Message received from userId=123 to userId=456"
# And: "Sending MESSAGE_RECEIVED back"

# Check in Flutter logs for:
[ChatWebSocketService] Subscribed to /user/queue/messages
```

### Issue 4: Message Doesn't Appear in UI
**Root Cause**: ChatStore.addIncomingMessage() not being called OR not notifying listeners
**Symptoms**:
- Log shows optimistic message added: `[CHATSTORE] insert incoming...`
- But message doesn't appear in ListView
- Consumer<ChatStore> not rebuilding

**Solutions**:
1. Check that Consumer<ChatStore> is present in chat_screen.dart (line 490)
2. Check that chatStore.notifyListeners() is called (line 163 in chat_store.dart)
3. Check that messagesForUser() returns the correct list
4. Verify ChatStore is being provided via Provider.ChangeNotifierProvider

**Test**:
```bash
# Add in chat_screen.dart build method:
print('[Chat] Consumer building, message count = ${msgs.length}');

# In chat_store.dart after notifyListeners():
print('[CHATSTORE] notifyListeners called, listeners count = ${listeners.length}');
```

### Issue 5: Message Doesn't Reach Receiver
**Root Cause**: 
- Server not sending to recipient's queue, OR
- Recipient not subscribed to `/user/queue/messages`, OR
- Message data format incorrect

**Solutions**:
1. Check backend is correctly implementing message delivery to recipient
2. Check recipient's WebSocket subscribed to `/user/queue/messages`
3. Check message JSON contains correct `recipientId`
4. Check both devices connected to same backend

**Test**:
```bash
# On receiver device, check logs for:
[ChatWebSocketService] Subscribed to /user/queue/messages
[ChatWebSocketService] MESSAGE_RECEIVED: ...

# Send message from sender device and watch receiver logs
```

### Issue 6: Message Persists Locally But Not on Backend
**Root Cause**: Message only in optimistic state, server never confirmed
**Symptoms**:
- Message shows ⏱ with ✓ on sender side
- Message disappears when app restarts
- No database entry for message

**Solutions**:
1. Check if message was actually sent to backend (/app/chat.send)
2. Check backend received and stored it
3. Check database schema has correct columns
4. Check backend error logs

## Debugging Commands

### Get All Relevant Logs
```bash
flutter logs | grep -E "\[Chat\]|\[ChatWebSocketService\]|\[CHATSTORE\]|\[MAIN\]"
```

### Monitor Message Flow Real-Time
```bash
flutter logs | grep -E "MESSAGE_RECEIVED|Reconciled|insert incoming"
```

### Watch Connection Status
```bash
flutter logs | grep -E "CONNECTED|DISCONNECTED|connection"
```

### Check ChatStore State
```bash
flutter logs | grep -E "\[CHATSTORE\] after insert"
```

## Quick Fix Checklist

- [ ] App logs show `[MAIN] ✅ WebSocket CONNECTED` at startup
- [ ] When sending message: `[Chat] WebSocket connected: true`
- [ ] Optimistic message logged: `[CHATSTORE] insert incoming`
- [ ] Server acknowledgment logged: `[ChatWebSocketService] MESSAGE_RECEIVED`
- [ ] Status update logged: `[CHATSTORE] reconcile message`
- [ ] Message persists after navigation
- [ ] Receiver sees message in their UI

## Advanced Debugging

### If WebSocket Connection Fails
1. Check backend URL in ApiConfig (should be `http://98.92.24.110:8082/ws`)
2. Check token is valid (not expired)
3. Check backend server is running
4. Try connecting manually in terminal:
   ```bash
   curl -i http://98.92.24.110:8082/ws
   ```

### If Message Never Reaches Server
1. Check WebSocket is actually connected before sending
2. Check message destination: should be `/app/chat.send`
3. Check message body format (should be JSON with clientMessageId, recipientId, content)
4. Check backend logs for errors
5. Try sending from web client to test backend

### If Server Doesn't Send Back MESSAGE_RECEIVED
1. Check backend MessageController implementation
2. Check backend sends to correct destination: `/user/{senderId}/queue/messages`
3. Check backend includes clientMessageId in response
4. Check backend database insertion was successful

## Next Steps

1. **Run the app with the Flutter logs command above**
2. **Send a message and capture the output**
3. **Share the log output in the format:**
   ```
   [Chat] 📤 Sending message...
   [Chat] WebSocket connected: true/false
   [ChatWebSocketService] ❌/✅ ...
   [CHATSTORE] ...
   ```
4. **Based on which logs appear/don't appear, we can identify the exact failure point**
5. **Apply the specific fix for that component**

