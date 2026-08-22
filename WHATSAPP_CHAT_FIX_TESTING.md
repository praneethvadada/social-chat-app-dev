# Quick Testing Guide - WhatsApp Chat Fixes

## Pre-Testing Setup

1. **Backend Migration**
   ```bash
   # From MySQL client:
   USE auth_db;
   SOURCE /path/to/migrations/add_chat_deletion_tracking.sql;
   ```

2. **Verify tables created**
   ```sql
   SHOW TABLES LIKE 'chat_deletion%';
   DESC chat_deletions;
   ```

3. **Restart Backend Services**
   ```bash
   ./restart-services.bat
   ```

4. **Rebuild Flutter** (optional, only if compilation errors)
   ```bash
   flutter clean
   flutter pub get
   ```

---

## Test Scenario 1: New Chat Creation (MOST IMPORTANT)

**Setup**: Two devices/users (User A and User B)

**Steps**:
1. **User A (Device 1)**
   - Open app, go to Chats
   - Tap + button → New Chat
   - Search for User B username
   - Tap to open conversation with User B
   - Type message: "Hello from A"
   - Send message

2. **User B (Device 2)**
   - Open app, go to Chats
   - Wait 2-3 seconds (or pull to refresh)
   - **EXPECTED**: New conversation with User A appears
   - **EXPECTED**: Message "Hello from A" visible
   - Open conversation → message appears

**What's Happening**:
- Backend receives message, checks `chat_deletions` table (no entry)
- Sends `new_conversation` WebSocket notification to User B
- User B's ChatsScreen listener receives it and calls `_loadConversations()`
- List refreshes and shows new chat

**Check Logs**:
- Backend console: `[MessageService] New conversation notification sent to user [B's ID]`
- Flutter console (User B): `[ChatsScreen] Received new conversation notification for user [A's ID]`

---

## Test Scenario 2: Chat Deletion Isolation

**Setup**: User A and B have existing conversation with 5+ messages

**Steps**:

### Part A: Delete from User A's side
1. **User A (Device 1)**
   - Open Chats
   - Long-press conversation with User B
   - Tap "Delete" button
   - **EXPECTED**: Conversation disappears from list

2. **User B (Device 2)**
   - Open Chats
   - **EXPECTED**: Conversation with User A STILL THERE
   - Open conversation
   - **EXPECTED**: All previous messages intact

**Check Database**:
```sql
-- From MySQL:
SELECT * FROM chat_deletions WHERE user_id = [A's ID] AND other_user_id = [B's ID];
-- EXPECTED: 1 row exists

-- Messages should still exist:
SELECT COUNT(*) FROM messages WHERE (sender_id=[A's ID] AND receiver_id=[B's ID]) OR (sender_id=[B's ID] AND receiver_id=[A's ID]);
-- EXPECTED: Still has all messages (e.g., 5 rows)
```

### Part B: User B sends message (auto-restore)
3. **User B (Device 2)**
   - Type new message: "Are you there?"
   - Send

4. **User A (Device 1)**
   - Open Chats
   - Wait 2-3 seconds
   - **EXPECTED**: Conversation with User B reappears
   - Open conversation
   - **EXPECTED**: All old messages + new message from B

**Check Database**:
```sql
-- Auto-restore should have deleted the chat_deletion record:
SELECT * FROM chat_deletions WHERE user_id = [A's ID] AND other_user_id = [B's ID];
-- EXPECTED: 0 rows (record deleted)
```

**Check Logs**:
- Backend console: `[MessageService] Auto-restored conversation for recipient [A's ID]`

---

## Test Scenario 3: Multiple Deletions & Re-creation

**Setup**: User A and B conversation exists

**Steps**:
1. **User A**: Delete conversation
   - Verify it's gone from A's list
   - Verify it's still in B's list

2. **User A**: Try to find User B again
   - New Chat → Search User B
   - Send message

3. **User B**: Open Chats
   - **EXPECTED**: Conversation back in list
   - **EXPECTED**: Can see new message

---

## Test Scenario 4: Verify Messages Never Deleted

**Setup**: User A and B have conversation, User A deletes

**Check Database**:
```sql
-- After User A deletes conversation:
SELECT COUNT(*) FROM messages 
WHERE (sender_id=[A's ID] AND receiver_id=[B's ID]) 
   OR (sender_id=[B's ID] AND receiver_id=[A's ID]);

-- EXPECTED: Still shows exact same count as before delete
-- Example: if 5 messages before, still 5 after
```

---

## Test Scenario 5: WebSocket Connection Verification

**Setup**: Two devices, connected to backend

**Steps**:
1. **Device 1 (User A)**:
   - Check Flutter logs for connection:
   ```
   [WS] ===== CONNECTED user=[A's ID] =====
   [WS] ✅ SUBSCRIBED /user/queue/messages
   [WS] ✅ SUBSCRIBED /topic/messages.[A's ID]
   [WS] ✅ SUBSCRIBED /topic/chat/[A's ID]
   [WS] ✅ SUBSCRIBED /topic/calls.[A's ID]
   ```

2. **Verify notification subscription**:
   - Look for: `[WS] 🔔 subscribeToNotifications CALLED`
   - Look for: `[WS] 🔔 listeners count AFTER add=1`

3. **Test new conversation**:
   - Device 1 sends message to Device 2
   - Device 2 should show: `[ChatsScreen] Received new conversation notification for user [A's ID]`

---

## Debugging Commands

### Check WebSocket Connection
```dart
// In Flutter console, run:
// Import ChatWebSocketService in main.dart to access singleton

// Get connection status:
final ws = ChatWebSocketService();
print(ws.getConnectionStatus());

// Output should show:
// [WS HEALTH CHECK]
//   Connected: true
//   Current User: [userId]
//   Listeners: 1
//   Notification Queue Subscribed: true
```

### Check Backend Database
```sql
-- See all deleted conversations
SELECT * FROM chat_deletions;

-- See specific user's deletions
SELECT * FROM chat_deletions WHERE user_id = [USER_ID];

-- Count messages in conversation (shouldn't decrease after delete)
SELECT COUNT(*) FROM messages 
WHERE sender_id=[A] AND receiver_id=[B] OR sender_id=[B] AND receiver_id=[A];

-- Check conversation partners (should exclude deleted)
SELECT DISTINCT CASE WHEN sender_id=[CURRENT_USER] THEN receiver_id ELSE sender_id END 
FROM messages 
WHERE sender_id=[CURRENT_USER] OR receiver_id=[CURRENT_USER];
```

### Check Server Logs
```bash
# Tail backend logs
tail -f app_logs.txt | grep -E "\[MessageService\]|\[CHAT\]|\[WS\]"

# Or in backend console during testing, look for:
# [MessageService] Message sent to /user/[userId]/queue/messages
# [MessageService] New conversation notification sent to user [userId]
# [MessageService] Auto-restored conversation for recipient [userId]
```

---

## Success Criteria

### Test 1: New Chat (✓ PASS if)
- [ ] Chat appears on receiver's device within 3 seconds
- [ ] No manual refresh needed (or refresh triggers it)
- [ ] Message content visible
- [ ] No database errors in logs

### Test 2: Chat Deletion (✓ PASS if)
- [ ] Conversation removed from deleter's list
- [ ] Conversation REMAINS in other user's list
- [ ] Other user can still see all messages
- [ ] Other user can send new messages
- [ ] Database shows no message loss

### Test 3: Auto-Restore (✓ PASS if)
- [ ] When deleted user receives message, chat reappears
- [ ] Happens automatically without manual refresh
- [ ] Old messages + new message both visible
- [ ] No errors in logs

### Test 4: Database (✓ PASS if)
- [ ] No messages are permanently deleted
- [ ] `chat_deletions` tracks per-user deletions
- [ ] Auto-restore removes from `chat_deletions`

---

## Expected Log Output

### Successful New Chat Flow
```
[Backend]
[MessageService] Message sent to /user/[B]/queue/messages
[MessageService] New conversation notification sent to user [B]

[Flutter B]
[ChatsScreen] Received new conversation notification for user [A]
[CHAT] MESSAGE_IN raw={...message data...}
[CHATSTORE] insert incoming otherUserId=[A]
```

### Successful Deletion + Send Flow
```
[Backend]
[MessageService] Conversation deleted for user [A] with user [B]
[INSERT into chat_deletions...]

[User B sends message]
[MessageService] Auto-restored conversation for recipient [A]
[MessageService] New conversation notification sent to user [A]

[Flutter A]
[ChatsScreen] Received new conversation notification for user [B]
[CHAT] MESSAGE_IN raw={...message data...}
[CHATSTORE] insert incoming otherUserId=[B]
```

---

## Troubleshooting

| Problem | Check | Fix |
|---------|-------|-----|
| New chat doesn't appear on receiver | WebSocket connected? Logs show `CONNECTED`? | Ensure backend is running |
| Deleted chat reappears immediately | Is auto-restore triggering on own delete? | This is expected behavior - it's a race condition. User shouldn't see deleted until they send first |
| Messages disappearing | Check DB: `SELECT COUNT(*) FROM messages` | They're not deleted, only hidden via `chat_deletions` |
| WebSocket disconnected | Backend logs show errors? | Check backend service status |
| ChatDeletion entity not found | Did you rebuild backend? | `mvn clean package` in social-service folder |
| Migration errors | Check if table exists | `DESC chat_deletions;` in MySQL |

---

## Quick Reset (for testing multiple times)

```sql
-- Reset all deletions (warning: doesn't restore UI state)
DELETE FROM chat_deletions;

-- Verify messages still exist
SELECT COUNT(*) FROM messages;

-- Check conversations
SELECT COUNT(DISTINCT user_id) FROM (
  SELECT sender_id AS user_id FROM messages 
  UNION 
  SELECT receiver_id FROM messages
) t;
```

---

## Performance Notes

- Query optimization: `chat_deletions` has UNIQUE constraint on (user_id, other_user_id)
- Deletion check: Single indexed lookup, ~1ms
- No full table scans
- Messages table unchanged, so existing queries still efficient
