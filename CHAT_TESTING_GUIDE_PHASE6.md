# Chat Fixes Phase 6 - Testing Guide

## Quick Start Testing

### Prerequisites
- Two devices or emulators running the app
- Device 1: User "sai" (ID: 2)
- Device 2: User "vamsi" (ID: 3)
- Both connected to same Wi-Fi (192.168.31.74:8082)

## Test Case 1: Read Receipts (Double Ticks)

### Steps
1. **User A (Device 1 - sai):** Open chat with User B (vamsi)
2. **User A:** Send message "Test read receipt"
   - Observe: ✓ (single tick) appears immediately
3. **User B (Device 2 - vamsi):** Open chat with User A (sai)
   - Message should appear and auto-mark as read
4. **User A:** Look at message
   - Expected: ✓✓ (double tick) should appear after ~1-2 seconds

### Expected Logs (Frontend - Device A)
```
[ChatWebSocketService] 📨 _onMessageReceived CALLED
[ChatWebSocketService] 💬 FRAME TYPE: REGULAR_MESSAGE detected
[SENDER] [ChatWebSocketService] ===== CONFIRMATION RECEIVED =====

[ChatWebSocketService] 📨 _onMessageReceived CALLED
[ChatWebSocketService] Data keys: fromUserId, messageIds, type, toUserId, timestamp
[ChatWebSocketService] 📖 FRAME TYPE: READ_RECEIPT detected
[ChatWebSocketService] 📖 Marking messages as read: ids=[XX] from=3
[ChatWebSocketService] ✅ Read receipt processed
```

### Expected Logs (Backend - Server)
```
[MessageController] ===== READ RECEIPT RECEIVED =====
[MessageController] Current userId: 3
[MessageController] Other userId: 2
[MessageController] Message IDs to mark as read: 1
[MessageController] ✅ Marked 1 messages as read
[MessageController] ✅ Read receipt broadcasted to user 2
```

### Success Indicator
- ✅ Message shows double tick (✓✓)
- ✅ No "Invalid otherUserId" errors in logs
- ✅ Read receipt processed logs appear

---

## Test Case 2: Typing Indicators

### Steps
1. **User A (Device 1):** Open chat with User B
2. **User B (Device 2):** Open chat with User A
3. **User B:** Start typing message in text field
   - Should send typing indicator
4. **User A:** Look at chat UI below message list
   - Expected: "vamsi is typing..." should appear

### Expected Logs (Frontend - Device B)
```
[ChatWebSocketService] Typing indicator sent: isTyping=true
```

### Expected Logs (Frontend - Device A)
```
[ChatWebSocketService] 📨 _onMessageReceived CALLED
[ChatWebSocketService] ⌨️ FRAME TYPE: TYPING_INDICATOR detected
[ChatWebSocketService] ⌨️ TYPING_INDICATOR received via frame
[ChatWebSocketService] ✅ Typing status updated: user=3 isTyping=true
```

### Expected Logs (UI - Device A)
```
[CHATSTORE] Typing indicator set for user=3: true
```

### Success Indicator
- ✅ "vamsi is typing..." appears in UI
- ✅ Typing frame type detected correctly
- ✅ Auto-clears after 3 seconds of idle

---

## Test Case 3: Message Delivery Speed

### Steps
1. **User A:** Send rapid messages (5 messages in quick succession)
   - Message 1: "Hello"
   - Message 2: "How are you"
   - Message 3: "Let's chat"
   - Message 4: "Real-time test"
   - Message 5: "Final message"

2. **User B:** Observe message arrival
   - Expected: All messages appear within 500ms-1 second

### Expected Behavior
- ✅ All messages delivered in real-time
- ✅ No messages missing
- ✅ Order preserved
- ✅ Each shows single tick immediately

---

## Test Case 4: Edge Cases

### Case 4A: Typing Then Delete
1. **User B:** Start typing
2. **User A:** Sees "typing..." indicator
3. **User B:** Delete all typed text without sending
4. **User A:** Indicator should disappear after ~3 seconds

### Case 4B: Multiple Reads
1. **User A:** Send message
2. **User B:** Close app
3. **User B:** Reopen app and open chat
   - Message should auto-mark as read
4. **User A:** Should see double tick

### Case 4C: Offline Handling
1. **User B:** Send read receipt
2. **User A:** Temporarily lose Wi-Fi connection
3. **User A:** Reconnect to Wi-Fi
   - Should receive queued read receipt
   - Message should update to double tick

---

## Logs to Monitor

### Good Signs ✅
```
[ChatWebSocketService] 💬 FRAME TYPE: REGULAR_MESSAGE detected
[ChatWebSocketService] 📖 FRAME TYPE: READ_RECEIPT detected
[ChatWebSocketService] ⌨️ FRAME TYPE: TYPING_INDICATOR detected
[ChatWebSocketService] ✅ Read receipt processed
[ChatWebSocketService] ✅ Typing status updated
```

### Bad Signs ❌
```
[ChatWebSocketService] ❌ Invalid otherUserId in message
[ChatWebSocketService] ❌ Error processing read receipt
[ChatWebSocketService] ❌ Error processing typing indicator
Message.fromJson: Parse error
```

---

## Debug Commands

### View Active WebSocket Subscriptions
Look for in logs:
```
[ChatWebSocketService] Subscribed to /user/queue/messages
[ChatWebSocketService] Subscribed to /user/queue/typing
```

### Verify ChatStore Updates
```
[CHATSTORE] markMessagesRead applied for otherUserId=X marked=N ids=N
[CHATSTORE] Typing indicator set for user=X: true/false
```

### Check Frame Reception
```
[ChatWebSocketService] Frame body length: XXX bytes
[ChatWebSocketService] Data keys: senderId, recipientId, content, ...
```

---

## Performance Metrics

### Target Performance
- Message delivery: < 500ms
- Read receipt processing: < 100ms
- Typing indicator display: < 200ms
- UI update: < 300ms

### How to Measure
1. Send message and note timestamp
2. Open other device and observe arrival time
3. Check device clock difference if needed
4. Calculate total latency

---

## Rollback Plan (If Issues)

If any issues occur during testing:

1. **Revert changes:**
   ```
   git checkout -- social-media-mobile/lib/src/services/chat_websocket_service.dart
   ```

2. **Rebuild:**
   ```
   flutter clean
   flutter pub get
   flutter run
   ```

3. **Report issues with:**
   - Steps to reproduce
   - Full log output
   - Device/emulator info
   - Message content

---

## Success Criteria

Test passes when:
1. ✅ Read receipts produce double ticks
2. ✅ Typing indicators appear and auto-clear
3. ✅ Messages deliver within 500ms
4. ✅ No "Invalid otherUserId" errors
5. ✅ All frame types detected correctly
6. ✅ Chat scrolls smoothly
7. ✅ No app crashes
8. ✅ State persists after navigation

---

## Common Issues & Solutions

### Issue: Still seeing single tick after long time
**Solution:** 
- Verify Device 2 has opened the chat
- Check if read receipts are enabled in settings
- Restart app on Device 2

### Issue: Typing indicator not appearing
**Solution:**
- Ensure both devices in same chat
- Check Network tab - verify typing indicator sent
- Restart WebSocket connection

### Issue: App crashes on message receive
**Solution:**
- Check error logs for null pointer exceptions
- Verify ChatStore is initialized
- Check if Message model has `isRead` field

### Issue: Messages not appearing on Device B
**Solution:**
- Check if WebSocket connected: "subscribe to /user/queue/messages" in logs
- Verify authorization: "JWT token verified" should appear
- Check network: ping 192.168.31.74:8082

---

## Next Steps After Testing

1. **If all tests pass:** ✅ Deploy to production
2. **If some tests fail:** 🔧 Debug with full logs
3. **Monitor in production:** 📊 Track read receipt success rate

---

## Contact & Support

For issues:
1. Collect full logs from both devices
2. Note exact steps to reproduce
3. Share in development channel with context

---

**Last Updated:** Phase 6 - Frame Type Detection Implementation
**Status:** Ready for Testing ✅
