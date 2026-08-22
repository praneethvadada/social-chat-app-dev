# Complete Presence Management System

## Overview
This document explains how user online/offline status is managed across the app lifecycle.

---

## Architecture

### Three Techniques Working Together

1. **Backend Presence Map** - Stores who's currently online on the server
2. **WebSocket Streams** - Real-time presence updates via STOMP messaging
3. **Local ChatStore State** - In-memory map of user online status

---

## Complete User Lifecycle Flow

### SCENARIO 1: User A is Online, User B Logs In

#### User A (Already Online)
- User A is marked as ONLINE in backend presence map
- Real-time broadcast sent to all connected users
- User A's local ChatStore has `_onlineStatus[userIdA] = true`

#### User B Logs In (What Happens)

**Step 1: WebSocket Connection (main.dart)**
```dart
final wsService = ChatWebSocketService();
await wsService.connect(token, userId);  // userId = B
// This triggers _onConnect() callback
```

**Step 2: _onConnect() Callback (chat_websocket_service.dart)**
```dart
// In _onConnect():
_notifyPresenceUpdate(true);  // B sends "I'm ONLINE" to /app/presence.update
_subscribeToPresenceUpdates();  // B subscribes to /user/queue/presence for updates
// Schedules request after 500ms:
Future.delayed(500ms, () => _requestInitialPresence());
```

**Step 3: Backend Processes B's Online Status**
- Backend adds B to presence map
- Backend broadcasts B's online status to all online users (including A)

**Step 4: B Requests Initial Presence (after 500ms)**
```dart
_requestInitialPresence();  // Sends to /app/presence.getInitial
// Backend responds with all currently online users
// Response received on /user/queue/presence
```

**Step 5: Process Presence Data (chat_websocket_service.dart)**
```dart
_onPresenceUpdate(frame) {
  // Parses response: {userId: A, isOnline: true}, {userId: C, isOnline: true}, ...
  _chatStore?.setUserOnline(userId, isOnline);  // Updates local state
}
```

**Step 6: Update Local ChatStore (main.dart)**
```dart
chatStore.setUserOnline(userId, true);  // B's own status
// After 500ms initial presence arrives:
// chatStore.setUserOnline(A, true);  // A is online
// chatStore.setUserOnline(C, true);  // C is online
```

**Step 7: UI Renders**
- **Immediately**: Shows B as ONLINE (from step 6)
- **Within 500ms**: Shows A, C, and others as ONLINE (from step 5)

---

### SCENARIO 2: User B Logs Out

**Step 1: handleLogout() (settings_screen.dart)**
```dart
// Step 1: Send OFFLINE presence
wsService.sendPresenceUpdate(false);  // B sends "I'm OFFLINE"

// Step 2: Disconnect WebSocket
await wsService.disconnect();  // Clears subscriptions, stops receiving updates

// Step 3: Logout from API
await ApiService.logout();

// Step 4: Clear local state
chatStore.clear();  // Clears _onlineStatus map
```

**Step 2: Backend Processes B's Offline Status**
- Backend removes B from presence map
- Backend broadcasts B's offline status to all online users
- User A receives: {userId: B, isOnline: false}
- User A's ChatStore updates: `_onlineStatus[B] = false`

**Why Disconnect WebSocket is Critical**
- If we don't disconnect, WebSocket stays subscribed
- When app reopens, old subscription might get stale presence data
- Causes B to show as "online" even after logout

---

### SCENARIO 3: App Minimized/Backgrounded

**Step 1: App State Changes (main.dart - _AppLifecycleObserver)**
```dart
didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.resumed) {
    // App brought to foreground
    _wsService.sendPresenceUpdate(true);  // Mark as ONLINE again
  }
  
  if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
    // App minimized/closed
    _wsService.sendPresenceUpdate(false);  // Mark as OFFLINE
  }
}
```

**Step 2: Backend Updates Presence Map**
- B is removed from online users
- Other users see B as offline

**Step 3: When App Resumed**
- B is added back to presence map
- Other users see B as online again

**Note on App Lifecycle States:**
- ✅ `resumed` → Send ONLINE
- ✅ `paused` → Send OFFLINE  
- ✅ `detached` → Send OFFLINE
- ❌ `hidden` → IGNORED (too frequent during navigation)
- ❌ `inactive` → IGNORED (fires during dialogs/permissions)

---

## Code Components

### 1. ChatWebSocketService (chat_websocket_service.dart)

**Public Methods:**
- `connect(token, userId)` → Connects, sends online, subscribes to presence, requests initial
- `sendPresenceUpdate(bool isOnline)` → Send online/offline to `/app/presence.update`
- `disconnect()` → Gracefully disconnect, cleanup all subscriptions
- `requestInitialPresence()` → Public method to request who's online (called automatically)

**Private Methods:**
- `_notifyPresenceUpdate(true)` → Called in _onConnect, sends ONLINE
- `_subscribeToPresenceUpdates()` → Subscribes to `/user/queue/presence`
- `_requestInitialPresence()` → Sends to `/app/presence.getInitial` after 500ms
- `_onPresenceUpdate(frame)` → Processes presence updates from backend
- `_onConnect()` → Called when WebSocket connects, orchestrates presence setup

**Presence Data Flow:**
```
[Backend Presence Map]
         ↓
    /user/queue/presence  (broadcast channel)
         ↓
_subscribeToPresenceUpdates()
         ↓
_onPresenceUpdate(frame)
         ↓
_chatStore?.setUserOnline(userId, isOnline)
         ↓
    [Local ChatStore]
         ↓
    [UI Consumers]
```

### 2. ChatStore (chat_store.dart)

**Map:**
```dart
final Map<int, bool> _onlineStatus = {};
```

**Method:**
```dart
void setUserOnline(int userId, bool isOnline) {
  final prev = _onlineStatus[userId];
  _onlineStatus[userId] = isOnline;
  
  if (prev != isOnline) {
    notifyListeners();  // Triggers UI rebuild
  }
}
```

**Consumer in UI:**
```dart
Consumer<ChatStore>(
  builder: (context, chatStore, _) {
    bool isOnline = chatStore.isUserOnline(userId);
    return Text(isOnline ? '🟢 Online' : '⚫ Offline');
  }
)
```

### 3. App Lifecycle Observer (main.dart)

```dart
class _AppLifecycleObserver extends WidgetsBindingObserver {
  final ChatWebSocketService _wsService = ChatWebSocketService();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // App brought to foreground after being backgrounded
        _wsService.sendPresenceUpdate(true);
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // App minimized or closed
        _wsService.sendPresenceUpdate(false);
        break;
      // ... other states ignored
    }
  }
}
```

**Registered in main():**
```dart
WidgetsBinding.instance.addObserver(_appLifecycleObserver);
```

### 4. Login Flow (main.dart - after authentication)

```dart
// Step 1: Connect WebSocket (sends online, subscribes, requests initial)
final wsService = ChatWebSocketService();
await wsService.connect(token, userId);

// Step 2: Set local online status immediately
chatStore.setUserOnline(userId, true);

// Step 3: Continue with chat initialization
// (initial presence will arrive within 500ms)
```

### 5. Logout Flow (settings_screen.dart)

```dart
Future<void> handleLogout() async {
  try {
    // Step 1: Send offline
    final wsService = ChatWebSocketService();
    wsService.sendPresenceUpdate(false);
    
    // Step 2: Disconnect WebSocket completely
    await wsService.disconnect();
    
    // Step 3: Logout from API
    await ApiService.logout();
    
    // Step 4: Clear local state
    chatStore.clear();
    
    // Step 5: Navigate to login
    appNotifier.goToGetStarted();
  } catch (e) {
    // Handle error
  }
}
```

---

## Key Design Decisions

### 1. Single WebSocket Instance (Singleton)
✅ All code uses `ChatWebSocketService()` which returns same instance
✅ Prevents duplicate connections
✅ Prevents duplicate presence broadcasts

### 2. Immediate Local Status Update
✅ `chatStore.setUserOnline(userId, true)` called right after `connect()`
✅ UI shows your own status immediately
✅ Not waiting for server confirmation (backend is trusted)

### 3. Delayed Initial Presence Request (500ms)
✅ Subscriptions need time to be fully active
✅ 500ms is fast enough for user experience
✅ Gets other users' statuses within 500ms of login

### 4. Graceful Logout with Disconnect
✅ Send offline status first
✅ Then disconnect WebSocket
✅ Prevents stale presence data on relogin
✅ Prevents subscriptions from receiving old data

### 5. App Lifecycle Management
✅ Foreground → Send ONLINE
✅ Background → Send OFFLINE
✅ Handles screen off, app minimized, other apps opened
✅ Ignores transient states (hidden, inactive)

---

## Backend Contract (No Modifications Needed)

### What Backend Must Do
1. **Maintain Presence Map** - Store online users
2. **Handle `/app/presence.update`** - Add/remove from map
3. **Broadcast Updates** - Send to all users on `/topic/presence` or individual `/user/queue/presence`
4. **Handle `/app/presence.getInitial`** - Return list of currently online users
5. **Enforce Offline Rules** - Only mark offline under strict conditions (as already implemented)

### What Backend Already Does (as configured)
- ✅ Presence map exists
- ✅ Updates handled
- ✅ Broadcasts sent
- ✅ Initial presence endpoint exists
- ✅ Strict offline conditions enforced

---

## Timeline

### User Logs In
```
T+0ms:    connect() called
T+0ms:    WebSocket connects
T+0ms:    _notifyPresenceUpdate(true) sent
T+0ms:    _subscribeToPresenceUpdates() active
T+0ms:    chatStore.setUserOnline(userId, true) → UI renders "You: ONLINE"
T+500ms:  _requestInitialPresence() sent
T+500ms+: Backend responds with online users
T+500ms+: _onPresenceUpdate() processes response
T+500ms+: chatStore updated with all online statuses → UI renders others' statuses
```

### User Logs Out
```
T+0ms:   sendPresenceUpdate(false) sent
T+10ms:  disconnect() completes
T+50ms:  ApiService.logout() completes
T+100ms: chatStore.clear() clears all status
T+150ms: Navigation to login
```

### App Minimized → Maximized
```
T+0ms:   App enters background (paused event)
T+0ms:   sendPresenceUpdate(false) sent
T+100ms: App brought to foreground (resumed event)
T+100ms: sendPresenceUpdate(true) sent
T+150ms: Backend updates presence
T+150ms: Other users see you as online again
```

---

## Troubleshooting

### Issue: "I see myself as online but not others"
**Cause:** Initial presence request hasn't arrived yet  
**Solution:** Wait 500-700ms, others should appear  
**Fix If Persistent:** Check backend `/app/presence.getInitial` endpoint

### Issue: "After logout, I still show as online"
**Cause:** WebSocket not disconnected before relogin  
**Solution:** Already fixed - we call `disconnect()` during logout  
**Verify:** Check settings_screen.dart has `await wsService.disconnect()`

### Issue: "Status doesn't update when I minimize app"
**Cause:** App lifecycle events not firing properly  
**Solution:** Check AppLifecycleObserver is registered in main()  
**Verify:** Check `WidgetsBinding.instance.addObserver(_appLifecycleObserver)`

### Issue: "Multiple WebSocket instances created"
**Cause:** Code calling `ChatWebSocketService()` multiple times  
**Solution:** Already fixed - ChatWebSocketService is singleton  
**Verify:** All code uses `final wsService = ChatWebSocketService()` (same instance)

---

## Current Status

✅ **Complete** - Presence management fully implemented with:
- Singleton WebSocket instance
- Immediate local status updates
- 500ms initial presence requests
- Graceful logout with disconnect
- App lifecycle monitoring
- No backend changes needed
- No duplicate instances created

