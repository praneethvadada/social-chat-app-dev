# Real-Time Chat Fixes Applied - December 27, 2025

## Critical Issues Fixed

### 1. **Messages Not Arriving in Real-Time (One-Sided Failure)**
**Root Cause:** WebSocket STOMP routing relies on the `Principal` (authenticated user) to use `convertAndSendToUser()`. Without it, messages didn't route to the correct recipient queue.

**Fix Applied:**
- **WebSocketSecurityInterceptor.java**: Now validates JWT token via `JwtTokenProvider` on STOMP CONNECT and sets a `UsernamePasswordAuthenticationToken` Principal
- **Backend Build:** Recompiled all services (api-gateway, auth-service, social-service) - BUILD SUCCESS
- **Routing Path:** Sender sends to `/app/chat.send` → MessageService → `convertAndSendToUser(recipientId, "/queue/messages", message)` → Recipient receives instantly

### 2. **Presence (Online/Offline Status) Not Syncing**
**Root Cause:** Presence wasn't being tracked when users connect/disconnect via WebSocket.

**Fix Applied:**
- **WebSocketEventListener.java**: Listens to `SessionConnectedEvent` and `SessionDisconnectEvent`, calls `UserProfileService.setUserOnlineStatus(userId, true/false)`
- **Database:** `is_online` and `last_seen_at` columns exist in `users` table (migration: `add_online_status.sql`)
- **API Response:** ConversationResponse now includes `isOnline` field from UserProfile

### 3. **Messages Not Showing Until App Refreshed**
**Root Cause:** Mobile app wasn't subscribing to the WebSocket `/user/queue/messages` destination properly.

**Fix Applied:**
- **ChatWebSocketService.dart**: Explicitly subscribes to `/user/queue/messages` and fallback `/topic/messages.{userId}` in `_onConnect()`
- **ChatDetailScreen.dart**: Registers listener via `subscribeToConversation(otherUserId, _onMessageReceived)`
- **Message flow:** Incoming STOMP frame → parsed → dispatched to conversation listeners → setState() to update UI

### 4. **Double Ticks Not Appearing Instantly**
**Root Cause:** Client wasn't subscribed to read-receipt notifications from the server.

**Fix Applied:**
- **MessageService.java**: When `markAsRead()` or `markConversationAsRead()` is called, sends notification to `/user/queue/notifications` with `type: 'read_receipt'` and `messageIds`
- **ChatWebSocketService.dart**: New `subscribeToNotifications()` method subscribes to `/user/queue/notifications`
- **ChatDetailScreen.dart**: New `_onNotificationReceived()` handler receives read-receipt notifications and immediately sets `message.isRead = true` for matching message IDs
- **UI Update:** Double tick appears instantly without app refresh

## Architecture Overview

```
Device A (Sender)                  Backend                        Device B (Receiver)
    ↓                              ↓                                  ↓
[User sends message]
    ↓
ChatWebSocketService.sendMessage(recipientId, content)
    ↓
Send to /app/chat.send
    ↓                         MessageController.sendMessageViaWebSocket()
                              ↓
                         MessageService.sendMessage()
                              ↓
                         Save to DB
                              ↓
                         convertAndSendToUser(recipientId, "/queue/messages", response)
                                   ↓
                                   [WebSocket routing via Principal]
                                         ↓
                              ChatWebSocketService._onConnect()
                              subscribes to /user/queue/messages
                                         ↓
                         _handleIncomingMessageFrame(frame)
                                         ↓
                         _onMessageReceived(message)
                                         ↓
                         setState() → UI updates instantly

[User reads message on Device B]
    ↓
_markMessageAsRead(message)
    ↓
ApiService.markMessageAsRead(messageId)
    ↓                         MessageService.markAsRead()
                              ↓
                         convertAndSendToUser(senderId, "/queue/notifications", {
                             type: "read_receipt",
                             messageIds: [messageId],
                             fromUserId: deviceB_userId
                         })
                                   ↓
                              [Notification routed via Principal]
                                         ↓
                         ChatWebSocketService.subscribeToNotifications()
                         _onNotificationReceived(notification)
                                         ↓
                         _onNotificationReceived() updates message.isRead
                                         ↓
                         setState() → Double tick appears instantly
```

## Key Changes Summary

| Component | Change | Purpose |
|-----------|--------|---------|
| `WebSocketSecurityInterceptor.java` | Validate JWT, set Principal on CONNECT | Enable convertAndSendToUser routing |
| `WebSocketEventListener.java` | Track user online/offline on connect/disconnect | Real-time presence |
| `MessageService.java` | Send notifications to `/user/queue/notifications` | Real-time read receipts |
| `ChatWebSocketService.dart` | Subscribe to `/user/queue/messages` and `/user/queue/notifications` | Receive messages and notifications |
| `ChatDetailScreen.dart` | Handle `_onNotificationReceived()` | Update ticks without refresh |

## How to Test

### Prerequisites
1. Database has `is_online`, `last_seen_at` columns in `users` table
2. Both devices have auth tokens (login successful)
3. Both devices have the updated mobile app

### Test Steps
1. **Open chat on both devices**
   - Device A sends message
   - Device B should receive instantly (no refresh needed)

2. **Check presence**
   - Both should show "Active" or "Online"
   - Close chat on Device A
   - Device B should show "Offline" (or update on next chat refresh)

3. **Check double ticks**
   - Device A sends message
   - Device B opens and reads it
   - Device A should show double tick instantly (no refresh)

## Backend Ports
- API Gateway: `8080`
- Auth Service: `8081`
- Social Service (WebSocket): `8082`

## Environment Config
- Mobile: `lib/src/config/api_config.dart` - Points to correct WebSocket URL
- Ensure `Authorization: Bearer {token}` is sent in STOMP CONNECT headers

## Known Limitations
- End-to-end encryption not yet implemented (future enhancement)
- Presence updates only on explicit connect/disconnect (not heartbeat polling)
- Read receipts only sync to sender (receiver can't see if sender has seen their messages)

---
**Status:** Build Success ✓ | Backend Ready ✓ | Mobile Updated ✓ | Ready for Testing
