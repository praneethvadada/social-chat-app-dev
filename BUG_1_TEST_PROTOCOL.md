# BUG #1 TEST PROTOCOL: STOMP Callback Not Firing

## 📋 Test Steps

### STEP 1: Enhanced Logging Added ✅
- ✅ Added debug logging to subscription creation
- ✅ Added frame headers and body preview logging
- ✅ Added connection phase logging
- ✅ Added send phase logging  
- ✅ Added error logging

### STEP 2: Prepare Test Environment
1. Make sure Flutter app is **NOT running**
2. If running, stop it: `flutter run` → `q` to quit
3. Clean build: `flutter clean`
4. Get packages: `flutter pub get`

### STEP 3: Start Fresh App with Logging
```bash
cd "c:\Users\VAMSI KRISHNA\Desktop\PROJECTS\INTERNSHIP\Mobile App Development\social-media-mobile"
flutter run -v 2>&1 | tee flutter_debug.log
```

This will:
- ✅ Show all Flutter logs in console
- ✅ Save logs to `flutter_debug.log` for later analysis
- ✅ Include `-v` for verbose output

### STEP 4: Test Message Flow
1. **Wait for login** - App fully loads
2. **Wait for WebSocket connection** - Look for:
   ```
   [ChatWebSocketService] ✅ CONNECTED TO STOMP BROKER
   [ChatWebSocketService] ✅ ALL SUBSCRIPTIONS REGISTERED
   ```
3. **Open a chat** - Select a conversation
4. **Send a test message** - Type message → Press send
5. **Observe logs** - Watch for:

   **EXPECTED LOGS** (Working):
   ```
   [ChatWebSocketService] 📤 SENDING MESSAGE VIA WEBSOCKET
   [ChatWebSocketService]    ├─ clientMessageId: abc-123-xyz
   [ChatWebSocketService]    ├─ recipientId: 5
   [ChatWebSocketService]    ├─ destination: /app/chat.send
   [ChatWebSocketService] ✅ MESSAGE SENT to broker
   [ChatWebSocketService] ⏳ WAITING FOR CONFIRMATION on /user/queue/messages...
   
   [ChatWebSocketService] 🔔🔔🔔 SUBSCRIPTION CALLBACK FIRED for /user/queue/messages 🔔🔔🔔
   [ChatWebSocketService] Frame headers: {message-id: ...}
   [ChatWebSocketService] Frame body preview: {"id":123,"senderId":4...
   [ChatWebSocketService] ===== CONFIRMATION RECEIVED =====
   ```

   **PROBLEM LOGS** (Not Working - THIS IS THE BUG):
   ```
   [ChatWebSocketService] 📤 SENDING MESSAGE VIA WEBSOCKET
   [ChatWebSocketService]    ├─ clientMessageId: abc-123-xyz
   [ChatWebSocketService] ✅ MESSAGE SENT to broker
   [ChatWebSocketService] ⏳ WAITING FOR CONFIRMATION on /user/queue/messages...
   
   [NOTHING - Callback never fires]
   [Clock icon stays forever on message]
   ```

### STEP 5: Capture Output for Analysis
**When callback DOESN'T fire**, copy-paste these sections from logs:
1. Connection phase (look for CONNECTED + SUBSCRIPTIONS REGISTERED)
2. Message send (look for 📤 SENDING MESSAGE)
3. Next 30 seconds of logs (capture if anything arrives)

### STEP 6: Check Backend Logs
Connect to backend server and check if message is actually being sent:
```bash
# On backend server
tail -f /path/to/backend/logs/spring.log | grep "MessageService\|convertAndSendToUser"
```

**Expected backend log:**
```
[MessageService] Message received from user 4 to user 5
[MessageService] Saving message...
[MessageService] ✅ Message saved with ID: 123
[MessageService] Sending to /user/5/queue/messages
[STOMP] Routing message to /user/5/queue/messages
```

---

## 🔍 Root Cause Diagnosis

Based on logs, bug could be caused by:

### SCENARIO A: Subscription Not Actually Registered
**Symptom**: No `✅ Subscription request sent` log
**Cause**: STOMP library bug or already unsubscribed
**Fix**: Reinstall stomp_dart_client package

### SCENARIO B: Message Sent But Backend Not Sending
**Symptom**: `✅ MESSAGE SENT` appears, but no backend send logs
**Cause**: Backend logic not executing or message lost in queue
**Fix**: Need to add backend logging (ask permission)

### SCENARIO C: Backend Sending But Client Not Receiving  
**Symptom**: Backend logs show `[MessageService] Sending to /user/5/queue/messages`, but callback never fires
**Cause**: 
- Session ID mismatch (sent to wrong user)
- STOMP frame format issue
- Network/firewall blocking responses
- STOMP broker routing misconfiguration
**Fix**: Check WebSocket session attributes and STOMP routing

### SCENARIO D: Callback Registered But Silent Failure
**Symptom**: Callback appears to be called but throws error internally
**Cause**: JSON parsing error in callback
**Fix**: Check error logs in callback catch block

---

## 📊 What To Look For

### Connection Logs
```
[ChatWebSocketService] ✅ CONNECTED TO STOMP BROKER
[ChatWebSocketService] 📊 Frame headers: {version: 1.2, server: ...}
[ChatWebSocketService] 🔔 Subscribing to message queue...
[ChatWebSocketService] 📊 DEBUG: STOMP client active=true connected=true
[ChatWebSocketService] 📊 DEBUG: Current user ID=4
[ChatWebSocketService] 📊 DEBUG: Expected destination: /user/queue/messages
[ChatWebSocketService] ✅ Subscription request sent for /user/queue/messages
[ChatWebSocketService] ✅ ALL SUBSCRIPTIONS REGISTERED
```

### Send & Confirm Flow (GOOD)
```
[ChatWebSocketService] 📤 SENDING MESSAGE VIA WEBSOCKET
[ChatWebSocketService]    ├─ clientMessageId: msg-abc-123
[ChatWebSocketService]    ├─ recipientId: 5
[ChatWebSocketService]    ├─ destination: /app/chat.send
[ChatWebSocketService]    └─ body size: 156 bytes
[ChatWebSocketService] ✅ MESSAGE SENT to broker
[ChatWebSocketService] ⏳ WAITING FOR CONFIRMATION on /user/queue/messages...

[ChatWebSocketService] 🔔🔔🔔 SUBSCRIPTION CALLBACK FIRED for /user/queue/messages 🔔🔔🔔
[ChatWebSocketService] Frame headers: {message-id: msg-123, content-length: 156}
[ChatWebSocketService] Frame body preview: {"id":123,"senderId":4,"receiverId":5
[SENDER] [ChatWebSocketService] ===== CONFIRMATION RECEIVED =====
[SENDER] [ChatWebSocketService] ✅ Our message confirmed by server!
```

### Error Indicators
```
[ChatWebSocketService] ❌ STOMP ERROR RECEIVED
[ChatWebSocketService] ❌ WEBSOCKET ERROR
[ChatWebSocketService] ❌ ERROR IN CALLBACK: 
```

---

## ⏱️ Expected Timeline

### If Bug is Frontend-Only
- Add debug logging: ✅ Done
- Identify issue: 30 minutes (from logs)
- Implement fix: 1-2 hours
- Verify: 15 minutes
- **Total: 2 hours**

### If Bug Requires Backend Changes
- Add debug logging: ✅ Done  
- Identify issue: 30 minutes
- Ask permission: 5 minutes
- Implement backend fix: 1-2 hours
- Rebuild & deploy backend: 30 minutes
- Verify: 15 minutes
- **Total: 3-4 hours**

### If Bug is Network/Firewall Related
- May require DevOps team involvement
- **Total: Unpredictable**

---

## 🔄 Next Steps

1. ✅ Add enhanced logging to chat_websocket_service.dart - **DONE**
2. Run test protocol Steps 2-5 above
3. Capture logs and share findings
4. Based on logs, determine root cause (A, B, C, or D)
5. Implement fix
6. Test again to verify callback fires
7. Mark Bug #1 as completed

---

## 📝 Test Checklist

- [ ] Enhanced logging code added to chat_websocket_service.dart
- [ ] App compiles without syntax errors
- [ ] App runs and connects to WebSocket
- [ ] Message sent successfully
- [ ] Callback fires OR doesn't fire (note which)
- [ ] Logs captured and analyzed
- [ ] Root cause identified (Scenario A/B/C/D)
- [ ] Fix implemented
- [ ] Test rerun to verify fix
- [ ] Callback now fires ✅

