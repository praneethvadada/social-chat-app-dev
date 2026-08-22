# SENDER vs RECEIVER Debug Output Guide

## Overview
All debug logs now clearly distinguish between:
- 🔴 **[SENDER]** - What happens when you SEND a message (Red borders)
- 🟢 **[RECEIVER]** - What happens when you RECEIVE a message (Green borders)

---

## SENDER Side Output (When You Send a Message)

### Step 1: User Clicks Send Button
```
🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴
[SENDER] [Chat] 📤 SENDING MESSAGE
[SENDER] [Chat]  ├─ To userId: 123
[SENDER] [Chat]  ├─ From userId: 456
[SENDER] [Chat]  ├─ Text: "hello world"
[SENDER] [Chat]  ├─ WebSocket connected: true
[SENDER] [Chat]  └─ ChatStore: ✅ initialized
🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴
```

**What it shows:**
- Your user ID (456)
- Recipient ID (123)
- The message text you typed
- Whether WebSocket is connected
- Whether ChatStore is initialized

---

### Step 2: WebSocket Service Processes Send
```
[SENDER] [ChatWebSocketService] ===== SEND_CHAT_MESSAGE =====
[SENDER] [ChatWebSocketService] ✅ Sender ID: 456
[SENDER] [ChatWebSocketService] ✅ ChatStore: initialized
[SENDER] [ChatWebSocketService] ✅ Generated clientMessageId: abc123_987654321
```

**What it shows:**
- Your sender ID confirmed
- ChatStore is ready
- Unique message ID generated

---

### Step 3: Optimistic Message Added (⏱ Appears in UI)
```
[SENDER] [ChatWebSocketService] ✅ Optimistic message added to ChatStore
[SENDER] [ChatWebSocketService]    ├─ clientId: abc123_987654321
[SENDER] [ChatWebSocketService]    ├─ from: 456
[SENDER] [ChatWebSocketService]    ├─ to: 123
[SENDER] [ChatWebSocketService]    └─ status: sending (⏱)
[SENDER] [ChatStore] ✅ INSERT new message
[SENDER] [ChatStore]  ├─ otherUser: 123
[SENDER] [ChatStore]  ├─ clientId: abc123_987654321
[SENDER] [ChatStore]  ├─ serverId: 0
[SENDER] [ChatStore]  └─ status: sending
[SENDER] [ChatStore] 📢 notifyListeners() called (UI will rebuild)
[SENDER] [ChatStore] 📊 Unread count for user=123: 1
```

**What it shows:**
- Message added to state management
- Status is "sending" (⏱ icon in UI)
- UI notified to rebuild
- Message ready to be sent

---

### Step 4: Send to Backend
```
[SENDER] [ChatWebSocketService] ✅ SENT to WebSocket: /app/chat.send
[SENDER] [ChatWebSocketService] ===== END SEND_CHAT_MESSAGE =====

[SENDER] [Chat] ✅ Message queued: clientId=abc123_987654321
🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴
```

**What it shows:**
- Message sent to backend
- Send operation complete
- Ready to wait for server confirmation

---

### Step 5: Server Confirms (⏱ Changes to ✓) - Usually within 2-5 seconds
```
🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴
[SENDER] [ChatWebSocketService] ===== CONFIRMATION RECEIVED =====
[SENDER] [ChatWebSocketService] ✅ Reconciled our optimistic message!
[SENDER] [ChatWebSocketService]    ├─ clientId: abc123_987654321
[SENDER] [ChatWebSocketService]    ├─ serverId: 999
[SENDER] [ChatWebSocketService]    ├─ status: sent (✓)
[SENDER] [ChatWebSocketService]    └─ (UI will update from ⏱ to ✓)
[SENDER] [ChatWebSocketService] ===== END CONFIRMATION =====
[SENDER] [ChatStore] 🔄 RECONCILE message
[SENDER] [ChatStore]  ├─ otherUser: 123
[SENDER] [ChatStore]  ├─ clientId: abc123_987654321
[SENDER] [ChatStore]  ├─ serverId: 999
[SENDER] [ChatStore]  └─ status: sent (updated ⏱ → ✓)
[SENDER] [ChatStore] 📢 notifyListeners() called (UI will rebuild)
[SENDER] [ChatStore] 📊 Unread count for user=123: 1
🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴
```

**What it shows:**
- Server assigned ID: 999
- Message status changed from "sending" to "sent"
- UI updated with ✓ checkmark
- Message now persisted on server

---

## RECEIVER Side Output (When You Receive a Message)

### When Message Arrives from Other User
```
🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢
[RECEIVER] [ChatWebSocketService] ===== MESSAGE RECEIVED FROM OTHER USER =====
[RECEIVER] [ChatWebSocketService] ✅ Added incoming message from user=456
[RECEIVER] [ChatWebSocketService]    ├─ clientId: abc123_987654321
[RECEIVER] [ChatWebSocketService]    ├─ serverId: 999
[RECEIVER] [ChatWebSocketService]    └─ from other user (will appear in UI)
[RECEIVER] [ChatWebSocketService] ===== END MESSAGE RECEIVED =====
[RECEIVER] [ChatStore] ✅ INSERT new message
[RECEIVER] [ChatStore]  ├─ otherUser: 456
[RECEIVER] [ChatStore]  ├─ clientId: abc123_987654321
[RECEIVER] [ChatStore]  ├─ serverId: 999
[RECEIVER] [ChatStore]  └─ status: sent
[RECEIVER] [ChatStore] 📢 notifyListeners() called (UI will rebuild)
[RECEIVER] [ChatStore] 📊 Unread count for user=456: 1
🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢
```

**What it shows:**
- Message received from user 456
- Message stored in ChatStore
- Message will appear in UI immediately
- Status is "sent" (has ✓ checkmark)
- Unread count increased

---

## Complete Two-Device Flow Example

### Device A (Sender):
```
USER TYPES "hello" AND CLICKS SEND

🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴
[SENDER] [Chat] 📤 SENDING MESSAGE
[SENDER] [Chat]  ├─ To userId: 789
[SENDER] [Chat]  ├─ From userId: 456
[SENDER] [Chat]  ├─ Text: "hello"
[SENDER] [Chat]  ├─ WebSocket connected: true
[SENDER] [Chat]  └─ ChatStore: ✅ initialized
🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴

[SENDER] [ChatWebSocketService] ===== SEND_CHAT_MESSAGE =====
[SENDER] [ChatWebSocketService] ✅ Sender ID: 456
[SENDER] [ChatWebSocketService] ✅ ChatStore: initialized
[SENDER] [ChatWebSocketService] ✅ Generated clientMessageId: xyz789_111222333
[SENDER] [ChatWebSocketService] ✅ Optimistic message added to ChatStore
[SENDER] [ChatWebSocketService]    ├─ clientId: xyz789_111222333
[SENDER] [ChatWebSocketService]    ├─ from: 456
[SENDER] [ChatWebSocketService]    ├─ to: 789
[SENDER] [ChatWebSocketService]    └─ status: sending (⏱)
[SENDER] [ChatStore] ✅ INSERT new message
[SENDER] [ChatStore]  ├─ otherUser: 789
[SENDER] [ChatStore]  ├─ clientId: xyz789_111222333
[SENDER] [ChatStore]  ├─ serverId: 0
[SENDER] [ChatStore]  └─ status: sending
[SENDER] [ChatStore] 📢 notifyListeners() called (UI will rebuild)
[SENDER] [ChatStore] 📊 Unread count for user=789: 1
[SENDER] [ChatWebSocketService] ✅ SENT to WebSocket: /app/chat.send
[SENDER] [ChatWebSocketService] ===== END SEND_CHAT_MESSAGE =====

[SENDER] [Chat] ✅ Message queued: clientId=xyz789_111222333
🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴

WAITING FOR SERVER CONFIRMATION...
(Message shows ⏱ in UI)

(2 seconds later - Server responds)

🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴
[SENDER] [ChatWebSocketService] ===== CONFIRMATION RECEIVED =====
[SENDER] [ChatWebSocketService] ✅ Reconciled our optimistic message!
[SENDER] [ChatWebSocketService]    ├─ clientId: xyz789_111222333
[SENDER] [ChatWebSocketService]    ├─ serverId: 1001
[SENDER] [ChatWebSocketService]    ├─ status: sent (✓)
[SENDER] [ChatWebSocketService]    └─ (UI will update from ⏱ to ✓)
[SENDER] [ChatWebSocketService] ===== END CONFIRMATION =====
[SENDER] [ChatStore] 🔄 RECONCILE message
[SENDER] [ChatStore]  ├─ otherUser: 789
[SENDER] [ChatStore]  ├─ clientId: xyz789_111222333
[SENDER] [ChatStore]  ├─ serverId: 1001
[SENDER] [ChatStore]  └─ status: sent (updated ⏱ → ✓)
[SENDER] [ChatStore] 📢 notifyListeners() called (UI will rebuild)
[SENDER] [ChatStore] 📊 Unread count for user=789: 1
🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴🔴

(Message now shows ✓ in UI)
```

### Device B (Receiver):
```
LISTENING FOR MESSAGES FROM USER 456...

(Receives message from server)

🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢
[RECEIVER] [ChatWebSocketService] ===== MESSAGE RECEIVED FROM OTHER USER =====
[RECEIVER] [ChatWebSocketService] ✅ Added incoming message from user=456
[RECEIVER] [ChatWebSocketService]    ├─ clientId: xyz789_111222333
[RECEIVER] [ChatWebSocketService]    ├─ serverId: 1001
[RECEIVER] [ChatWebSocketService]    └─ from other user (will appear in UI)
[RECEIVER] [ChatWebSocketService] ===== END MESSAGE RECEIVED =====
[RECEIVER] [ChatStore] ✅ INSERT new message
[RECEIVER] [ChatStore]  ├─ otherUser: 456
[RECEIVER] [ChatStore]  ├─ clientId: xyz789_111222333
[RECEIVER] [ChatStore]  ├─ serverId: 1001
[RECEIVER] [ChatStore]  └─ status: sent
[RECEIVER] [ChatStore] 📢 notifyListeners() called (UI will rebuild)
[RECEIVER] [ChatStore] 📊 Unread count for user=456: 1
🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢🟢

(Message "hello" appears in Device B's UI)
```

---

## Log Categories Quick Reference

### SENDER Labels (Red 🔴)
- `[SENDER] [Chat]` - User action, checking connection
- `[SENDER] [ChatWebSocketService]` - Message sending, validation, transmission
- `[SENDER] [ChatStore]` - Adding optimistic message
- `[SENDER] [ChatWebSocketService] ===== CONFIRMATION RECEIVED =====` - Server confirms
- `[SENDER] [ChatStore] 🔄 RECONCILE` - Updating from ⏱ to ✓

### RECEIVER Labels (Green 🟢)
- `[RECEIVER] [ChatWebSocketService]` - Message received from other user
- `[RECEIVER] [ChatStore]` - Adding incoming message to state
- `[RECEIVER]` - All about receiving and displaying messages from others

---

## Console Output Pattern

When you run the app with logging enabled:

```bash
flutter logs | grep -E "\[SENDER\]|\[RECEIVER\]"
```

You'll see:

1. **Red bordered section** when you send (🔴)
2. **Red bordered section** when server confirms (🔴)
3. **Green bordered section** when you receive from someone else (🟢)

---

## Troubleshooting by Log Type

### If You See Only SENDER Logs But No CONFIRMATION RECEIVED
- Message was sent but server didn't respond
- Check backend logs for errors
- Verify /app/chat.send endpoint is working

### If You See SENDER Logs But No RECEIVER Logs
- Message reached server but other user didn't receive it
- Check other user's WebSocket connection
- Verify server is sending to /user/{recipientId}/queue/messages

### If You See Both SENDER and RECEIVER Logs Immediately
- Both messages sent and received
- This is expected when testing on same device with two conversations

---

## How to Run & Monitor

```bash
# Terminal 1: Run the app
cd "c:\Users\VAMSI KRISHNA\Desktop\PROJECTS\INTERNSHIP\Mobile App Development\social-media-mobile"
flutter run

# Terminal 2: Filter SENDER/RECEIVER logs
flutter logs | grep -E "\[SENDER\]|\[RECEIVER\]"

# Terminal 3: See ALL chat logs if needed
flutter logs | grep -E "\[Chat\]|\[ChatWebSocketService\]|\[ChatStore\]"
```

---

## Expected Behavior

### Sending Message:
1. ✅ SENDER logs appear (red)
2. ✅ Message shows with ⏱ in UI
3. ✅ CONFIRMATION RECEIVED logs appear (red)
4. ✅ Message updates to ✓ in UI

### Receiving Message:
1. ✅ RECEIVER logs appear (green)
2. ✅ Message appears in UI with ✓ (already confirmed by sender)
3. ✅ No SENDER logs on receiving device (you didn't send it)

---

## Color Code Legend

```
🔴 RED BORDERS = SENDER SIDE
   - What happens when YOU send a message
   - What happens when server confirms YOUR message

🟢 GREEN BORDERS = RECEIVER SIDE
   - What happens when you RECEIVE from someone else
   - How message appears in your UI

⏱ CLOCK = Message is sending
✓ CHECKMARK = Message sent/delivered
```

Perfect! Now you can easily distinguish what's happening on sender vs receiver by the color coding!

