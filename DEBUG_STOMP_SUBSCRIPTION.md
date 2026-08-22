# IMMEDIATE ACTION PLAN - FIX STOMP SUBSCRIPTION BUG

## Current Status: 🔴 CRITICAL
**Messages sent successfully to backend but NEVER reach Flutter clients**

---

## ROOT CAUSE HYPOTHESIS

The STOMP subscription callback `_onMessageReceived` is not firing despite:
- ✅ WebSocket connection active
- ✅ Subscription to `/user/queue/messages` successful  
- ✅ Backend routing message to `/user/{userId}/queue/messages`
- ❌ Frontend callback NOT invoked

**Most Likely Cause**: Authentication context lost between WebSocket connection and subscription message routing.

---

## DEBUG STEPS (In Order)

### STEP 1: Verify WebSocket Session Persistence
**Backend**: `WebSocketSecurityInterceptor.java`

Add logging:
```java
@Override
public void handleTransportError(WebSocketSession session, Throwable exception) throws Exception {
    String sessionId = session.getId();
    Map<String, Object> attributes = session.getAttributes();
    Long userId = (Long) attributes.get("userId");
    System.out.println("[WEBSOCKET DEBUG] Session: " + sessionId + ", UserId: " + userId);
    // ... rest of method
}
```

**Check If**:
- userId persists after connection
- Same userId used for routing messages

---

### STEP 2: Verify STOMP Message Routing
**Backend**: `MessageService.java` lines 57-71

Enhance logging:
```java
// BEFORE sending to user
System.out.println("[DEBUG] About to send to user: " + senderId.toString());
System.out.println("[DEBUG] Destination: /queue/messages");
System.out.println("[DEBUG] Message ID: " + response.getId());
System.out.println("[DEBUG] Timestamp: " + System.currentTimeMillis());

messagingTemplate.convertAndSendToUser(
    senderId.toString(),
    "/queue/messages",
    response
);

System.out.println("[DEBUG] convertAndSendToUser completed for user: " + senderId);
```

**Check If**:
- Logs show send attempt
- No exceptions thrown
- Message actually dispatched

---

### STEP 3: Verify Frontend Subscription Lifecycle
**Frontend**: Add comprehensive logging

Replace in `chat_websocket_service.dart`:

```dart
void _onConnect(StompFrame frame) {
  print('\n\n═══════════════════════════════════════════════');
  print('[ChatWebSocketService] 🟢 WEBSOCKET CONNECTED');
  print('═══════════════════════════════════════════════');
  print('[ChatWebSocketService] Session: ${frame.toString()}');
  _isConnected = true;
  _isConnecting = false;
  
  _connectCompleter?.complete();
  _notifyConnectionListeners(true);
  
  print('[ChatWebSocketService] About to subscribe to queues...');
  print('[ChatWebSocketService] Current user: $_currentUserId');
  
  _subscribeToMessageQueue();
  _subscribeToTypingIndicators();
  _subscribeToNotifications();
  
  print('[ChatWebSocketService] ✅ All subscriptions registered');
  print('═══════════════════════════════════════════════\n');
  
  _sendQueuedMessages();
}
```

---

### STEP 4: Add STOMP Subscribe Callback Debug
**Frontend**: Enhance subscription

```dart
void _subscribeToMessageQueue() {
  final topic = '/user/queue/messages';
  if (_activeSubscriptions.contains(topic)) {
    print('[ChatWebSocketService] Already subscribed to $topic');
    return;
  }

  print('\n[ChatWebSocketService] 🔔 SUBSCRIBING TO: $topic');
  
  try {
    _stompClient.subscribe(
      destination: topic,
      callback: (frame) {
        print('\n╔════════════════════════════════════════════════╗');
        print('║  🎉 🎉 🎉 CALLBACK FIRED 🎉 🎉 🎉            ║');
        print('╚════════════════════════════════════════════════╝');
        print('[ChatWebSocketService] Frame received');
        print('[ChatWebSocketService] Frame command: ${frame.command}');
        print('[ChatWebSocketService] Frame headers: ${frame.headers}');
        print('[ChatWebSocketService] Frame body: ${frame.body}');
        print('[ChatWebSocketService] Body length: ${frame.body?.length ?? 0}');
        
        try {
          _onMessageReceived(frame);
        } catch (e) {
          print('[ChatWebSocketService] ❌ Error in callback: $e');
          print('[ChatWebSocketService] Stack trace: ${e.toString()}');
        }
      },
      headers: {
        'id': 'sub-messages',
        'ack': 'auto',
        // Try explicit user subscription
        'selector': '',
      },
    );
    
    _activeSubscriptions.add(topic);
    print('[ChatWebSocketService] ✅ Subscribe call completed');
    print('[ChatWebSocketService] Active subscriptions: $_activeSubscriptions\n');
  } catch (e) {
    print('[ChatWebSocketService] ❌ SUBSCRIBE ERROR: $e');
    print('[ChatWebSocketService] Stack: ${e.toString()}');
  }
}
```

---

### STEP 5: Verify Message Is Actually Sent
**Backend**: Add logging after saveAll

```java
Message savedMessage = messageRepository.save(message);
System.out.println("[VERIFY] Message saved with ID: " + savedMessage.getId());
System.out.println("[VERIFY] Saved content: " + savedMessage.getContent());

MessageResponse response = mapToResponse(savedMessage);
System.out.println("[VERIFY] Response created: " + response);

// Print full response JSON
try {
    com.fasterxml.jackson.databind.ObjectMapper mapper = 
        new com.fasterxml.jackson.databind.ObjectMapper();
    String json = mapper.writeValueAsString(response);
    System.out.println("[VERIFY] Response JSON:\n" + json);
} catch (Exception e) {
    System.out.println("[VERIFY] Could not serialize: " + e.getMessage());
}
```

---

### STEP 6: Check STOMP Broker Logs
**Backend**: Enable Spring STOMP debugging

Add to `application.yml`:
```yaml
logging:
  level:
    org.springframework.messaging: DEBUG
    org.springframework.web.socket: DEBUG
```

Look for:
```
Processing MESSAGE destination=/user/{userId}/queue/messages
```

---

### STEP 7: Test Direct Message Publishing
**Backend**: Create test endpoint

```java
@PostMapping("/test/send-message")
public ResponseEntity<String> testSendMessage(@RequestAttribute("userId") Long userId) {
    try {
        Map<String, Object> testMessage = new HashMap<>();
        testMessage.put("id", 999L);
        testMessage.put("senderId", 5L);
        testMessage.put("receiverId", userId);
        testMessage.put("content", "TEST MESSAGE FROM ENDPOINT");
        testMessage.put("clientMessageId", "test-123");
        testMessage.put("createdAt", LocalDateTime.now());
        testMessage.put("isRead", false);
        
        System.out.println("[TEST] Sending test message to user: " + userId);
        messagingTemplate.convertAndSendToUser(
            userId.toString(),
            "/queue/messages",
            testMessage
        );
        System.out.println("[TEST] Test message sent");
        
        return ResponseEntity.ok("Test message sent to user " + userId);
    } catch (Exception e) {
        System.out.println("[TEST] Error: " + e.getMessage());
        e.printStackTrace();
        return ResponseEntity.status(500).body("Error: " + e.getMessage());
    }
}
```

**Test**: Call this endpoint and check if Flutter receives message.

---

### STEP 8: Monitor Network Traffic
**Frontend**: Add network packet inspection

Use Charles Proxy or Burp Suite to sniff WebSocket frames:
- Look for STOMP SEND frames from backend
- Verify they contain your message
- Check headers and body

---

## EXPECTED OUTPUTS AFTER EACH STEP

### After Step 1:
```
[WEBSOCKET DEBUG] Session: xyz123, UserId: 5
[WEBSOCKET DEBUG] Session: xyz123, UserId: 5  ← Should match
```

### After Step 2:
```
[DEBUG] About to send to user: 5
[DEBUG] Destination: /queue/messages
[DEBUG] convertAndSendToUser completed for user: 5
```

### After Step 3:
```
[ChatWebSocketService] 🟢 WEBSOCKET CONNECTED
[ChatWebSocketService] About to subscribe to queues...
[ChatWebSocketService] Current user: 5
[ChatWebSocketService] ✅ All subscriptions registered
```

### After Step 4:
```
╔════════════════════════════════════════════════╗
║  🎉 🎉 🎉 CALLBACK FIRED 🎉 🎉 🎉            ║
╚════════════════════════════════════════════════╝
[ChatWebSocketService] Frame received
[ChatWebSocketService] Frame command: MESSAGE
[ChatWebSocketService] Frame body: {"id":56,"senderId":5,...}
```

**If Step 4 shows callback IS firing**: Problem is in message parsing/handling  
**If Step 4 shows NO callback**: Problem is in STOMP routing (Steps 1-2)

---

## QUICK TEST SCRIPT

Run this in Flutter after hot reload:

```dart
// In chat_detail_screen.dart or anywhere
import 'package:social_chat_app/src/services/chat_websocket_service.dart';

void testWebSocket() {
  final ws = ChatWebSocketService();
  
  print('[TEST] WebSocket connected: ${ws.isConnected}');
  print('[TEST] Current user ID: ${ws._currentUserId}');  // May need to make public
  print('[TEST] Active subscriptions: ${ws._activeSubscriptions}');
  
  // Send test message
  try {
    ws.sendChatMessage(6, 'TEST MESSAGE');
    print('[TEST] Test message sent');
  } catch (e) {
    print('[TEST] Error: $e');
  }
}
```

---

## FALLBACK SOLUTIONS (If STOMP Can't Be Fixed)

### Option 1: Polling
Replace WebSocket with HTTP polling:
```dart
Timer.periodic(Duration(seconds: 2), (_) {
  ApiService.getUnreadMessages().then((messages) {
    // Process messages
  });
});
```
❌ Inefficient, high battery drain

### Option 2: Native WebSocket
Replace `stomp_dart_client` with `web_socket_channel`:
```dart
final channel = IOWebSocketChannel.connect('ws://...');
channel.stream.listen((message) {
  // Parse STOMP manually
});
```
⚠️ More control, more code

### Option 3: Firebase Cloud Messaging (FCM)
Use FCM for push notifications:
```
User sends message → Backend saves → Backend sends FCM notification → Device receives notification → App fetches message
```
✅ More reliable, works offline better
❌ Introduces Firebase dependency

---

## NEXT IMMEDIATE STEPS

1. **Run Steps 1-4** on your local machine
2. **Share logs** showing what happens
3. **Check if callback fires** (Step 4)
4. **If not**: Share backend logs when message is sent
5. **If yes**: Debug message parsing error

Once we see the logs, the issue will be obvious.

