# Typing Indicator Workflow - Full Debug Trace

## Complete Flow with Logging

### 1️⃣ User Types in ChatDetailScreen

```
📱 USER TYPING:
├─ ChatDetailScreen TextField onChange → _onUserTyping(text)
│
├─ [Chat] Checking if typing: text.isNotEmpty && !_isTypingSent
│  └─ First character: send TYPING_START
│     └─ _webSocketService.sendTypingStart(chatId)
│        └─ Sends: {"action":"TYPING_START", "recipientId":2}
│
└─ Then: 1.5s debounce timer set
   └─ On timeout: sendTypingStop(chatId)
      └─ Sends: {"action":"TYPING_STOP", "recipientId":2}
```

**Expected Logs:**
```
[Chat] _onUserTyping CALLED - text=...
[Chat] ⌨️ Sending TYPING_START to recipient
[WebSocket] Sending MESSAGE to /app/chat.typing
```

---

### 2️⃣ WebSocket Sends to Backend

```
🌐 BACKEND RECEIVES:
├─ POST /app/chat.typing
│  └─ MessageController.handleTypingViaWebSocket()
│
└─ Broadcasts to recipient:
   └─ /user/{recipientId}/queue/typing
      └─ Message: {"fromUserId":2, "isTyping":true}
```

**Expected Backend Logs:**
```
Searching methods to handle SEND /app/chat.typing
Invoking MessageController#handleTypingViaWebSocket
```

---

### 3️⃣ Recipient's Flutter Receives Typing Notification

```
📱 RECIPIENT RECEIVES:
├─ WebSocket frame on /user/queue/typing
│
├─ [ChatWebSocketService] 📨 TYPING FRAME RECEIVED
│  ├─ Frame headers: {...}
│  ├─ Frame body: {"fromUserId":2, "isTyping":true}
│
├─ [ChatWebSocketService] 🔔 TYPING FRAME RECEIVED - processing...
│  ├─ Parsed data: {fromUserId: 2, isTyping: true}
│  └─ Calling: _chatStore?.setTyping(userId=2, isTyping=true)
│
└─ [ChatWebSocketService] ⌨️✅ Typing indicator PROCESSED: user=2 isTyping=true
```

**Expected Logs:**
```
[ChatWebSocketService] 🔔 TYPING FRAME RECEIVED - processing...
[ChatWebSocketService]    ├─ Headers: {destination: /user/2/queue/typing, ...}
[ChatWebSocketService]    └─ Body: {"fromUserId":2,"isTyping":true}
```

---

### 4️⃣ ChatStore Updates State

```
🔄 CHATSTORE STATE UPDATE:
├─ [CHATSTORE] 🔤 setTyping CALLED: user=2 isTyping=true
│  ├─ Before: _typingStatus={}
│  ├─ ✅ Typing status SET to TRUE for user=2
│  ├─ After: _typingStatus={2: true}
│  └─ 📢 notifyListeners() called
│
└─ [CHATSTORE] 🔤 isUserTyping(2) = TRUE ← typing in progress
```

**Expected Logs:**
```
[CHATSTORE] 🔤 setTyping CALLED: user=2 isTyping=true
[CHATSTORE]    ├─ Before: _typingStatus={}
[CHATSTORE]    ├─ ✅ Typing status SET to TRUE for user=2
[CHATSTORE]    ├─ After: _typingStatus={2: true}
[CHATSTORE]    └─ 📢 notifyListeners() called
```

---

### 5️⃣ UI Rebuilds and Shows "typing..."

```
🎨 UI UPDATES:
├─ ChatDetailScreen UI rebuilds (Consumer<ChatStore> triggered)
│  │
│  ├─ [ChatScreen-DETAIL] 🔤 Typing indicator REBUILD: chatId=2 isTyping=true
│  ├─ [CHATSTORE] 🔤 isUserTyping(2) = TRUE ← typing in progress
│  │
│  └─ ✅ DISPLAYING typing indicator: "Sai is typing…"
│     └─ Text("Sai is typing…", style: italic grey)
│
└─ ChatListScreen also shows "typing..." in conversation item
   ├─ [ChatScreen] 📊 ConvItem REBUILD: user=2 isTyping=true isOnline=true
   ├─ [ChatScreen]    ✅ TYPING DETECTED - displaying "typing..."
   └─ Text("typing...", style: green italic)
```

**Expected Logs:**
```
[ChatScreen-DETAIL] 🔤 Typing indicator REBUILD: chatId=2 isTyping=true
[ChatScreen-DETAIL]    ✅ DISPLAYING typing indicator: "Sai is typing…"
[ChatScreen] 📊 ConvItem REBUILD: user=2 isTyping=true isOnline=true
[ChatScreen]    ✅ TYPING DETECTED - displaying "typing..."
```

---

### 6️⃣ Auto-Clear After 3 Seconds of No Typing

```
⏱️ TIMEOUT:
├─ 3 seconds pass without new typing event
│
├─ [CHATSTORE] ⏱️ Typing indicator auto-cleared for user=2 (3s timeout)
│  ├─ After clear: _typingStatus={}
│  └─ 📢 notifyListeners() called
│
└─ UI rebuilds and "typing..." disappears
   ├─ [ChatScreen-DETAIL] 🔤 Typing indicator REBUILD: chatId=2 isTyping=false
   └─ [ChatScreen-DETAIL]    └─ Not typing, returning SizedBox.shrink()
```

**Expected Logs:**
```
[CHATSTORE] ⏱️ Typing indicator auto-cleared for user=2 (3s timeout)
[CHATSTORE]    └─ After clear: _typingStatus={}
[ChatScreen-DETAIL] 🔤 Typing indicator REBUILD: chatId=2 isTyping=false
```

---

## Complete Workflow Log Example

```
=== TYPING INDICATOR WORKFLOW ===

1️⃣ USER (ID=3) STARTS TYPING:
[Chat] _onUserTyping CALLED - text=h
[Chat] ⌨️ Sending TYPING_START to recipient
[WebSocket] Sending MESSAGE to /app/chat.typing: {"action":"TYPING_START","recipientId":2}

2️⃣ BACKEND PROCESSES:
[social-service] Invoking MessageController#handleTypingViaWebSocket
[social-service] Broadcasting typing indicator to user 2

3️⃣ RECIPIENT (ID=2) RECEIVES:
[ChatWebSocketService] 🔔 TYPING FRAME RECEIVED - processing...
[ChatWebSocketService]    ├─ Parsed data: {fromUserId: 3, isTyping: true}
[ChatWebSocketService] ⌨️✅ Typing indicator PROCESSED: user=3 isTyping=true
[CHATSTORE] 🔤 setTyping CALLED: user=3 isTyping=true
[CHATSTORE]    ├─ ✅ Typing status SET to TRUE for user=3
[CHATSTORE]    ├─ After: _typingStatus={3: true}
[CHATSTORE]    └─ 📢 notifyListeners() called

4️⃣ UI DISPLAYS:
[ChatScreen-DETAIL] 🔤 Typing indicator REBUILD: chatId=3 isTyping=true
[ChatScreen-DETAIL]    ✅ DISPLAYING typing indicator: "Sai is typing…"
[ChatScreen] 📊 ConvItem REBUILD: user=3 isTyping=true
[ChatScreen]    ✅ TYPING DETECTED - displaying "typing..."

5️⃣ USER STOPS TYPING (1.5s debounce):
[Chat] Timer fired - sending TYPING_STOP
[WebSocket] Sending MESSAGE to /app/chat.typing: {"action":"TYPING_STOP","recipientId":2}

6️⃣ RECIPIENT RECEIVES STOP:
[ChatWebSocketService] ⌨️✅ Typing indicator PROCESSED: user=3 isTyping=false
[CHATSTORE] 🔤 setTyping CALLED: user=3 isTyping=false
[CHATSTORE]    ├─ ✅ Typing status CLEARED for user=3
[CHATSTORE]    ├─ After: _typingStatus={}
[CHATSTORE]    └─ 📢 notifyListeners() called

7️⃣ UI UPDATES:
[ChatScreen-DETAIL] 🔤 Typing indicator REBUILD: chatId=3 isTyping=false
[ChatScreen-DETAIL]    └─ Not typing, returning SizedBox.shrink()
```

---

## Debug Checklist

Run the app and look for these log patterns:

### On Sender Side (Person Typing):
- ✅ `[Chat] _onUserTyping CALLED - text=...`
- ✅ `[Chat] ⌨️ Sending TYPING_START`
- ✅ `[WebSocket] Sending MESSAGE to /app/chat.typing`

### On Recipient Side (Person Seeing Typing):
- ✅ `[ChatWebSocketService] 🔔 TYPING FRAME RECEIVED`
- ✅ `[ChatWebSocketService] ⌨️✅ Typing indicator PROCESSED: user=X isTyping=true`
- ✅ `[CHATSTORE] 🔤 setTyping CALLED: user=X isTyping=true`
- ✅ `[CHATSTORE]    ✅ Typing status SET to TRUE`
- ✅ `[ChatScreen-DETAIL] 🔤 Typing indicator REBUILD: chatId=X isTyping=true`
- ✅ `[ChatScreen-DETAIL]    ✅ DISPLAYING typing indicator`

### Auto-Clear (After 3 Seconds):
- ✅ `[CHATSTORE] ⏱️ Typing indicator auto-cleared for user=X (3s timeout)`

---

## Troubleshooting

| Issue | Logs to Check | Solution |
|-------|---------------|----------|
| "typing..." not showing | No `DISPLAYING typing indicator` log | Check WebSocket subscription to `/user/queue/typing` |
| Typing indicator never clears | No `auto-cleared` log | Check ChatStore timer logic |
| No TYPING frame received | No `TYPING FRAME RECEIVED` log | Backend not broadcasting |
| _typingStatus empty | `_typingStatus={}` after setTyping | Check if notifyListeners() is being called |
| UI not rebuilding | No rebuild logs in ChatScreen-DETAIL | Check if Consumer<ChatStore> is connected |

