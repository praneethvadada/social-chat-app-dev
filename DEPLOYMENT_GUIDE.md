# QUICK DEPLOYMENT GUIDE - Real-Time Chat Fixes

## Summary of All Changes

This document provides a quick reference for all changes made to fix the real-time chat issues:
- Messages not being received in real-time
- Timestamp showing wrong time (5h issue)
- User showing "Offline" even when online

---

## Backend Changes

### 1. Database Migration - ADD ONLINE STATUS TRACKING
**File**: `backend/add_online_status.sql`

Execute this on your database:
```bash
mysql -u [username] -p [database_name] < add_online_status.sql
```

Or manually run:
```sql
ALTER TABLE users ADD COLUMN is_online BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE users ADD COLUMN last_seen_at DATETIME;
CREATE INDEX idx_is_online ON users(is_online);
CREATE INDEX idx_last_seen_at ON users(last_seen_at);
```

### 2. Java Backend Files Modified (6 files)

#### A. WebSocket Configuration 
**File**: `backend/social-service/src/main/java/com/socialmedia/social/config/WebSocketConfig.java`
- ✅ Added `WebSocketSecurityInterceptor` registration
- ✅ Added session timeout (1 hour)
- ✅ Enhanced message broker config

#### B. WebSocket Security Interceptor (NEW)
**File**: `backend/social-service/src/main/java/com/socialmedia/social/config/WebSocketSecurityInterceptor.java`
- ✅ NEW FILE: Extracts userId from JWT token
- ✅ Sets userId in WebSocket session attributes
- ✅ Enables proper message routing to connected users

#### C. Message Controller 
**File**: `backend/social-service/src/main/java/com/socialmedia/social/controller/MessageController.java`
- ✅ Enhanced `sendMessageViaWebSocket()` method
- ✅ Improved userId extraction with logging
- ✅ Better error handling

#### D. Message Service
**File**: `backend/social-service/src/main/java/com/socialmedia/social/service/MessageService.java`
- ✅ Updated `sendMessage()` to fetch sender details
- ✅ Enhanced `mapToResponse()` with senderName and senderProfilePictureUrl
- ✅ Improved `getConversations()` to include real online status
- ✅ Added comprehensive logging

#### E. Message Response DTO
**File**: `backend/social-service/src/main/java/com/socialmedia/social/dto/MessageResponse.java`
- ✅ Added `senderName` field
- ✅ Added `senderProfilePictureUrl` field

#### F. User Profile Entity
**File**: `backend/social-service/src/main/java/com/socialmedia/social/entity/UserProfile.java`
- ✅ Added `isOnline` Boolean field
- ✅ Added `lastSeenAt` LocalDateTime field

#### G. User Profile Service
**File**: `backend/social-service/src/main/java/com/socialmedia/social/service/UserProfileService.java`
- ✅ Added `setUserOnlineStatus(Long userId, boolean isOnline)` method
- ✅ Added `isUserOnline(Long userId)` method

#### H. WebSocket Event Listener (NEW)
**File**: `backend/social-service/src/main/java/com/socialmedia/social/event/WebSocketEventListener.java`
- ✅ NEW FILE: Listens to SessionConnectedEvent (user comes online)
- ✅ NEW FILE: Listens to SessionDisconnectEvent (user goes offline)
- ✅ Updates user online status in database

#### I. Conversation Response DTO
**File**: `backend/social-service/src/main/java/com/socialmedia/social/dto/ConversationResponse.java`
- ✅ Added `isOnline` Boolean field (now returns real status)

---

## Mobile App Changes

### 1. Message Model - Fix Timestamp
**File**: `social-media-mobile/lib/src/models/message.dart`
- ✅ Fixed `Message.timeAgo` getter to use UTC
- ✅ Fixed `Conversation.timeAgo` getter to use UTC
- ✅ Added handling for negative durations (clock skew)

### 2. WebSocket Service - Improved Message Reception
**File**: `social-media-mobile/lib/src/services/chat_websocket_service.dart`
- ✅ Now subscribes to BOTH:
  - `/user/queue/messages` (PRIMARY - direct personal messages)
  - `/topic/messages.${userId}` (FALLBACK - topic-based broadcast)
- ✅ Improved connection logging

---

## Step-by-Step Deployment Instructions

### Prerequisites
- Database access to execute SQL migration
- Backend rebuild capability (Maven)
- Mobile app rebuild capability (Flutter)
- Server restart capability or Docker redeploy

### STEP 1: Database Migration
```bash
# SSH to database server or local execution
mysql -u root -p social_media_db < /path/to/backend/add_online_status.sql

# Verify
mysql -u root -p social_media_db
> SELECT * FROM users LIMIT 1\G  # Check is_online and last_seen_at columns exist
```

### STEP 2: Rebuild Backend
```bash
cd backend/social-service

# Clean build
mvn clean install -DskipTests

# Check for compilation errors
# If successful, you'll see: BUILD SUCCESS
```

### STEP 3: Deploy Backend
```bash
# Option A: Local/Dev Server
mvn spring-boot:run

# Option B: AWS/Production
cd ../
bash deploy-social-service.sh

# Option C: Docker (if using)
docker-compose up -d social-service
```

### STEP 4: Rebuild Mobile App
```bash
cd social-media-mobile

# Clean flutter
flutter clean

# Get dependencies
flutter pub get

# Rebuild
flutter run
# or for release build
flutter build apk --release
```

### STEP 5: Verify Deployment

Test 1 - Check Backend Logs:
```bash
# Should see messages like:
# [WS] User [userId] connected
# [WS] Subscribed to /user/queue/messages
# [MessageService] Message sent to /user/[userId]/queue/messages
tail -f /var/log/tomcat/catalina.out
# or
journalctl -u social-service -f
```

Test 2 - Real-Time Message Test:
1. Open Device A - Login to chat
2. Open Device B - Login to chat with different user
3. Send message from Device B
4. **Expected**: Message appears instantly on Device A (not delayed)

Test 3 - Online Status Test:
1. Device A open chat (shows "Online" next to Device B)
2. Kill app on Device A or put in background for 30 seconds
3. Device B should show Device A as "Offline"
4. Reopen chat on Device A
5. Device B should show Device A as "Online" within 2 seconds

Test 4 - Timestamp Test:
1. Send message from Device A
2. **Expected**: Shows "now" (not "5h" or any wrong time)

---

## Troubleshooting

### Messages Still Not Arriving?
```bash
# Check backend logs for:
grep -i "websocket\|message" /var/log/tomcat/catalina.out | tail -20

# Check if user is online in database:
mysql -u root -p social_media_db
> SELECT userId, username, isOnline FROM users WHERE userId = [test_user_id];
```

### Online Status Not Updating?
```bash
# Verify event listener is loaded:
grep -i "WebSocketEventListener\|SessionConnectedEvent" catalina.out

# Check database migration:
mysql -u root -p social_media_db
> DESCRIBE users;  # Should show 'is_online' and 'last_seen_at' columns
```

### Timestamp Still Wrong?
```bash
# Check server time sync:
date
timedatectl status

# Check MySQL server time:
mysql -u root -p social_media_db
> SELECT NOW(), UTC_TIMESTAMP;
```

### WebSocket Connection Fails?
```bash
# Check firewall for port 8082:
sudo ufw status
sudo ufw allow 8082/tcp

# Check if service is listening:
netstat -tuln | grep 8082
```

---

## Rollback Plan (If Issues Occur)

### Rollback Database Changes
```sql
ALTER TABLE users DROP COLUMN is_online;
ALTER TABLE users DROP COLUMN last_seen_at;
```

### Rollback Code Changes
```bash
# Git rollback
git revert [commit_hash]
git push

# Or manually restore backup files
```

---

## Performance Monitoring

### Query to Monitor Active Users
```sql
SELECT 
    COUNT(*) as active_users,
    COUNT(CASE WHEN isOnline = 1 THEN 1 END) as currently_online,
    MAX(lastSeenAt) as last_activity
FROM users;
```

### WebSocket Connection Metrics
Monitor these in your logs:
- `[WS] User [X] connected` - Count these for active connections
- `[WS] User [X] disconnected` - Track disconnections
- `[MessageService] Message sent to /user/` - Count message deliveries

---

## Important Notes

1. **JWT Token Format**: Ensure your JWT includes either `"userId"` or `"sub"` claim
2. **Timezone Handling**: All systems must use UTC for consistency
3. **Session Timeout**: Currently set to 1 hour - adjust in WebSocketConfig.java if needed
4. **Test With Actual Devices**: Mobile emulators don't always test WebSocket correctly
5. **Network Stability**: WebSocket requires stable connection - test on WiFi first

---

## Files Summary

### New Files Created
- `backend/add_online_status.sql` - Database migration
- `backend/social-service/src/main/java/com/socialmedia/social/config/WebSocketSecurityInterceptor.java`
- `backend/social-service/src/main/java/com/socialmedia/social/event/WebSocketEventListener.java`

### Modified Files
- Backend: 6 files
- Mobile: 2 files
- Database: 1 migration file

**Total: 9 files changed/created**

---

## Support

If issues persist after deployment:
1. Check all backend logs thoroughly
2. Verify database migration executed successfully
3. Restart backend service
4. Clear Flutter build cache and rebuild
5. Test with fresh app install (uninstall old APK first)

Good luck with the deployment! 🚀
