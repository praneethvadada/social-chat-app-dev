# SQLite Integration - Proper Architecture

## Status
✅ **Reverted to commit `f9b2a92`** - All features working without SQLite
- ✅ Calls working perfectly
- ✅ Chats working perfectly  
- ✅ Typing indicators working
- ✅ Presence updates (online/offline) working
- ✅ Message read receipts working

---

## New Architecture

### **RULE: Separation by Data Type**

#### 1️⃣ **REAL-TIME FEATURES** (Bypass SQLite - Direct WebSocket)
These need instant updates and can't have SQLite latency:

**Calls**
- Signal: `call.initiated` → Direct UI update via Provider
- Status: `call.accepted/declined/ended` → Direct UI update
- Duration updates → Direct timer in UI
- NO SQLite persistence needed (stored separately in call_history table)

**Typing Indicators**
- `typing.start` → Direct UI update (Provider stream)
- `typing.stop` → Direct UI update
- Auto-clear after 3 seconds
- NO SQLite needed

**Presence (Online/Offline)**
- `user.online` → Update Provider state
- `user.offline` → Update Provider state  
- NO SQLite needed (optional: store for last_seen)

**Message Read Receipts**
- `message.read` → Direct UI update
- Mark message as read in UI immediately
- Persist to SQLite in background

#### 2️⃣ **PERSISTENT DATA** (Use SQLite - Async)
These are historical data that need offline access:

**Messages**
- Flow: WebSocket → Insert to SQLite → Refresh ChatStore → UI reads from cache
- Can be async (slight delay acceptable)
- Available offline

**Conversations**
- Flow: WebSocket (new message) → Create/update in SQLite → UI reads from cache
- REST sync on app start (for message history)
- Available offline

**Call Logs**
- Flow: WebSocket call notification → Store in SQLite
- Display from SQLite
- Available offline

---

## Implementation Plan

### Phase 1: Keep Working Features As-Is
✅ **Already Done** - Reverted to working commit

### Phase 2: Add SQLite for Persistence Only
**What to add:**
1. Database schema (messages, conversations, call_logs)
2. Repositories (message_repo, conversation_repo, call_log_repo)
3. ChatSyncService for REST/WebSocket → SQLite
4. ChatStoreSQLite for SQLite → UI cache

**What NOT to change:**
- ❌ Don't modify WebSocket subscription structure
- ❌ Don't route calls through SQLite
- ❌ Don't route typing through SQLite
- ❌ Don't route presence through SQLite
- ✅ Keep all real-time features as Provider streams

### Phase 3: Hybrid Integration
**Architecture:**
```
WebSocket Events
    ↓
    ├─ Call/Typing/Presence → Provider streams (real-time)
    │
    └─ Messages/Conversations → SQLite → ChatStore cache → UI
```

---

## Code Changes Overview

### 1. WebSocket Handler Routing
```dart
// chat_websocket_service.dart
void _onMessageReceived(StompFrame frame) {
  final data = json.decode(frame.body);
  
  switch(data['type']) {
    // REAL-TIME: Direct Provider update
    case 'CALL_INITIATED':
    case 'CALL_ACCEPTED':
    case 'TYPING_START':
    case 'PRESENCE_UPDATE':
      // Update Provider directly - NO SQLite
      updateProviderState(data);
      break;
      
    // PERSISTENT: Route through SQLite
    case 'MESSAGE':
    case 'MESSAGE_READ':
      // Save to SQLite first
      chatSyncService.handleMessage(data);
      break;
  }
}
```

### 2. ChatSyncService (SQLite Layer)
```dart
// chat_sync_service.dart - ONLY handles persistent data
class ChatSyncService {
  
  // REST Sync (on app start)
  Future<void> syncConversationsFromREST() async {
    final conversations = await ApiService.getConversations();
    for (var conv in conversations) {
      await conversationRepo.upsert(conv);
    }
    await chatStore.refresh();
  }
  
  // WebSocket: Insert message to SQLite
  Future<void> handleMessage(Message msg) async {
    await messageRepo.insert(msg);
    await conversationRepo.updateLastMessage(msg);
    // ChatStore listens to repo and auto-refreshes
  }
  
  // WebSocket: Persist call log
  Future<void> handleCallLog(CallHistory call) async {
    await callLogRepo.upsert(call);
  }
}
```

### 3. UI Providers (Real-Time)
```dart
// Keep existing providers:
- CallStateProvider → Direct WebSocket → Real-time updates
- ChatStoreProvider → Reads from SQLite cache (async ok)
- TypingIndicatorProvider → Direct WebSocket stream
- PresenceProvider → Direct WebSocket stream
```

---

## Key Principles

1. **SQLite = Persistence Only**
   - Messages: Need offline access ✅ Use SQLite
   - Conversations: Need offline access ✅ Use SQLite
   - Call logs: Need history ✅ Use SQLite
   - Calls: Real-time only ❌ Skip SQLite
   - Typing: Real-time only ❌ Skip SQLite
   - Presence: Real-time only ❌ Skip SQLite

2. **No SQLite Latency for Real-Time**
   - Calls must respond in <100ms
   - Typing must show instantly
   - Presence must update instantly
   - SQLite operations are async and can take 10-100ms

3. **Async SQLite Operations**
   - All writes to SQLite are async/fire-and-forget
   - UI updates from cache first, SQLite second
   - No blocking on SQLite operations

4. **Cache Pattern**
   - SQLite is source of truth
   - ChatStore is in-memory cache
   - UI reads from ChatStore (fast)
   - ChatStore listens to SQLite changes (via repo callbacks)

---

## Testing Checklist

After implementation, verify:

- [ ] **Calls**: Receive call → Show immediately (not waiting for SQLite)
- [ ] **Typing**: User typing → Show indicator instantly
- [ ] **Presence**: User online → Status updates instantly
- [ ] **Messages**: Send message → Show immediately (optimistic)
- [ ] **Message ACK**: Receive echo → Update status tick
- [ ] **Conversations**: New chat → Conversation appears in list
- [ ] **Offline**: Close app → Reopen → Messages still there
- [ ] **REST Sync**: On app start → Fetch all conversations
- [ ] **Call History**: View past calls from SQLite

---

## Next Steps

1. ✅ Revert to working commit (DONE)
2. ⏳ Verify app runs and calls/chats work
3. ⏳ Add SQLite schema (messages, conversations, call_logs)
4. ⏳ Add repositories (minimal - only CRUD operations)
5. ⏳ Add ChatSyncService (REST sync + SQLite persistence)
6. ⏳ Add ChatStoreSQLite (reads from repo cache)
7. ⏳ Integrate: WebSocket → ChatSyncService → SQLite
8. ⏳ Keep calls/typing/presence as pure WebSocket streams

---

## Files To Create/Modify

### New Files
- `lib/src/database/database_helper.dart` - SQLite schema
- `lib/src/database/message_repository.dart` - Message CRUD
- `lib/src/database/conversation_repository.dart` - Conversation CRUD
- `lib/src/database/call_log_repository.dart` - Call log CRUD
- `lib/src/services/chat_sync_service.dart` - Persistence logic
- `lib/src/state/chat_store_sqlite.dart` - Cache layer
- `lib/src/models/db_models.dart` - SQLite models

### Modified Files
- `lib/main.dart` - Initialize ChatSyncService + SQLite
- `lib/src/services/chat_websocket_service.dart` - Route to ChatSyncService (async)
- `lib/src/screens/chats_screen.dart` - Read from ChatStoreSQLite
- `lib/src/screens/chat_detail_screen.dart` - Read messages from ChatStoreSQLite

### Unchanged Files
- `lib/src/screens/call_screen.dart` - Stays as-is (works perfectly)
- `lib/src/screens/calls_screen.dart` - Stays as-is
- All call-related services - Stay as-is

---

## Success Criteria

✅ All existing features work exactly as before:
- Calls answer/decline/end instantly
- Typing shows in real-time
- Presence updates instantly
- Messages send and display immediately

✅ New persistence features added:
- Conversations persist offline
- Messages persist offline  
- Call history persists
- REST sync on app start loads all data

✅ NO breaking changes to UI/UX
