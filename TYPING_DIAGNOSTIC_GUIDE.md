# Typing Indicator Diagnostic Guide

## Problem Summary
**Symptom:** Typing indicators not showing in chat UI  
**Root Cause:** Backend sends typing frames correctly, but frontend callbacks are not firing

## Backend Status ✅ CONFIRMED WORKING
From logs, backend is:
1. Receiving typing events on `/app/chat.typing`
2. Sending to `/user/{userId}/queue/typing` via `convertAndSendToUser()`
3. Frames confirmed in backend logs:
   ```
   Processing MESSAGE destination=/user/2/queue/typing session=null payload={"fromUserId":3,"type":"typing","toUserId":2,"isTyping":true,...}
   Processing MESSAGE destination=/queue/typing-usert25warag session=null payload={"fromUserId":3,"type":"typing","toUserId":2,"isTyping":true,...}
   ```

## Frontend Status 🔍 BEING DIAGNOSED

### What Changed
Enhanced logging added to pinpoint exactly where frames are lost:

#### 1. Subscription Registration (Lines 447-488)
```dart
void _subscribeToTypingIndicators() {
  final topic = '/user/queue/typing';
  
  print('[ChatWebSocketService] 📝 SUBSCRIBING to typing indicators at $topic...');
  print('[ChatWebSocketService]    ├─ Current User ID: $_currentUserId');
  print('[ChatWebSocketService]    ├─ STOMP Connected: $_isConnected');
  print('[ChatWebSocketService]    ├─ STOMP Client connected: ${_stompClient.isConnected}');
  print('[ChatWebSocketService]    └─ Subscription will receive messages from backend convertAndSendToUser()');
  
  void typingCallback(StompFrame frame) {
    print('[ChatWebSocketService] 🚨🚨🚨 TYPING CALLBACK FIRED 🚨🚨🚨');
    print('[ChatWebSocketService]    ├─ Frame destination: ${frame.headers?['destination']}');
    print('[ChatWebSocketService]    ├─ Frame subscription: ${frame.headers?['subscription']}');
    print('[ChatWebSocketService]    └─ Frame message-id: ${frame.headers?['message-id']}');
    _onTypingIndicator(frame);
  }
  
  final unsubscribeFn = _stompClient.subscribe(
    destination: topic,
    callback: typingCallback,
    headers: {'id': 'sub-typing-${_currentUserId}', 'ack': 'auto'},
  );
  
  print('[ChatWebSocketService] ✅ Subscribed to $topic');
  print('[ChatWebSocketService]    ├─ STOMP subscribe() returned: ${unsubscribeFn != null ? 'Function' : 'null'}');
}
```

**Key diagnostics:**
- Confirms STOMP client is connected BEFORE subscription
- Captures subscription return value (function = successful)
- Logs when callback is fired (🚨 marker)

#### 2. Frame Handler (Lines 739-773)
```dart
void _onTypingIndicator(StompFrame frame) {
  print('[ChatWebSocketService] 🔔 TYPING FRAME RECEIVED - processing...');
  print('[ChatWebSocketService]    ├─ Frame command: ${frame.command}');
  print('[ChatWebSocketService]    ├─ Frame headers: ${frame.headers}');
  print('[ChatWebSocketService]    ├─ Frame body length: ${frame.body?.length}');
  
  final data = jsonDecode(frame.body!);
  print('[ChatWebSocketService]    ├─ Extracted userId: $userId');
  print('[ChatWebSocketService]    ├─ Extracted isTyping: $isTyping');
  print('[ChatWebSocketService]    └─ ChatStore available: ${_chatStore != null}');
  
  _chatStore?.setTyping(userId, isTyping);
  print('[ChatWebSocketService] ⌨️✅ Typing indicator PROCESSED: user=$userId isTyping=$isTyping');
}
```

**Key diagnostics:**
- Frame structure validation
- Data extraction confirmation
- ChatStore availability check
- Final processing confirmation

#### 3. Unhandled Message Fallback (Lines 154-174)
```dart
onUnhandledMessage: (StompFrame frame) {
  final destination = frame.headers['destination'] ?? '';
  final subscription = frame.headers['subscription'] ?? '';
  
  print('[ChatWebSocketService] ⚠️⚠️⚠️ UNHANDLED MESSAGE ⚠️⚠️⚠️');
  print('[ChatWebSocketService] ⚠️ Destination: $destination');
  print('[ChatWebSocketService] ⚠️ Subscription: $subscription');
  
  // CRITICAL: Check for typing messages
  if (destination.contains('typing') || subscription.contains('typing')) {
    print('[ChatWebSocketService] 🚨 UNHANDLED TYPING MESSAGE DETECTED! Processing manually...');
    _onTypingIndicator(frame);
    return;
  }
}
```

**Key diagnostics:**
- Catches typing frames that bypass subscription callbacks
- Manually routes them to handler
- This is a safety net - if frames arrive here, the subscription callback wasn't triggered

#### 4. Debug Frame Filter (Lines 145-150)
Enhanced to include typing messages:
```dart
onDebugMessage: (String message) {
  if (message.contains('MESSAGE') && 
      (message.contains('/queue/messages') || 
       message.contains('typing') || 
       message.contains('/queue/typing'))) {
    print('[ChatWebSocketService] 🔍 RAW STOMP FRAME: $message');
  }
}
```

## Testing Steps

### Step 1: Run Flutter App
```bash
cd social-media-mobile
flutter run
```

### Step 2: Open Chat in Two Windows
- **Window A (User 3 - Vamsi):** Chat with User 2
- **Window B (User 2 - Sai):** Chat with User 3

### Step 3: Trigger Typing Event
In **Window A**, start typing a message. Watch **Window B** logs.

### Step 4: Analyze Logs

#### SCENARIO A: Working (Expected) 🟢
```
[ChatWebSocketService] 📝 SUBSCRIBING to typing indicators at /user/queue/typing...
[ChatWebSocketService]    ├─ STOMP Client connected: true
[ChatWebSocketService] ✅ Subscribed to /user/queue/typing
[ChatWebSocketService]    ├─ STOMP subscribe() returned: Function
```

Then when other user types:
```
[ChatWebSocketService] 🚨🚨🚨 TYPING CALLBACK FIRED 🚨🚨🚨
[ChatWebSocketService]    ├─ Frame destination: /user/2/queue/typing
[ChatWebSocketService]    ├─ Frame subscription: sub-typing-2
[ChatWebSocketService] 🔔 TYPING FRAME RECEIVED - processing...
[ChatWebSocketService]    ├─ Extracted userId: 3
[ChatWebSocketService]    ├─ Extracted isTyping: true
[ChatWebSocketService] ⌨️✅ Typing indicator PROCESSED: user=3 isTyping=true
```

UI should show: "typing..." in the conversation

#### SCENARIO B: Callback Never Fires 🔴
```
[ChatWebSocketService] ✅ Subscribed to /user/queue/typing
[ChatWebSocketService]    ├─ STOMP subscribe() returned: Function
```

But when other user types, NO output like:
```
[ChatWebSocketService] 🚨🚨🚨 TYPING CALLBACK FIRED 🚨🚨🚨
```

**Possible Solutions:**
- Check if `onUnhandledMessage` is catching it (look for 🚨 UNHANDLED TYPING MESSAGE)
- If yes: Subscription is not working, STOMP library issue
- If no: Frame never reaches client at all, network issue

#### SCENARIO C: Fallback Handler Catches It 🟡
```
[ChatWebSocketService] ⚠️⚠️⚠️ UNHANDLED MESSAGE ⚠️⚠️⚠️
[ChatWebSocketService] ⚠️ Destination: /user/2/queue/typing
[ChatWebSocketService] 🚨 UNHANDLED TYPING MESSAGE DETECTED! Processing manually...
[ChatWebSocketService] ⌨️✅ Typing indicator PROCESSED: user=3 isTyping=true
```

UI should show: "typing..." (fallback is working!)

This means the subscription callback setup has an issue, but the frame IS arriving.

## Key Questions to Answer from Logs

1. **Is subscription callback being set up?**
   - Look for: `🚨🚨🚨 TYPING CALLBACK FIRED` or `⚠️ UNHANDLED TYPING MESSAGE`

2. **Is STOMP client connected before subscription?**
   - Look for: `STOMP Client connected: true`

3. **What destination is the frame using?**
   - Look for: `Frame destination: /user/{userId}/queue/typing`

4. **Is ChatStore initialized?**
   - Look for: `ChatStore available: true`

5. **Is typing being set in state?**
   - Look for: `Typing indicator PROCESSED: user=X isTyping=true`

## Next Steps

1. **Run app with new enhanced logging**
2. **Trigger typing event and capture full logs**
3. **Share logs focusing on typing indicators**
4. **Identify which scenario matches your setup**
5. **Apply targeted fix based on findings**

## Files Modified
- `lib/src/services/chat_websocket_service.dart`
  - Enhanced typing subscription logging
  - Enhanced frame handler diagnostics
  - Added typing fallback in unhandled message handler
  - Updated debug frame filter

## Expected Behavior After Fix
- Type in chat → recipient sees "typing..." immediately ✅
- Stop typing → "typing..." disappears after 3 seconds ✅
- Works bidirectionally between users ✅
