# Typing Indicator Testing Guide

## Quick Start

### Step 1: Stop all running instances
- Kill Flutter app if running
- Stop backend services (kill ports 8081, 8082 if needed)
- Close any simulators/emulators

### Step 2: Start Backend Services
```bash
# Terminal 1: Start Auth Service (port 8081)
cd backend/auth-service
mvn spring-boot:run

# Terminal 2: Start Social Service (port 8082)  
cd backend/social-service
mvn spring-boot:run

# Verify both started successfully:
# - Auth: "Started AuthServiceApplication in X seconds"
# - Social: "Started SocialServiceApplication in X seconds"
```

### Step 3: Clear Flutter Logs
```bash
# Terminal 3: Clear previous logs
cd social-media-mobile
flutter clean
flutter pub get
```

### Step 4: Run Flutter App with Logging
```bash
# Terminal 3: Run app with verbose logging
flutter run -v 2>&1 | tee flutter_typing_test.log

# This will:
# - Show EVERY log message (not just errors)
# - Save output to flutter_typing_test.log
# - Display in terminal in real-time
```

---

## Test Scenario: Typing Indicator

### Setup
1. Open app on **Device/Simulator A** (User: Sai, ID=3)
2. Open app on **Device/Simulator B** (User: John, ID=2)
3. Navigate to Chat → conversations → Click on conversation with each other

### Test Steps

#### From Device A (Sai - sending typing):
1. Click on chat with John
2. **Start typing** in the message input field
   - Type: `h` (just one character to trigger)
   - Expected: Sends TYPING_START to backend
3. **Watch logs** - look for:
   ```
   [Chat] _onUserTyping CALLED - text=h
   [Chat] ⌨️ Sending TYPING_START to recipient
   [WebSocket] Sending MESSAGE to /app/chat.typing
   ```

#### From Device B (John - receiving typing):
1. **Watch console logs** for:
   ```
   [ChatWebSocketService] 🔔 TYPING FRAME RECEIVED - processing...
   [ChatWebSocketService]    ├─ Headers: {...}
   [ChatWebSocketService]    └─ Body: {"fromUserId":3,"isTyping":true}
   [ChatWebSocketService] ⌨️✅ Typing indicator PROCESSED: user=3 isTyping=true
   [CHATSTORE] 🔤 setTyping CALLED: user=3 isTyping=true
   [CHATSTORE] ✅ Typing status SET to TRUE for user=3
   [CHATSTORE] 📢 notifyListeners() called
   [ChatScreen-DETAIL] 🔤 Typing indicator REBUILD: chatId=3 isTyping=true
   [ChatScreen-DETAIL]    ✅ DISPLAYING typing indicator: "Sai is typing…"
   ```

2. **On Screen B**: Should see **"Sai is typing…"** above the message input box

#### Stop Typing (from Device A):
1. **Clear the message input** (delete the character)
2. Wait 1.5 seconds (debounce timer)
3. Expected: Sends TYPING_STOP
4. Watch logs on Device B:
   ```
   [ChatWebSocketService] ⌨️✅ Typing indicator PROCESSED: user=3 isTyping=false
   [CHATSTORE] 🔤 setTyping CALLED: user=3 isTyping=false
   [CHATSTORE] ✅ Typing status CLEARED for user=3
   [CHATSTORE] 📢 notifyListeners() called
   [ChatScreen-DETAIL] 🔤 Typing indicator REBUILD: chatId=3 isTyping=false
   [ChatScreen-DETAIL]    └─ Not typing, returning SizedBox.shrink()
   ```
5. **On Screen B**: Should see **"Sai is typing…"** disappear

---

## Log Collection

### After Test Completes:
```bash
# The log file should be in:
# social-media-mobile/flutter_typing_test.log

# To view just the typing-related logs:
grep -E "\[ChatWebSocketService\]|\[CHATSTORE\]|\[ChatScreen\]|\[Chat\]" flutter_typing_test.log

# To save a filtered log:
grep -E "\[ChatWebSocketService\]|\[CHATSTORE\]|\[ChatScreen\]|\[Chat\]" flutter_typing_test.log > typing_logs_filtered.txt
```

---

## Expected Output Pattern

**Healthy Workflow (Typing Shows):**
```
SENDER (Device A):
  [Chat] _onUserTyping CALLED - text=h
  [Chat] ⌨️ Sending TYPING_START to recipient
  [WebSocket] Sending MESSAGE to /app/chat.typing

RECEIVER (Device B):
  [ChatWebSocketService] 🔔 TYPING FRAME RECEIVED - processing...
  [ChatWebSocketService]    └─ Body: {"fromUserId":3,"isTyping":true}
  [ChatWebSocketService] ⌨️✅ Typing indicator PROCESSED: user=3 isTyping=true
  [CHATSTORE] 🔤 setTyping CALLED: user=3 isTyping=true
  [CHATSTORE] ✅ Typing status SET to TRUE for user=3
  [CHATSTORE] 📢 notifyListeners() called
  [ChatScreen-DETAIL] 🔤 Typing indicator REBUILD: chatId=3 isTyping=true
  [ChatScreen-DETAIL]    ✅ DISPLAYING typing indicator: "Sai is typing…"

UI SHOWS:
  ✅ "Sai is typing…" visible above message input
```

---

## Troubleshooting

| Symptom | Check Logs For | Action |
|---------|----------------|--------|
| No typing visible | No `DISPLAYING typing indicator` | Check if `[ChatScreen-DETAIL]` logs appear |
| No `[Chat] _onUserTyping` | Message input not working | Verify TextField is clickable |
| No `[ChatWebSocketService] 🔔 TYPING FRAME RECEIVED` | Backend not broadcasting | Check auth-service/social-service logs |
| `isTyping=false` in REBUILD | setTyping called with false | Check if TYPING_STOP sent too early |
| Typing never auto-clears | No `auto-cleared` log | Check 3-second timer in ChatStore.setTyping |

---

## Collect Backend Logs Too

While running test, also capture backend logs:

### From Auth-Service terminal:
```
# Look for typing-related logs (if any)
# Mostly watch for errors in this terminal
```

### From Social-Service terminal:
```
# Look for TYPING message processing logs
# Should see "Broadcasting typing indicator to user X"
```

---

## Save All Logs

After test, save everything for analysis:
```bash
# Flutter logs
cp social-media-mobile/flutter_typing_test.log ./typing_debug_flutter.log

# Filter for key sections
grep -E "TYPING|setTyping|notifyListeners" flutter_typing_test.log > typing_debug_key_logs.txt

# Share both files with me
```

---

## If Still Not Working

Please provide:
1. `flutter_typing_test.log` (complete log from test)
2. `typing_debug_key_logs.txt` (filtered logs)
3. Screenshots of Device B showing what UI displayed
4. Which step did NOT have the expected logs?
   - [ ] No `[Chat] _onUserTyping`
   - [ ] No `[ChatWebSocketService] 🔔 TYPING FRAME RECEIVED`
   - [ ] No `[CHATSTORE] 🔤 setTyping CALLED`
   - [ ] No `[ChatScreen-DETAIL] 🔤 Typing indicator REBUILD`
   - [ ] Logs show but text not visible

