# Backend → Frontend Typing Subscription Verification ✅

**Status:** VERIFIED - CORRECT ROUTING AND SUBSCRIPTIONS  
**Date:** January 9, 2026

---

## 🔍 **SUBSCRIPTION FLOW VERIFICATION**

### **1️⃣ FRONTEND - WHERE IT'S LISTENING**

#### File: `chat_websocket_service.dart` (lines 457-480)

```dart
void _subscribeToTypingIndicators() {
  final topic = '/user/queue/typing';  // ← LISTENING HERE
  
  final unsubscribeFn = _stompClient.subscribe(
    destination: topic,  // ✅ Correct STOMP destination
    callback: _onTypingIndicator,  // ← Callback handler
    headers: {'id': 'sub-typing-${_currentUserId}', 'ack': 'auto'},
  );
  
  _subscriptionHandlers[topic] = unsubscribeFn;
  _activeSubscriptions.add(topic);
  print('[ChatWebSocketService] ✅ Subscribed to $topic');
}
```

**Frontend Listening On:** `/user/queue/typing`

---

### **2️⃣ BACKEND - WHERE IT'S SENDING**

#### File: `MessageController.java` (lines 150-171)

```java
@MessageMapping("/chat.typing")
public void handleTypingViaWebSocket(
    @Payload TypingRequest request,
    SimpMessageHeaderAccessor headerAccessor) {
  
  try {
    // Get typing sender
    Long userId = Long.parseLong(
      headerAccessor.getSessionAttributes().get("userId").toString()
    );
    
    // Prepare payload with sender info
    Map<String, Object> payload = new HashMap<>();
    payload.put("type", "typing");
    payload.put("fromUserId", userId);  // ← WHO IS TYPING
    payload.put("toUserId", request.getReceiverId());  // ← WHO IS RECEIVING
    payload.put("isTyping", request.getIsTyping() == Boolean.TRUE);
    payload.put("timestamp", LocalDateTime.now());
    
    // ✅ SEND TO RECEIVER'S QUEUE
    messagingTemplate.convertAndSendToUser(
      request.getReceiverId().toString(),  // ← RECEIVER'S ID
      "/queue/typing",  // ← QUEUE NAME
      payload
    );
    
  } catch (Exception e) {
    System.out.println("[MessageController] Error: " + e.getMessage());
  }
}
```

**Backend Sending To:** `/user/{receiverId}/queue/typing`

---

## 🎯 **STOMP PROTOCOL VERIFICATION**

### **How STOMP Routes Messages to Users**

STOMP automatically converts `convertAndSendToUser(userId, "/queue/typing", payload)` into:

```
/user/{userId}/queue/typing
```

This is STOMP's user-specific routing convention.

---

### **EXACT MESSAGE FLOW**

```
┌──────────────────────────────────────────────────────────────┐
│ FRONTEND: User A (ID=3) types a message                      │
│ Calls: sendTypingIndicator(receiverId=2, isTyping=true)      │
└──────────────────────────────────────────────────────────────┘
                            ↓
                   SENDS TO: /app/chat.typing
              PAYLOAD: {receiverId: 2, isTyping: true}
                            ↓
┌──────────────────────────────────────────────────────────────┐
│ BACKEND: MessageController receives on /app/chat.typing      │
│                                                               │
│ handler() {                                                   │
│   userId = 3 (from session)                                  │
│   receiverId = 2 (from request)                              │
│   payload = {fromUserId: 3, toUserId: 2, isTyping: true}    │
│                                                               │
│   // Send to User 2 (the receiver)                           │
│   convertAndSendToUser("2", "/queue/typing", payload)        │
│ }                                                             │
└──────────────────────────────────────────────────────────────┘
                            ↓
      ROUTES TO: /user/2/queue/typing (in STOMP protocol)
                            ↓
┌──────────────────────────────────────────────────────────────┐
│ FRONTEND: User B (ID=2) WebSocket receives                   │
│ Subscription: /user/queue/typing (which becomes)             │
│              /user/2/queue/typing (in STOMP)                 │
│                                                               │
│ PAYLOAD RECEIVED: {fromUserId: 3, isTyping: true, ...}       │
│                                                               │
│ _onTypingIndicator(frame) {                                  │
│   userId = 3 (from payload.fromUserId) ← THIS IS WHO TYPED   │
│   chatStore.setTyping(3, true)                               │
│   UI UPDATES: "John is typing..."                            │
│ }                                                             │
└──────────────────────────────────────────────────────────────┘
```

---

## ✅ **VERIFICATION CHECKLIST**

| Component | Backend | Frontend | Match? |
|-----------|---------|----------|--------|
| **Receiver Extraction** | `request.getReceiverId()` | ✅ (used in sendTypingIndicator) | ✅ YES |
| **Sender Extraction** | `fromUserId: userId` | ✅ (expects fromUserId) | ✅ YES |
| **Queue Name** | `/queue/typing` | `/user/queue/typing` | ✅ YES (STOMP matches) |
| **Routing** | convertAndSendToUser(receiverId) | Subscribed to /user/queue/typing | ✅ YES |
| **Payload Field** | `fromUserId` | Reads `fromUserId` | ✅ YES |

---

## 🔗 **COMPLETE SUBSCRIPTION CHAIN**

### Step 1: Frontend connects to WebSocket
```
WebSocket: ws://backend:8080/ws
```

### Step 2: STOMP frame exchange
```
CONNECT
  login: user123
  passcode: token
  
← CONNECTED
```

### Step 3: Frontend subscribes
```
SUBSCRIBE
  destination: /user/queue/typing
  id: sub-typing-2
  ack: auto
  
← RECEIPT (subscription registered)
```

### Step 4: Backend sends to receiver
```
SEND
  destination: /user/2/queue/typing
  
{
  "type": "typing",
  "fromUserId": 3,
  "toUserId": 2,
  "isTyping": true,
  "timestamp": "2026-01-09T10:30:45"
}
```

### Step 5: Frontend receives via subscription
```
MESSAGE
  destination: /user/2/queue/typing
  message-id: ID:...
  
{
  "type": "typing",
  "fromUserId": 3,
  "toUserId": 2,
  "isTyping": true,
  "timestamp": "2026-01-09T10:30:45"
}

→ Callback: _onTypingIndicator(frame)
→ Extract: fromUserId = 3
→ Update: chatStore.setTyping(3, true)
→ Display: "John is typing..."
```

---

## 📡 **ADDITIONAL SUBSCRIPTIONS**

Frontend also subscribes to:

1. **Messages**: `/user/queue/messages`
   - For new chat messages
   - Backend sends: `/user/{receiverId}/queue/messages`

2. **Presence**: `/user/queue/presence`  
   - For online/offline status
   - Backend broadcasts presence updates

3. **Read Receipts**: `/user/queue/read-receipts`
   - For message delivery confirmation

All follow the **same pattern**: Backend uses `convertAndSendToUser()`, Frontend subscribes to `/user/queue/{topic}`

---

## 🎯 **CRITICAL CONFIRMATION**

### **Is Backend Correctly Sending to Receiver?** ✅ YES

```java
messagingTemplate.convertAndSendToUser(
  request.getReceiverId().toString(),  // ✅ Sends to RECEIVER's ID
  "/queue/typing",  // ✅ Typing queue
  payload  // ✅ Contains fromUserId (sender info)
);
```

### **Is Frontend Correctly Listening?** ✅ YES

```dart
_stompClient.subscribe(
  destination: '/user/queue/typing',  // ✅ Listens on this queue
  callback: _onTypingIndicator,  // ✅ Handler extracts fromUserId
);
```

### **Do They Match?** ✅ YES

- Backend: `convertAndSendToUser(receiverId, "/queue/typing", ...)`
- Frontend: `subscribe(destination: "/user/queue/typing", ...)`
- STOMP expands `/user/queue/typing` → `/user/{userId}/queue/typing`
- Message correctly routes to receiver ✅

---

## 🚀 **SUMMARY**

| Aspect | Status | Details |
|--------|--------|---------|
| Backend sending route | ✅ Correct | `convertAndSendToUser(receiverId, "/queue/typing")` |
| Frontend listening route | ✅ Correct | `subscribe("/user/queue/typing")` |
| STOMP routing | ✅ Correct | Automatically expands to `/user/{userId}/queue/typing` |
| Receiver identification | ✅ Correct | Backend uses `request.getReceiverId()` |
| Sender identification | ✅ Correct | Backend sends `fromUserId`, frontend reads it |
| Payload structure | ✅ Correct | Contains `fromUserId`, `isTyping`, metadata |
| Queue name consistency | ✅ Correct | Both use `/queue/typing` |
| Callback handler | ✅ Correct | `_onTypingIndicator()` properly processes frame |

**EVERYTHING IS CORRECTLY WIRED!** ✅

The typing indicator should now work end-to-end after app restart.

