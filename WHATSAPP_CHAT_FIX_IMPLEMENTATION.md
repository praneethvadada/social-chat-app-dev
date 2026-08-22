# WhatsApp-like Chat Implementation - Bug Fixes

## Overview
Fixed two critical chat system issues:
1. **New chat creation sync**: New incoming chats now immediately appear in receiver's chat list
2. **Chat deletion isolation**: Deleted chats only disappear from deleter's side, not globally

---

## Changes Made

### 1. Database Schema

**Migration File**: `add_chat_deletion_tracking.sql`
- Created `chat_deletions` table with columns:
  - `id` (PK)
  - `user_id` (FK to users)
  - `other_user_id` (FK to users)
  - `deleted_at` (TIMESTAMP)
  - Unique constraint on (user_id, other_user_id)

- This tracks which users have deleted which conversations
- Messages are NEVER deleted, only marked as deleted for specific users

**Updated `messages` table**:
- Added `media_url` (VARCHAR 500)
- Added `client_message_id` (VARCHAR 255 UNIQUE)
- Added `read_at` (DATETIME)

---

### 2. Backend Java Implementation

#### New Entity: `ChatDeletion.java`
Located in: `backend/social-service/src/main/java/com/socialmedia/social/entity/ChatDeletion.java`

```java
@Entity
@Table(name = "chat_deletions", uniqueConstraints = {...})
public class ChatDeletion {
    private Long id;
    private Long userId;
    private Long otherUserId;
    private LocalDateTime deletedAt;
}
```

#### New Repository: `ChatDeletionRepository.java`
Located in: `backend/social-service/src/main/java/com/socialmedia/social/repository/ChatDeletionRepository.java`

Methods:
- `findByUserIdAndOtherUserId()` - Find deletion record
- `hasUserDeletedConversation()` - Check if conversation was deleted by user

#### Updated DTO: `MessageRequest.java`
Added field:
- `clientMessageId` (String) - Client-generated unique ID for optimistic message handling

#### Updated Service: `MessageService.java`
Location: `backend/social-service/src/main/java/com/socialmedia/social/service/MessageService.java`

**Modified Methods**:

1. **sendMessage()**
   - Now includes auto-restoration logic:
     - If recipient deleted this conversation, it auto-restores
     - Sends `new_conversation` WebSocket notification to recipient
   - Preserves `clientMessageId` from request

2. **getConversations()**
   - NEW: Checks `chatDeletionRepository.hasUserDeletedConversation()`
   - Filters out conversations deleted by current user
   - Other user still sees the conversation

3. **deleteConversation()**
   - CHANGED: Instead of deleting messages, creates ChatDeletion record
   - Tracks which user deleted which conversation

4. **restoreConversation()** (NEW)
   - Removes ChatDeletion record, bringing conversation back
   - Called automatically when recipient receives new message from deleter

#### Updated Controller: `MessageController.java`
Location: `backend/social-service/src/main/java/com/socialmedia/social/controller/MessageController.java`

New Endpoint:
- `POST /messages/conversation/{otherUserId}/restore`
- Restores a deleted conversation for current user

---

### 3. Flutter Implementation

#### Updated Service: `chat_websocket_service.dart`
Location: `social-media-mobile/lib/src/services/chat_websocket_service.dart`

**Changes to `_handleIncomingMessageFrame()`**:
- Added handler for `type == 'new_conversation'`:
  - Extracts userId, username, profilePictureUrl
  - Notifies all listeners with new_conversation data
  - Triggers chat list refresh on receiver side

**How it works**:
1. User A sends first message to User B
2. Backend saves message and creates `new_conversation` notification
3. WebSocket sends notification to User B
4. ChatsScreen listener receives notification
5. Conversation list refreshes and shows User A's chat

#### Updated Store: `chat_store.dart`
Location: `social-media-mobile/lib/src/state/chat_store.dart`

New Method:
```dart
void ensureConversation(int otherUserId) {
  if (!_messagesByUser.containsKey(otherUserId)) {
    _messagesByUser[otherUserId] = [];
    notifyListeners();
  }
}
```
- Ensures conversation exists (for pre-creating empty conversations)

#### Updated Screen: `chats_screen.dart`
Location: `social-media-mobile/lib/src/screens/chats/chats_screen.dart`

**Changes**:
1. Import `ChatWebSocketService`
2. Create `_webSocketService` instance in initState
3. Subscribe to notifications with `_handleNotification()` callback
4. When `new_conversation` notification received:
   - Refresh conversation list via `_loadConversations()`
   - New chat automatically appears for receiver

5. Unsubscribe in dispose

---

## How It Works (Flow Diagrams)

### Scenario 1: New Chat Creation (User A → User B)

```
User A                          Backend                        User B
   │
   │  1. Search & tap User B
   │──────────────────────────────────────────────────────────────→
   │                          ✓ Found in database
   │  2. Send first message
   │──────────────────────────────────────────────────────────────→
   │                          ✓ Save Message
   │                          ✓ Check: Has B deleted (A,B)? NO
   │                          ✓ Create new_conversation notification
   │                          ✓ Send via /queue/notifications
   │                                                               ← new_conversation event
   │                                                               ✓ ChatsScreen listener fires
   │                                                               ✓ _loadConversations()
   │                                                               ✓ Shows new chat with A
```

### Scenario 2: Chat Deletion (User A deletes chat with B)

```
User A                          Backend                        User B
   │
   │  1. Select & delete conversation
   │──────────────────────────────────────────────────────────────→
   │                          ✓ INSERT chat_deletions(A, B)
   │                          ✓ Messages STAY in DB
   │                          ✓ Return success
   │
   ✓ Chat removed from A's list
   
                                                               User B
                                                               - Conversation still visible
                                                               - All messages still there
                                                               - Can still send to A
```

### Scenario 3: Deleted User Sends Message (A deleted B, B sends to A)

```
User B                          Backend                        User A
   │
   │  1. Send message to A (who deleted the chat)
   │──────────────────────────────────────────────────────────────→
   │                          ✓ Save Message
   │                          ✓ Check: Has A deleted (A,B)? YES
   │                          ✓ DELETE from chat_deletions(A,B)
   │                          ✓ Send new_conversation notification
   │                          ✓ Send message via /queue/messages
   │                                                               ← new_conversation + message
   │                                                               ✓ ChatsScreen listener fires
   │                                                               ✓ _loadConversations()
   │                                                               ✓ Shows restored chat with B
```

---

## Database Impact

### Before (Old System)
```sql
-- Deleting conversation between User 1 and User 2
DELETE FROM messages WHERE (sender_id=1 AND receiver_id=2) OR (sender_id=2 AND receiver_id=1);
-- PROBLEM: Both users lose all messages
```

### After (New System)
```sql
-- User 1 deletes conversation with User 2
INSERT INTO chat_deletions (user_id, other_user_id, deleted_at) 
VALUES (1, 2, NOW());
-- MESSAGES INTACT for User 2

-- User 2 receives message from User 1
-- Backend auto-executes:
DELETE FROM chat_deletions WHERE user_id=2 AND other_user_id=1;
-- Chat restored for User 2
```

---

## Testing Checklist

### Test Case 1: New Chat Creation
- [ ] User A opens app, searches for User B (not in contacts)
- [ ] User A sends message to User B
- [ ] User B's chat list refreshes (may need manual refresh)
- [ ] User B sees new conversation with User A
- [ ] Can open conversation and see all messages

### Test Case 2: Chat Deletion Isolation
- [ ] User A and B have conversation
- [ ] User A: Long-press chat → Delete
- [ ] User A's chat list: Conversation gone ✓
- [ ] User B's chat list: Conversation still there ✓
- [ ] User B can still send messages to A
- [ ] Messages are preserved in database

### Test Case 3: Deleted User Receives Message
- [ ] User A and B have conversation
- [ ] User A deletes chat with B
- [ ] User B sends new message to A
- [ ] User A's chat list automatically refreshes (via WebSocket)
- [ ] Conversation reappears with all old messages + new message

### Test Case 4: Multiple Deletions
- [ ] User A and B have multiple messages
- [ ] User A deletes chat with B
- [ ] User A deletes chat again (from trash/archived) - should handle gracefully
- [ ] No errors in logs

### Test Case 5: WebSocket Notifications
- [ ] Check server logs: `[MessageService] New conversation notification sent to user ...`
- [ ] Check Flutter logs: `[ChatsScreen] Received new conversation notification for user ...`
- [ ] Check Flutter logs: `[NEW_CONV] notification from userId=...`

---

## Files Modified

### Backend (Java)
1. `backend/social-service/src/main/java/com/socialmedia/social/entity/ChatDeletion.java` - **NEW**
2. `backend/social-service/src/main/java/com/socialmedia/social/repository/ChatDeletionRepository.java` - **NEW**
3. `backend/social-service/src/main/java/com/socialmedia/social/dto/MessageRequest.java` - MODIFIED
4. `backend/social-service/src/main/java/com/socialmedia/social/service/MessageService.java` - MODIFIED
5. `backend/social-service/src/main/java/com/socialmedia/social/controller/MessageController.java` - MODIFIED
6. `backend/migrations/add_chat_deletion_tracking.sql` - **NEW MIGRATION**

### Frontend (Flutter)
1. `social-media-mobile/lib/src/services/chat_websocket_service.dart` - MODIFIED
2. `social-media-mobile/lib/src/state/chat_store.dart` - MODIFIED
3. `social-media-mobile/lib/src/screens/chats/chats_screen.dart` - MODIFIED

---

## Migration Steps

### 1. Database Migration
```bash
cd backend
mysql -u root -p < migrations/add_chat_deletion_tracking.sql
```

Or if using Flyway migrations:
- Place migration file in `resources/db/migration/`
- Run: `mvn flyway:migrate`

### 2. Backend Rebuild
```bash
cd backend/social-service
mvn clean package
```

### 3. Frontend Update
```bash
cd social-media-mobile
flutter pub get
flutter clean
flutter run
```

---

## Deployment Notes

1. **Database First**: Run migration BEFORE deploying new code
2. **Backward Compatibility**: Existing messages and conversations unaffected
3. **No User Action Required**: Works transparently after deployment
4. **Rollback Safe**: Can revert code, but keep chat_deletions table (harmless)

---

## Potential Enhancements

1. **Archive vs Delete**: Add soft archive feature (don't show in list, but retain)
2. **Restore from Trash**: Add trash/recently deleted view
3. **Batch Operations**: Optimize deletion of multiple conversations
4. **Notification Preferences**: Let users opt-out of auto-restore
5. **Read Receipts**: Ensure works correctly with per-user deletion

---

## Known Limitations

1. Conversation list refresh on receiver uses polling (loads from REST)
   - Future: Could optimize with local state update if we cache user info
2. Very large conversations (10k+ messages) - no pagination changes yet
   - Existing pagination still works

---

## Support & Debugging

### Common Issues

**Issue**: New chat doesn't appear on receiver's device
- **Check**: Is ChatWebSocketService connected? Look for `[WS] ✅ CONNECTED`
- **Check**: Is notification listener registered? Look for `[WS] 🔔 subscribeToNotifications CALLED`
- **Check**: Check backend logs for `[MessageService] New conversation notification sent to user`

**Issue**: Deleted conversation reappears after delete
- **Check**: Is auto-restore working? Look for `[MessageService] Auto-restored conversation`
- **Solution**: This is expected - chat re-appears when sender messages deleted user

**Issue**: Messages disappearing
- **Check**: Check database - messages should still exist
- **Solution**: Messages are never deleted, only hidden via chat_deletions table

---

## Code Statistics

- Lines Added: ~250 (Flutter) + ~150 (Java) = 400 total
- Files Created: 3 (ChatDeletion entity/repo + migration)
- Files Modified: 6
- No breaking changes to existing APIs
