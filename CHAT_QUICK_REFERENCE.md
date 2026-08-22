# Chat Debugging Quick Card

## Run These Commands

```bash
# Terminal 1: Run the app
flutter run

# Terminal 2: Monitor logs
flutter logs | grep -E "\[Chat\]|\[ChatWebSocketService\]|\[ChatStore\]"
```

## When You Send a Message, Expected Logs Appear In This Order:

### 1️⃣ User Clicks Send
```
[Chat] 📤 SENDING MESSAGE
[Chat]  ├─ To userId: XXX
[Chat]  ├─ From userId: YYY
[Chat]  ├─ WebSocket connected: true
[Chat]  └─ ChatStore: ✅ initialized
```

### 2️⃣ Service Validates & Creates Message
```
[ChatWebSocketService] ===== SEND_CHAT_MESSAGE =====
[ChatWebSocketService] ✅ Sender ID: YYY
[ChatWebSocketService] ✅ ChatStore: initialized
[ChatWebSocketService] ✅ Generated clientMessageId: abc123_456789
```

### 3️⃣ Optimistic Message Added (⏱ appears in UI)
```
[ChatWebSocketService] ✅ Optimistic message added to ChatStore
[ChatWebSocketService]    └─ status: sending (⏱)
[ChatStore] ✅ INSERT new message
[ChatStore] 📢 notifyListeners() called (UI will rebuild)
```

### 4️⃣ Message Sent to Backend
```
[ChatWebSocketService] ✅ SENT to WebSocket: /app/chat.send
[ChatWebSocketService] ===== END SEND_CHAT_MESSAGE =====
```

### 5️⃣ Server Confirms (⏱ changes to ✓) - Usually within 2-5 seconds
```
[ChatWebSocketService] ===== MESSAGE_RECEIVED (from server) =====
[ChatWebSocketService] ✅ Reconciled our optimistic message!
[ChatWebSocketService]    ├─ status: sent (✓)
[ChatWebSocketService]    └─ (UI will update from ⏱ to ✓)
[ChatStore] 🔄 RECONCILE message
[ChatStore] 📢 notifyListeners() called
```

---

## Common Problems & Quick Fixes

| Problem | Look For This Log | Solution |
|---------|-------------------|----------|
| Message never appears | No `INSERT new message` log | `ChatStore is null` - check main.dart |
| Message shows ⏱ forever | No `MESSAGE_RECEIVED` | Backend not responding - check server logs |
| Error when clicking send | `❌ ERROR: _currentUserId not set` | User not logged in - check login flow |
| WebSocket says not connected | `WebSocket connected: false` | Backend unreachable - check IP/port |
| Message disappears after back | No reconciliation log | Message only optimistic - backend issue |

---

## 3 Critical Checks Before Testing

1. ✅ **App compiles?** → No errors when you run `flutter run`
2. ✅ **Logged in?** → Shows home screen, not login screen
3. ✅ **Backend running?** → Can reach `http://98.92.24.110:8082/ws`

---

## How to Share Logs

**Copy entire log output from Terminal 2 when:**
1. You click send button
2. Wait 5 seconds
3. Paste in our chat

**Example format:**
```
[Chat] 📤 SENDING MESSAGE
[Chat]  ├─ To userId: 123
[Chat]  ├─ WebSocket connected: true
[Chat]  └─ ChatStore: ✅ initialized
[ChatWebSocketService] ===== SEND_CHAT_MESSAGE =====
[ChatWebSocketService] ✅ Sender ID: 456
... (rest of logs)
```

---

## If Something Goes Wrong

1. **Check the ERROR logs** - they start with ❌
2. **Note which logs are MISSING** - they show what failed
3. **Compare with "Expected Logs" section above**
4. **Share what you see + what's missing**

---

## Files That Were Enhanced

| File | What Changed | Why |
|------|-------------|-----|
| chat_screen.dart (line 230) | Added detailed logs when send clicked | See connection status & store state |
| chat_websocket_service.dart (line 399) | Added logs for each step | Track message from creation to send |
| chat_websocket_service.dart (line 269) | Added logs when server responds | Track status change ⏱→✓ |
| chat_store.dart (line 98) | Added logs for insert/reconcile | Track message in state management |

---

## Status Right Now

✅ **Code compiles** - 0 errors  
✅ **Logic is correct** - All methods implemented  
✅ **Logging is in place** - Can see everything  
⏳ **Ready to test** - Just need to run and observe logs

**Your job:** Run app → Send message → Share logs  
**My job:** Look at logs → Identify what's broken → Fix it

---

## Quick Test Checklist

- [ ] App running with `flutter run`
- [ ] Logs filtering with `grep` command
- [ ] Logged into the app
- [ ] Opened a chat conversation
- [ ] Typed test message
- [ ] Clicked send button
- [ ] Watched logs appear
- [ ] Checked if message shows with ⏱
- [ ] Waited 5 seconds to see if ⏱→✓
- [ ] Copied the log output
- [ ] Ready to share results

---

## Need Help?

Look for these specific patterns:

**If you see:**
```
❌ ERROR: _currentUserId not set (0)
```
→ WebSocket not connected to user  
→ Check: Is user logged in?

**If you see:**
```
❌ CRITICAL ERROR: ChatStore is null
```
→ State management not initialized  
→ Check: main.dart line 23

**If you see:**
```
WebSocket connected: false
```
→ Server unreachable  
→ Check: Backend is running at correct URL

**If you see nothing after "SENT to WebSocket":**
→ Server received but didn't respond  
→ Check: Backend logs for errors

---

## TL;DR - Just Do This

```bash
# Window 1
flutter run

# Window 2  
flutter logs | grep -E "\[Chat\]|\[ChatWebSocketService\]|\[ChatStore\]"

# In app:
# 1. Login
# 2. Open chat
# 3. Type "test"
# 4. Click send
# 5. Copy all logs
# 6. Share with me
```

**That's it!** The enhanced logging will show exactly where the problem is.

