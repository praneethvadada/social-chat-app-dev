# Testing & Verification Guide

## ✅ Build Status
- [x] App compiles with no errors
- [x] All dependencies installed
- [x] SQLite database created
- [x] Persistence helper initialized

## 🧪 Testing Checklist

### Phase 1: Startup Verification
```
When app launches:
  ✓ No errors in console
  ✓ WebSocket connects (should see "WebSocket CONNECTED" logs)
  ✓ SQLite initializes (should see "[SQLITE_HELPER] Attached to all streams")
  ✓ App loads normally (no lag, no crashes)
```

### Phase 2: Realtime Features (Unchanged)
```
These should work EXACTLY as before:

Calls:
  ✓ Can make outgoing calls
  ✓ Can receive incoming calls
  ✓ Call audio works
  ✓ Calling UI responsive
  ✓ Can accept/decline/end calls

Messaging:
  ✓ Can type messages (no lag)
  ✓ Typing indicators work
  ✓ Messages send immediately (optimistic UI)
  ✓ Message status updates (clock → tick → double tick)
  ✓ Incoming messages appear instantly

Presence:
  ✓ Online status shows for users
  ✓ Status updates when user comes online/offline
  ✓ No delay in presence updates

Read Receipts:
  ✓ Messages show single tick when sent
  ✓ Messages show double tick when read
```

### Phase 3: SQLite Persistence (New)
```
These are automatically persisted in SQLite:

Messages:
  ✓ Messages saved to SQLite after sending
  ✓ Incoming messages saved to SQLite
  ✓ Message status saved (SENDING → SENT → READ)

Conversations:
  ✓ Conversation created when first message sent
  ✓ Last message metadata saved
  ✓ Unread count saved
  ✓ Timestamps saved

(Note: Currently not loaded on app restart - future enhancement)
```

### Phase 4: Log Verification
```
Check console logs for:

✓ "[SQLite] Creating tables for SQLite..."
✓ "[SQLITE_HELPER] Initialized (write-behind cache)"
✓ "[MAIN] 🗄️  Initializing SQLite persistence layer..."
✓ "[MAIN] ✅ SQLite database initialized"
✓ "[SQLITE_HELPER] Attaching to ChatService streams..."
✓ "[SQLITE_HELPER] ✅ Attached to all streams (passive listening)"

When sending messages:
✓ "[SQLITE_HELPER] ✅ Message persisted to SQLite: ..."

When receiving messages:
✓ "[SQLITE_HELPER] ✅ Message persisted to SQLite: ..."

When marking as read:
✓ "[SQLITE_HELPER] ✅ Updated message status: ..."
```

## 🔍 How to Verify SQLite is Working

### Check 1: Database File Created
```
Location: 
  Android: /data/data/com.example.social_chat_app/databases/social_chat.db
  
Use Android Studio Device File Explorer:
  1. Open Android Studio
  2. Device File Explorer → data → data → com.example.social_chat_app → databases
  3. Look for social_chat.db (should be created after first run)
```

### Check 2: Console Logs
```
Watch console for:
  [DB] Creating tables for SQLite...
  [DB] ✅ messages table created
  [DB] ✅ conversations table created
  [DB] ✅ Database schema created successfully
```

### Check 3: Stream Emission Logs
```
When message sent:
  [SQLITE_HELPER] ✅ Message persisted to SQLite: clientId=..., status=SENDING

When message ACKed:
  [SQLITE_HELPER] ✅ Updated message status: clientId=..., status=SENT

When message read:
  [SQLITE_HELPER] ✅ Updated message status: clientId=..., status=READ
```

## 🚀 Test Scenarios

### Scenario 1: Send Message
```
1. Open app
2. Go to Chats
3. Open conversation or start new chat
4. Type message and send
5. Verify:
   - Message appears instantly (optimistic UI)
   - Check logs for "[SQLITE_HELPER] ✅ Message persisted"
   - Message shows clock icon briefly
   - Message shows single tick after server ACK
   - No lag in UI
```

### Scenario 2: Receive Message
```
1. Have two users in app
2. User A sends message to User B
3. User B should see:
   - Message appears instantly
   - Check logs for "[SQLITE_HELPER] ✅ Message persisted"
   - No lag in UI
   - Message shows with timestamp
```

### Scenario 3: Read Status
```
1. User A sends message to User B
2. User A should see:
   - Single tick (sent)
   - Double tick (read) after User B opens conversation
3. Check logs for read receipt persistence
```

### Scenario 4: Incoming Call
```
1. User A calls User B
2. Verify:
   - Call rings instantly (unchanged)
   - No lag in UI
   - Call audio works
   - Call can be accepted/declined
   - No SQLite interference
```

## ⚠️ Troubleshooting

### Issue: App crashes on startup
```
Solution:
  1. Check logs for error messages
  2. Verify sqflite dependency installed (flutter pub get)
  3. Check database_helper.dart has correct imports
  4. Try: flutter clean && flutter pub get && flutter run
```

### Issue: SQLite not persisting
```
Solution:
  1. Check "[SQLITE_HELPER] ✅ Attached to all streams" log
  2. Verify streams are being emitted (check for message/read receipt logs)
  3. Check database file exists in device storage
  4. Verify ConflictAlgorithm.replace is used (should overwrite duplicates)
```

### Issue: Slowness or lag
```
Solution:
  1. SQLite writes are non-blocking - should NOT cause lag
  2. If lag exists, check if it's from realtime features (unrelated)
  3. SQLite persistence happens AFTER UI update (user won't notice)
```

### Issue: Messages not showing status updates
```
Solution:
  1. This is expected for now (SQLite reads not implemented yet)
  2. Message status updates from ChatStore (unchanged)
  3. SQLite just records the status for future use
```

## 📊 Performance Expectations

- **Message Send**: Instant (optimistic UI) - no change
- **Message ACK**: <100ms - no change
- **Read Receipt**: <100ms - no change
- **Call Setup**: <500ms - no change
- **SQLite Write**: Async, non-blocking - ZERO user impact

## 🎯 Success Criteria

✅ **App works exactly like before**
✅ **No lag, no crashes, no errors**
✅ **Calls, messages, presence all work**
✅ **SQLite silently persists data**
✅ **Console shows persistence logs**
✅ **Database file created on device**

If all of the above are true: **✅ IMPLEMENTATION SUCCESSFUL**

## Next Steps (Future Enhancements)

These are NOT implemented yet but can be added later:

1. **Load messages on app startup** (from SQLite)
2. **Restore conversation list** (from SQLite)
3. **Offline message queue** (using SQLite)
4. **Message search** (from SQLite)
5. **Chat history export** (from SQLite)

Current implementation prepares the database for these features.
