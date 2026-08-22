# Realtime Chat Setup & Testing Guide

## Step 1: Apply Database Migration

````markdown
# Realtime Chat Setup & Testing Guide

## Step 1: Apply Database Migration

Run this SQL command on your `auth_db` database:

```sql
-- Apply this to auth_db
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_online BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS last_seen_at DATETIME;

CREATE INDEX IF NOT EXISTS idx_is_online ON users(is_online);
CREATE INDEX IF NOT EXISTS idx_last_seen_at ON users(last_seen_at);
```

**MySQL Command Line:**
```bash
mysql -u root -p auth_db < add_online_status.sql
```

Or in MySQL Workbench:
1. Open your `auth_db` connection
2. Paste the SQL above
3. Execute

## Step 2: Start Backend Services

All three services must be running:

### 2a. Authentication Service (Port 8081)
```bash
cd backend/auth-service
java -jar target/auth-service-1.0.0.jar --server.port=8081
```
✓ Should show: `Started AuthServiceApplication`

### 2b. Social Service (Port 8082) - **WebSocket Server**
```bash
cd backend/social-service
java -jar target/social-service-1.0.0.jar --server.port=8082
```
✓ Should show: `Started SocialServiceApplication`
✓ You should see: `[WS] User X connected` logs when app connects

### 2c. API Gateway (Port 8080)
```bash
cd backend/api-gateway
java -jar target/api-gateway-1.0.0.jar --server.port=8080
```
✓ Should show: `Started ApiGatewayApplication`

> **Tip:** Open 3 terminal tabs and start these simultaneously

## Step 3: Rebuild Flutter App

```bash
cd social-media-mobile

# Clean and build
flutter clean
flutter pub get
flutter run
```

On the device/emulator, you should see WebSocket connection logs like:
```
[WS] Attempting connection...
[WS] Connected successfully
[WS] Subscribed to /user/queue/messages
[WS] Subscribed to /topic/messages.{userId}
[WS] Subscribed to /user/queue/notifications
```

## Step 4: Test Real-Time Chat (Both Devices)

### Setup
1. Login on **Device A** with user `account_a`
2. Login on **Device B** with user `account_b`
3. Open a chat between them on both devices

### Test 1: Real-Time Message Delivery ✓
**Expected:** Message appears instantly without refresh

```
Device A: Send message "Hello from A"
  ↓
[Check Device B immediately - NO refresh]
  ↓
Device B: Message appears instantly
```

**What's happening behind the scenes:**
- Device A sends `/app/chat.send`
- Backend receives, saves to DB, routes to `/user/{device_b_id}/queue/messages`
- Device B receives via WebSocket listener
- `_onMessageReceived()` fires, `setState()` updates UI

**If it doesn't work:**
- Check Social Service logs for: `[MessageService] Message sent to /user/...`
- Check Flutter logs for: `[WS] frame received on /user/queue/messages`
- Verify API config points to `http://192.168.31.74:8082/ws`

---

### Test 2: Online/Offline Status ✓
**Expected:** Both show "Active" or "Online" while in chat

```
Device A: Open chat
  ↓
Device B: Open same chat
  ↓
[Both show "Online" in header]

Device A: Close app completely
  ↓
[Wait 2-3 seconds]
  ↓
Device B: See "Offline" (might need to refresh conversation list)
```

**What's happening:**
- When Device A connects: `SessionConnectedEvent` → `WebSocketEventListener` → `setUserOnlineStatus(true)`
- When Device A disconnects: `SessionDisconnectEvent` → `setUserOnlineStatus(false)`
- ConversationResponse includes `isOnline` from DB

**If it doesn't work:**
- Check logs for: `[WS] User X connected/disconnected`
- Verify migration added `is_online` column
- Check if UserProfileService.setUserOnlineStatus() is being called

---

### Test 3: Read Receipts (Double Ticks) ✓
**Expected:** Double tick appears instantly when message is read

```
Device A: Send "Test message"
  ↓
Device B: Message appears with single ✓
  ↓
Device B: Scroll up to read the message (app marks as read)
  ↓
Device A: Single ✓ changes to double ✓✓ INSTANTLY
```

**What's happening:**
1. Device B receives message, displays it
2. `_markMessageAsRead()` calls `ApiService.markMessageAsRead()`
3. Backend calls `MessageService.markAsRead()` → sends notification to `/user/{device_a_id}/queue/notifications`
4. Device A receives notification via `subscribeToNotifications()`
5. `_onNotificationReceived()` finds message by ID and sets `isRead = true`
6. `setState()` rebuilds, tick changes to ✓✓

**If it doesn't work:**
- Check Flutter logs for: `[WS] frame received on /user/queue/notifications`
- Check backend logs for: `[MessageService] Error sending read receipt notification:`
- Verify `_onNotificationReceived()` is logging in ChatDetailScreen

---

## Step 5: Debugging Checklist

| Issue | Debug Steps |
|-------|------------|
| **Messages not arriving** | 1. Check backend logs for `/user/queue/messages` routing<br>2. Check Flutter logs for `[WS] frame received`<br>3. Verify Principal is set (check WebSocketSecurityInterceptor logs)<br>4. Ensure both devices have valid JWT tokens |
| **Offline when should be Online** | 1. Check if migration was applied (`is_online` column exists)<br>2. Check backend logs for connect/disconnect events<br>3. Try refreshing conversation list on receiving device |
| **Double ticks not appearing** | 1. Ensure `subscribeToNotifications()` is called in initState<br>2. Check Flutter logs for `[WS] frame received on /user/queue/notifications`<br>3. Check `_onNotificationReceived()` logs in ChatDetailScreen |
| **WebSocket not connecting** | 1. Check API config URL: should be `http://192.168.31.74:8082/ws`<br>2. Verify Social Service is running on port 8082<br>3. Check for Authorization header in STOMP CONNECT<br>4. Check firewall/network (port 8082 accessible) |

## Expected Log Output

### Backend (Social Service)
```
[WS] CONNECT userId=123 principal set
[MessageController] WebSocket message from user 456 to 123
[MessageService] Message sent to /user/123/queue/messages
[WS] User 123 disconnected
```

### Mobile (Flutter)
```
[WS] Attempting connection...
[WS] Connected successfully
[WS] Subscribed to /user/queue/messages
[WS] Subscribed to /user/queue/notifications
[WS] frame received on /user/queue/messages: {...}
[ChatDetailScreen] _onMessageReceived message.id=789
[Chat] Error processing notification: (should be minimal)
```

## Ports Reference

| Service | Port | Purpose |
|---------|------|---------|
| API Gateway | 8080 | REST API, user management, profile |
| Auth Service | 8081 | JWT token validation, authentication |
| Social Service | 8082 | **WebSocket server, messaging, real-time** |
| Database | 3306 | MySQL (auth_db) |

## Quick Verification Commands

```bash
# Check Social Service is listening on 8082
netstat -an | grep 8082

# Check Java processes
jps -l | grep social-service

# Test WebSocket endpoint
curl -i -N -H "Connection: Upgrade" -H "Upgrade: websocket" \
  http://192.168.31.74:8082/ws
```

## What's Been Fixed

✓ WebSocket Principal routing (messages arrive to correct user)
✓ Presence tracking (online/offline status)
✓ Real-time message delivery (no refresh needed)
✓ Real-time read receipts (double ticks appear instantly)
✓ All backend services compiled and ready

## Next Steps if Issues Occur

1. **Check database**: Run `SELECT * FROM users LIMIT 1;` - verify `is_online`, `last_seen_at` columns exist
2. **Check JWT token**: Open Developer Tools → Network → check Authorization header in WebSocket frames
3. **Check routing**: Look for Principal in backend logs - if missing, WebSocket auth failed
4. **Enable verbose logging**: Add to `application.properties`:
   ```properties
   logging.level.com.socialmedia=DEBUG
   logging.level.org.springframework.web.socket=DEBUG
   ```

---

**Ready to test?** Start the three backend services and run the app on both devices! 🚀

````
