# Real-Time Chat System - Critical Fixes

## Issues Fixed

### 1. ✅ Message Timestamp Shows Wrong Time (5h issue)
**Problem**: Messages were showing "5h" regardless of actual time, indicating timezone issues.

**Root Cause**: DateTime comparison wasn't handling timezones properly. Local time was being compared with UTC times.

**Fixes Applied**:
- **File**: `lib/src/models/message.dart`
  - Updated `Message.timeAgo` getter to use UTC consistently
  - Added check for negative durations (clock skew handling)
  - Changed from `DateTime.now()` to `DateTime.now().toUtc()`
  - Properly converts `createdAt` to UTC before calculating difference

- **File**: `lib/src/models/message.dart`
  - Same fixes applied to `Conversation.timeAgo` getter

### 2. ✅ Messages Not Being Received in Real-Time
**Problem**: Messages sent from one device not appearing on another device in real-time.

**Root Causes**:
- WebSocket messages weren't being properly delivered via `/user/queue/messages`
- Sender details (name, profile picture) were missing in MessageResponse
- Connection headers not properly extracting userId

**Fixes Applied**:
- **Backend Files Updated**:

  1. **`backend/social-service/src/main/java/com/socialmedia/social/config/WebSocketConfig.java`**
     - Added `WebSocketSecurityInterceptor` registration
     - Added session timeout configuration (1 hour)
     - Improved message broker configuration

  2. **`backend/social-service/src/main/java/com/socialmedia/social/config/WebSocketSecurityInterceptor.java`** (NEW)
     - Intercepts WebSocket CONNECT messages
     - Extracts JWT token from Authorization header
     - Parses token to extract userId
     - Stores userId in session attributes for message routing

  3. **`backend/social-service/src/main/java/com/socialmedia/social/controller/MessageController.java`**
     - Enhanced `sendMessageViaWebSocket()` with proper error handling
     - Added logging for debugging message flow
     - Better userId extraction with fallback handling

  4. **`backend/social-service/src/main/java/com/socialmedia/social/service/MessageService.java`**
     - Improved `sendMessage()` to fetch sender details
     - Enhanced `mapToResponse()` to include senderName and senderProfilePictureUrl
     - Added try-catch blocks with logging
     - Explicit WebSocket send via `convertAndSendToUser()`

  5. **`backend/social-service/src/main/java/com/socialmedia/social/dto/MessageResponse.java`**
     - Added `senderName` field
     - Added `senderProfilePictureUrl` field

- **Mobile App Files Updated**:

  1. **`lib/src/services/chat_websocket_service.dart`**
     - Now subscribes to BOTH `/user/queue/messages` (priority) AND `/topic/messages.${userId}` (fallback)
     - `/user/queue/messages` is subscribed first for direct personal delivery
     - Added improved logging for connection status

### 3. ✅ User Showing "Offline" Even When in Chat
**Problem**: Users appear as "Offline" even though they're actively in the chat.

**Root Causes**:
- No online status tracking on backend
- `isOnline` field hardcoded to `false` in ConversationResponse
- No event listeners for WebSocket connect/disconnect

**Fixes Applied**:
- **Backend Database Migration**:
  - **File**: `backend/add_online_status.sql` (NEW)
  - Adds `is_online` BOOLEAN field to users table (default: false)
  - Adds `last_seen_at` DATETIME field to users table
  - Creates indexes for efficient queries

- **Backend Entity Updates**:

  1. **`backend/social-service/src/main/java/com/socialmedia/social/entity/UserProfile.java`**
     - Added `isOnline` field (Boolean, default: false)
     - Added `lastSeenAt` field (LocalDateTime)

  2. **`backend/social-service/src/main/java/com/socialmedia/social/event/WebSocketEventListener.java`** (NEW)
     - Listens to `SessionConnectedEvent` - sets user online
     - Listens to `SessionDisconnectEvent` - sets user offline
     - Updates `lastSeenAt` when user comes online
     - Includes logging for debugging

  3. **`backend/social-service/src/main/java/com/socialmedia/social/service/UserProfileService.java`**
     - Added `setUserOnlineStatus(Long userId, boolean isOnline)` method
     - Added `isUserOnline(Long userId)` method for queries
     - Both are `@Transactional` for data consistency

  4. **`backend/social-service/src/main/java/com/socialmedia/social/dto/ConversationResponse.java`**
     - Added `isOnline` Boolean field
     - Now returns actual online status instead of hardcoded value

  5. **`backend/social-service/src/main/java/com/socialmedia/social/service/MessageService.java`**
     - Updated `getConversations()` to fetch and include real `isOnline` status
     - Includes online status in `ConversationResponse`

## Implementation Steps

### Step 1: Database Migration
```bash
# Execute this SQL on your database
cd backend
# Run the migration
mysql -u root -p social_media_db < add_online_status.sql
```

### Step 2: Backend Compilation
```bash
cd backend/social-service
mvn clean install
mvn spring-boot:run
```

### Step 3: Redeploy to AWS (if applicable)
```bash
cd backend
# Follow your existing deployment process
./deploy-social-service.sh
```

### Step 4: Mobile App Updates
The Flutter code has been updated. Simply rebuild:
```bash
cd social-media-mobile
flutter clean
flutter pub get
flutter run
```

## Testing Checklist

- [ ] **Timestamp Test**: Send a message and verify it shows "now" or correct time (not 5h)
- [ ] **Real-Time Delivery**: 
  - Open chat on Device A
  - Send message from Device B
  - Message appears instantly on Device A
- [ ] **Online Status Test**:
  - Device A is in chat and shows "Online"
  - Close chat app on Device A
  - Device B should show Device A as "Offline" within 30 seconds
  - Reopen chat on Device A
  - Device B should show Device A as "Online" within 2 seconds
- [ ] **Message Read Receipts**: Verify read receipts work correctly
- [ ] **Multiple Conversations**: Test with 3+ users in different conversations

## Debugging Commands

### Backend Logs
```bash
# Watch real-time logs (if using systemd)
journalctl -u social-service -f

# Or check catalina logs
tail -f /var/log/tomcat/catalina.out
```

### Monitor Online Users
```bash
# SQL query to check online users
SELECT userId, username, isOnline, lastSeenAt FROM users WHERE isOnline = true;
```

### WebSocket Connection Test
-- Check browser console or app logs for messages like:
   - `[WS] Connected successfully`
   - `[WS] Subscribed to /user/queue/messages`
   - `[WS] Message sent to /user/[userId]/queue/messages`

## Important Notes

1. **Token Extraction**: The `WebSocketSecurityInterceptor` extracts userId from JWT token. Ensure your JWT format includes either:
   - `"userId": 123` claim, OR
   - `"sub": "123"` claim

2. **Session Timeout**: Set to 1 hour. Adjust in `WebSocketConfig.java` if needed:
   ```java
   config.setTimeToLiveForSessionId(3600 * 1000); // milliseconds
   ```

3. **Cross-Device Testing**: Always test with actual Android devices or emulators on different machines. Browser testing won't fully replicate mobile WebSocket behavior.

4. **Time Synchronization**: Ensure all servers (backend) and client devices have synchronized system clocks. Use NTP for server time sync.

## Files Modified Summary

### Backend (6 files)
1. `WebSocketConfig.java` - Enhanced with security interceptor
2. `WebSocketSecurityInterceptor.java` - NEW: Extracts userId from JWT
3. `MessageController.java` - Improved message sending
4. `MessageService.java` - Enhanced message routing and sender details
5. `ConversationResponse.java` - Added online status field
6. `UserProfile.java` - Added online status fields

### Backend Events (1 new file)
1. `WebSocketEventListener.java` - NEW: Tracks user online/offline events

### Mobile (2 files)
1. `chat_websocket_service.dart` - Improved subscription to both queues
2. `message.dart` - Fixed timestamp calculation with UTC handling

### Database (1 migration file)
1. `add_online_status.sql` - NEW: Database schema updates

## Support & Troubleshooting

If messages still don't arrive:
1. Check backend logs for WebSocket connection errors
2. Verify JWT token is being sent in WebSocket headers
3. Ensure firewall allows WebSocket connections (port 8082)
4. Check that userId is properly extracted from token
5. Verify message destination: `/user/[userId]/queue/messages`

If online status doesn't update:
1. Confirm database migration ran successfully
2. Check `WebSocketEventListener` logs
3. Verify `UserProfileService.setUserOnlineStatus()` is being called
4. Check database for user's `isOnline` field
