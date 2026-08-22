# Read Receipts Implementation Guide - Complete Fix

## Problem Analysis

**Current Issues:**
1. Device A: Shows message with ✓ only (never updates to ✓✓)
2. Device B: Shows message with ✓✓ immediately (should show ✓ then ✓✓ after sender sees it)
3. Root cause: Read receipt response not reaching Device A, or message status not updating

## Correct Flow Design

```
SENDER (Device A)                      RECEIVER (Device B)
────────────────────────────────────────────────────────────

User sends message
├─ Message created with ⏱ (sending)
└─ Queued to WebSocket

                                      Message arrives at receiver
                                      ├─ Stored with isRead=false
                                      ├─ Displayed with ✓ (sent)
                                      └─ Added to unread count

                                      User opens chat
                                      ├─ Chat marked as active
                                      ├─ All unread messages marked as isRead=true
                                      ├─ UI shows ✓ (sent status persists)
                                      └─ Sends read receipt for message IDs

Receives read receipt from B
├─ Finds message by ID
├─ Updates status to MessageStatus.read
├─ UI shows ✓✓ (double ticks)
└─ Persists to database
```

## Implementation Steps

### Step 1: Verify Message Model (DONE ✓)
- Fields: `id`, `senderId`, `receiverId`, `content`, `status`, `isRead`, `readAt`
- Status enum: `MessageStatus { sending, sent, read }`

### Step 2: Frontend - Properly Mark Messages as Read (CRITICAL)

When chat opens:
1. Get all unread messages for this conversation
2. Mark them as `isRead=true` locally
3. Send read receipt with message IDs
4. Persist to SQLite

When message arrives:
1. Store with `isRead=false` (from server)
2. DO NOT auto-mark as read
3. Only mark as read when user actively views the message

### Step 3: Backend - Send Read Receipt Response

When backend receives `/app/chat.read`:
1. Mark messages in database with `read_at` timestamp
2. Send read receipt back to SENDER (not receiver)
3. Destination: `/user/{senderId}/queue/read-receipts`
4. Include: messageIds, timestamp, recipientId

### Step 4: Frontend - Handle Read Receipt Response

When receiving read receipt:
1. Match by message IDs
2. Update message status to `MessageStatus.read`
3. Persist to SQLite
4. Notify UI to show ✓✓

### Step 5: UI - Display Correctly

```dart
if (message.status == MessageStatus.sent && !message.isRead) {
  // ✓ (single tick - not yet read)
} else if (message.status == MessageStatus.read || message.isRead) {
  // ✓✓ (double ticks - read)
}
```

## Critical Fix Required

The issue is likely in the **read receipt response destination**. Currently:

```java
// WRONG - sends to receiver
messagingTemplate.convertAndSendToUser(
    otherUserId.toString(), 
    "/queue/read-receipts",
    readReceipt
);
```

Should be:

```java
// CORRECT - sends to sender
messagingTemplate.convertAndSendToUser(
    senderId.toString(),  // Person who SENT the message
    "/queue/read-receipts",
    readReceipt
);
```

## Database Persistence

### SQLite (Frontend)
```
messages table:
- id (primary key)
- senderId
- recipientId  
- content
- status (sending/sent/read)
- isRead (0/1)
- readAt (timestamp)
- createdAt

Query: SELECT * FROM messages WHERE recipientId = ? AND isRead = 0
```

### MySQL (Backend)
```
messages table:
- id
- sender_id
- receiver_id
- content
- is_read (0/1)
- read_at (timestamp)
- created_at

Update: UPDATE messages SET is_read=1, read_at=NOW() WHERE id IN (...)
```

## Testing Checklist

### Test 1: Basic Send
- [  ] Device A sends message
- [  ] Message appears with ✓ on Device A
- [  ] Message appears with ✓ on Device B (unread notification)

### Test 2: Open Chat
- [  ] Device B opens chat
- [  ] Message shows ✓ on Device B
- [  ] Read receipt sent from Device B
- [  ] Device A RECEIVES read receipt
- [  ] Message shows ✓✓ on Device A

### Test 3: Close and Reopen
- [  ] Device B closes chat
- [  ] Device A sends new message
- [  ] Message shows ✓ on Device A (NOT ✓✓)
- [  ] Device B opens chat
- [  ] Message shows ✓ on Device B
- [  ] Read receipt sent
- [  ] Device A shows ✓✓

### Test 4: Database Persistence
- [  ] Kill Device A app
- [  ] Device B reads message
- [  ] Device A relaunches
- [  ] Message shows ✓✓ (from database)

## Summary

The **read receipt system must be bidirectional**:
- Sender → Receiver: Message delivery
- Receiver → Sender: Read receipt confirmation
- Both sides must persist the final state to database

The key issue is ensuring the read receipt response is sent to the **SENDER** (not receiver again), with the correct message IDs and status update logic.
