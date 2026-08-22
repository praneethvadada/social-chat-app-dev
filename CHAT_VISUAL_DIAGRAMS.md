# Chat System - Visual Diagrams & Flow Analysis

## Issue #1: Single Tick Not Appearing

### Current (Broken) Flow:
```
Sender sends message
    ↓
Frontend: Creates optimistic with clientMessageId, status=sending ✅
    ↓
Sends to /app/chat.send ✅
    ↓
Backend: Receives, saves to DB ✅
    ↓
Backend: Sends response with id (serverId) ❌ BUT NO STATUS FIELD
    ↓
Frontend receives via STOMP
    ↓
Parses JSON checking: if (id == 0) → sending; else if (isRead) → read; else → sent
    ↓
❌ Response has id=123 but no status field
    ❌ Checks fail, defaults to sent
    ❌ But message ALREADY has status=sending from optimistic
    ✅ Eventually updates (after reload)
```

### Fixed Flow:
```
Sender sends message
    ↓
Frontend: Creates optimistic with clientMessageId, status=sending ✅
    ↓
Sends to /app/chat.send ✅
    ↓
Backend: Receives, saves to DB ✅
    ↓
Backend: Sends response with:
  - id: 123 (serverId)
  - status: "sent"  ✅ NEW FIELD
  - clientMessageId: "abc-123-xyz"
    ↓
Frontend receives via STOMP
    ↓
Parses JSON:
  ✅ Finds status="sent"
  ✅ Sets MessageStatus.sent immediately
  ✅ Clock icon (⏱) → Single tick (✓)
```

---

## Issue #2: Double Ticks Not Appearing

### Current (Broken) Flow:
```
Recipient reads message
    ↓
Backend: markAsRead(messageId) called ✅
    ↓
Backend: Sets isRead=true, readAt=now ✅
    ↓
Backend: Sends notification to /user/sender/queue/notifications
  Message type: "read_receipt"
  MessageIds: [123]
    ↓
Frontend STOMP subscription:
  - Listens to /user/queue/notifications ✅
  - Receives message ✅
  - Checks type: "read_receipt"
    ↓
❌ NO CODE HANDLES THIS TYPE!
❌ Notification ignored
❌ ChatStore never updated
❌ Message stays with single tick (✓)
```

### Fixed Flow:
```
Recipient reads message
    ↓
Backend: markAsRead(messageId) called ✅
    ↓
Backend: Sets isRead=true, readAt=now ✅
    ↓
Backend: Sends notification to /user/sender/queue/notifications
  Message type: "read_receipt"
  MessageIds: [123]
    ↓
Frontend STOMP subscription:
  - Listens to /user/queue/notifications ✅
  - Receives message ✅
  - Checks type: "read_receipt"
    ↓
✅ NEW CODE: _handleReadReceipt()
    ↓
✅ Parses messageIds: [123]
    ↓
✅ Calls chatStore.markMessagesRead(otherId, messageIds: [123])
    ↓
✅ Message gets status=read
    ↓
✅ UI updates: Single tick (✓) → Double tick (✓✓)
```

---

## Issue #3: Own Messages Count as Unread

### Current State:
```
User A sends to User B:
  senderId: A
  recipientId: B
  isRead: false

On User A's side (conversation with B):
  otherUserId: B
  unreadCount = msgs where (recipientId == A && isRead==false)
  
  For message above: recipientId=B, so count=0 ✅ CORRECT!
  
But User A reports: "Badge shows message count"
```

### Analysis:
**Logic in unreadCountForConversation() is CORRECT!**

**Actual Problem:** Backend might be sending wrong recipientId

**Verify:** 
1. Check what backend sends for a message YOU send
2. Log: `System.out.println("Recipient: " + message.getReceiverId())`
3. Verify it equals the correct target user ID

---

## Issue #4: Read Messages Still Show Badge

### Current Flow:
```
User opens chat with User B:
    ↓
Frontend: chatStore.setActiveChat(B)
    ↓
Frontend: chatStore.markMessagesRead(B)
    ↓
ChatStore: Finds all unread messages where recipientId==currentUser
    ↓
✅ Sets isRead=true, readAt=now
    ↓
❌ PROBLEM: Only sends read receipt if idsSet.isNotEmpty
    ↓
When calling with NO specific IDs:
  - Marks ALL messages as read ✅
  - But doesn't collect the IDs ❌
  - sendReadReceipt() is NOT called ❌
    ↓
Backend never notified that messages were read
    ↓
Badge calculation in ChatsScreen:
  unreadCount = from ChatStore
  But ChatStore doesn't know about mark-as-read in UI
    ↓
❌ Badge shows old count
```

### Fixed Flow:
```
User opens chat with User B:
    ↓
Frontend: chatStore.setActiveChat(B)
    ↓
Frontend: chatStore.markMessagesRead(B)
    ↓
ChatStore: Finds all unread messages where recipientId==currentUser
    ↓
✅ Sets isRead=true, readAt=now
    ↓
✅ NEW CODE: Collects ALL message IDs that were marked:
  allMarkedIds = messages where (readAt!=null && recipientId==currentUser)
    ↓
✅ Sends to backend: sendReadReceipt(B, [123, 124, 125])
    ↓
✅ Backend: Notifies User B that messages 123,124,125 were read
    ↓
Badge updates immediately in ChatStore.unreadCountForConversation()
```

---

## Issue #5: Wrong Message Timestamps

### Current Problem:
```
Message JSON from backend:
{
  "id": 123,
  "content": "Hello",
  "createdAt": "2026-01-08T10:30:00Z"  ← Could be missing!
}

Frontend parsing:
```dart
createdAt: json['createdAt'] != null
    ? DateTime.parse(json['createdAt'] as String)
    : DateTime.now().toUtc()  // ❌ WRONG! Sets to current time
```

Example timeline:
- 10:00 AM: User sends message (createdAt: 10:00:00)
- 10:05 AM: Message received by backend (Backend stores createdAt: 10:00:00)
- 10:15 AM: Frontend receives message with missing createdAt
- Frontend sets createdAt to 10:15:00 (current time) ❌
- Message shows as "sent 1m ago" instead of "sent 15m ago"
```

### Fixed Flow:
```dart
createdAt: json['createdAt'] != null
    ? DateTime.parse(json['createdAt'] as String)
    : DateTime(1970, 1, 1).toUtc()  // ✅ Epoch - message appears at bottom

Benefit:
- If createdAt missing, message appears at bottom (1970)
- User sees something is wrong
- Backend logs show which messages have missing timestamps
- Better than silently showing wrong recent time
```

---

## Issue #6: No Typing Indicators

### Current Flow:
```
User A types in chat:
    ↓
Frontend: Sends to /app/chat.typing
  {isTyping: true, receiverId: B}
    ↓
Backend: MessageController.handleTypingViaWebSocket()
    ↓
Backend: Sends to User B via:
  convertAndSendToUser(B, "/queue/notifications", payload)  ❌ WRONG QUEUE!
    ↓
Frontend (User B):
  - Subscribed to /user/queue/typing ✅
  - Subscribed to /user/queue/notifications ❌ Listening but doesn't process "typing" type
    ↓
❌ Typing indicator never shown
```

### Fixed Flow:
```
User A types in chat:
    ↓
Frontend: Sends to /app/chat.typing
  {isTyping: true, receiverId: B}
    ↓
Backend: MessageController.handleTypingViaWebSocket()
    ↓
Backend: Sends to User B via:
  convertAndSendToUser(B, "/queue/typing", payload)  ✅ CORRECT QUEUE
    ↓
Frontend (User B):
  - Subscribed to /user/queue/typing ✅
  - Receives typing notification ✅
  - Calls chatStore.setTyping(A, true) ✅
    ↓
UI updates: Shows "User A is typing..."
    ↓
Auto-clear after 3 seconds or when isTyping=false arrives
```

---

## Issue #7 & #8: Presence & Status

### Current State:
```
No presence service implemented
No status field in database
No way to track online/offline state
No way to persist message status beyond just "read/unread"
```

### What's Needed:
```
Frontend:
  - Send presence update on app lifecycle
  - Listen to presence updates from backend
  - Update ChatStore with online status

Backend:
  - Add PresenceController.updatePresence()
  - Broadcast presence changes to conversation participants
  - Send presence updates when users go online/offline

Database:
  - Track when users were last seen
  - Optional: Add status column for future "away", "dnd", etc.
```

---

## Message Status Flow Diagram

### Complete Message Lifecycle (After Fixes):

```
SENDER SIDE:
┌─────────────────────────────────────────┐
│ 1. User types and sends message        │
│    Status: SENDING (optimistic)        │
│    UI: Clock icon ⏱                   │
└─────────────────────────────────────────┘
            ↓
┌─────────────────────────────────────────┐
│ 2. Message received by backend          │
│    Backend saves to DB                  │
│    Sends response: status="sent"        │
└─────────────────────────────────────────┘
            ↓
┌─────────────────────────────────────────┐
│ 3. Frontend receives confirmation       │
│    Status: SENT                         │
│    UI: Single tick ✓                   │
│    Updates ChatStore                    │
└─────────────────────────────────────────┘
            ↓
         (Network)
            ↓
RECEIVER SIDE:
┌─────────────────────────────────────────┐
│ 4. Message delivered to receiver        │
│    Backend sends to /user/queue/messages│
│    Status: SENT (from server)           │
└─────────────────────────────────────────┘
            ↓
┌─────────────────────────────────────────┐
│ 5. Frontend receives message            │
│    Adds to ChatStore                    │
│    Badge count updates                  │
│    UI: Message appears                  │
└─────────────────────────────────────────┘
            ↓
┌─────────────────────────────────────────┐
│ 6. Receiver opens chat & reads          │
│    Frontend marks as read               │
│    Sends read receipt to backend        │
│    Backend sends notification           │
└─────────────────────────────────────────┘
            ↓
         (Network)
            ↓
BACK TO SENDER:
┌─────────────────────────────────────────┐
│ 7. Sender receives read receipt         │
│    Status: READ                         │
│    UI: Double tick ✓✓                  │
└─────────────────────────────────────────┘
```

---

## Architecture Overview (After Fixes)

```
FRONTEND (Flutter):
┌─────────────────────────────────────────────────────────┐
│ ChatScreen                                              │
│  └─ Displays messages with status icons                │
│     - ⏱ (sending)                                       │
│     - ✓ (sent)                                          │
│     - ✓✓ (read)                                         │
│                                                         │
│ ChatStore (State Management)                           │
│  └─ Stores messages with complete metadata             │
│     - id, clientMessageId, status, readAt              │
│     - Calculates unread count correctly                │
│     - Processes read receipts                          │
│                                                         │
│ ChatWebSocketService                                    │
│  └─ Subscriptions:                                      │
│     - /queue/messages (new messages + confirmations)    │
│     - /queue/typing (typing indicators)                │
│     - /queue/notifications (read receipts + follow)     │
│                                                         │
│ onNotificationReceived():                              │
│  ├─ type="read_receipt" → _handleReadReceipt()        │
│  ├─ type="typing" → chatStore.setTyping()             │
│  └─ type="follow", etc → broadcast to listeners        │
└─────────────────────────────────────────────────────────┘
                    ↕
           WebSocket Bridge
                    ↕
BACKEND (Java):
┌─────────────────────────────────────────────────────────┐
│ MessageController                                       │
│  └─ Receives WebSocket messages                         │
│     - /app/chat.send → MessageService.sendMessage()    │
│     - /app/chat.typing → forward to recipient          │
│                                                         │
│ MessageService                                          │
│  └─ sendMessage():                                      │
│     - Save to DB with createdAt (auto-set)             │
│     - mapToResponse() sets status="sent"               │
│     - Sends to both sender and recipient               │
│                                                         │
│  └─ markAsRead():                                       │
│     - Set isRead=true, readAt=now                      │
│     - Send read_receipt to sender                      │
│                                                         │
│ Message Entity                                          │
│  └─ Fields:                                             │
│     - id, senderId, receiverId                         │
│     - content, mediaUrl                                │
│     - clientMessageId                                  │
│     - isRead, readAt                                   │
│     - createdAt (auto-set by DB)                       │
│     - status (NEW) → for future enhancements           │
│                                                         │
│ MessageResponse DTO                                     │
│  └─ All above fields PLUS:                             │
│     - senderName, senderProfilePictureUrl              │
│     - status: "sending"|"sent"|"read"  ← NEW FIELD     │
└─────────────────────────────────────────────────────────┘
```

---

## Queue Mapping (After Fixes)

```
Frontend Subscriptions:
┌─────────────────────────────────────┐
│ /user/{userId}/queue/messages       │
│  ├─ NEW messages (from other users) │
│  ├─ Message confirmations (echo)    │
│  └─ Status: sent, read              │
│                                     │
│ /user/{userId}/queue/typing         │
│  └─ Typing indicators               │
│     ✅ NOW CORRECT (was wrong)       │
│                                     │
│ /user/{userId}/queue/notifications  │
│  ├─ Follow requests                 │
│  ├─ Likes, Comments                 │
│  ├─ Mentions                        │
│  ├─ Read receipts ✅ (NEW handling) │
│  └─ New conversation notifications  │
└─────────────────────────────────────┘
```

This completes the comprehensive analysis of the chat system issues and fixes!

