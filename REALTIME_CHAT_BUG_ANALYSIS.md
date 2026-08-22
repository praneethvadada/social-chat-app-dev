# Real-Time Chat Bug Analysis - App Restart & No Receiver Logs

## Critical Issues Identified

### Issue #1: Read Receipt ClassCastException (BLOCKING RECEIVER)
**Location:** `MessageService.java` line 334
**Problem:** Message IDs arrive as `Integer` from JSON, but code expects `List<Long>`
**Error in Logs:**
```
ClassCastException: class java.lang.Integer cannot be cast to class java.lang.Long
at org.hibernate.type.descriptor.java.LongJavaType.unwrap(LongJavaType.java:24)
```
**Impact:** Read receipts crash transaction, marking messages as unread permanently
**Root Cause:** JSON deserializes numbers as `Integer` by default; repository expects `Long`

### Issue #2: userId=0 Infinite Profile Fetch Loop
**Location:** `ChatDetailScreen` logs show repeated requests:
```
[TOKEN RETRIEVED] eyJhbGciOiJIUzUxMiJ9...
========== FETCHING USER PROFILE ==========
userId: 0
[Response Status: 500]
```
**Problem:** Some component is requesting profile for userId=0 repeatedly
**Impact:** 
- Excessive API calls (16+ requests in logs)
- Backend returns 500 error (our validation fix will help)
- Suggests `_currentUserId` is being reset to 0

### Issue #3: NO RECEIVER-SIDE LOGS (CRITICAL)
**Observation:** When device acts as RECEIVER:
- NO `📨 _onMessageReceived CALLED` logs appear
- NO `[RECEIVER]` prefixed logs
- Backend successfully sends to `/user/2/queue/messages` but receiver doesn't process

**Root Causes:**
1. **WebSocket disconnection on app restart** - When app closes:
   - WebSocket connection is dropped
   - User logs in again but `ChatWebSocketService` singleton may NOT reconnect
   - Subscription to `/user/queue/messages` never re-established
   
2. **_currentUserId mismatch** - When device reopens app:
   - New login happens but `_currentUserId` might still be old value
   - User change detection code might not trigger reconnect
   - New messages arrive but app isn't listening

3. **Race condition in ChatStore initialization**:
   - `initState()` calls `_initializeWebSocket()` but may not wait for completion
   - `ChatDetailScreen` initializes before WebSocket is ready
   - Messages arrive while still loading

### Issue #4: Single Tick Display Bug
**Observation:** Previous messages show single tick (✓) instead of double tick (✓✓)
**Root Cause:** Read receipt never successfully processed due to ClassCastException
**Impact:** Users think messages not delivered when they actually are

## Analysis of App Restart Flow

### Current Broken Flow:
1. App closes → WebSocket still connected (?)
2. Device logs in again
3. `ChatDetailScreen.initState()` calls `_initializeWebSocket()`
4. But WebSocket service still has old `_currentUserId`
5. No user-change detection triggered
6. ChatDetailScreen opens but subscription never set up
7. Backend sends messages to `/user/queue/messages` 
8. **No client listening → Messages lost**

### Why Sender Works But Receiver Doesn't:
- **Sender:** Uses optimistic update, shows message immediately + sends via WebSocket
- **Receiver:** Waits for WebSocket message arrival, but connection dropped

## Code Issues Found

### 1. MessageService.java - Line 334
```java
List<Message> messages = messageRepository.findAllById(messageIds);  // messageIds contains Integer, expects Long
```

### 2. ChatWebSocketService.dart - Reconnection Logic
- Line 81-101: User change detection only checks `_isConnected && _currentUserId != userId`
- **Problem:** When app reopens, `_currentUserId` might be 0, so `0 != newUserId` is true
  - But the old WebSocket connection is still active
  - Disconnect might not properly clean up subscriptions

### 3. ChatDetailScreen.dart - Initialization Order
```dart
void initState() {
  _initializeWebSocket();  // Non-blocking
  WidgetsBinding.instance.addPostFrameCallback((_) {
    chatStore.setActiveChat(...);
    // Message loading happens here
  });
}
```
- WebSocket may not be connected yet when `addPostFrameCallback` executes

### 4. Missing Logging
- NO debug logs on RECEIVER side when messages arrive
- Suggests callback never fires
- Indicates subscription not established

## Solution Strategy

1. **Fix ClassCastException** - Convert Integer to Long in read receipt handler
2. **Fix userId=0 loop** - Validate userId before profile fetch
3. **Fix WebSocket reconnection** - Ensure proper cleanup and re-subscribe on app restart
4. **Fix initialization order** - Wait for WebSocket before loading messages
5. **Add receiver-side logs** - Verify subscription callback is firing

