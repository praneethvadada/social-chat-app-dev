# Quick Rebuild & Test Guide

## Step 1: Rebuild Backend

```powershell
cd "c:\Users\VAMSI KRISHNA\Desktop\PROJECTS\INTERNSHIP\Mobile App Development\backend\social-service"
mvn clean package -DskipTests
```

**Expected Output:** BUILD SUCCESS

**After Build:**
- Stop current social-service if running
- Start updated social-service

```bash
java -jar target/social-service-*.jar
```

## Step 2: Rebuild Flutter (Optional - Changes are Minor)

```powershell
cd "c:\Users\VAMSI KRISHNA\Desktop\PROJECTS\INTERNSHIP\Mobile App Development\social-media-mobile"
flutter clean
flutter pub get
flutter run
```

## Step 3: Test Sequence

### Test 1: Single Device Test (Sender)
1. App running with one user logged in
2. Open chat with another user
3. Send a message
4. **Expected logs:**
   ```
   [SENDER] [ChatWebSocketService] ===== CONFIRMATION RECEIVED =====
   [MessageService] ✅ Marked... messages as read
   ```
5. **NOT Expected:** ClassCastException errors

### Test 2: App Restart Test
1. User logged in and in chat screen
2. Force close app (kill process)
3. Reopen app and navigate back to chat
4. **Expected logs:**
   ```
   [ChatDetailScreen] ✅ WebSocket connected for userId=X
   ```
5. Send new message - should appear in real-time

### Test 3: Two-Device Test
**Device A (User 3 - vamsi):** Tail logs with `flutter logs --device-id <id>`
**Device B (User 2 - sai):** Separate flutter instance or second emulator

**Device A Actions:**
```
1. Open chat with User 2
2. Send message "test1"
3. Wait for response
```

**Device B Actions:**
```
1. Open chat with User 3  
2. Receive message "test1" → logs show [RECEIVER]...
3. Send message "response1"
4. Wait for Device A to show message in real-time
```

**Expected on Device A logs:**
```
[RECEIVER] [ChatWebSocketService] ===== MESSAGE RECEIVED FROM OTHER USER
[ChatStore] ✅ INSERT new message
```

**Expected on Device B logs:**
```
[SENDER] [ChatWebSocketService] ===== CONFIRMATION RECEIVED
```

### Test 4: Read Receipts Test
1. Device A sends message
2. Device B reads it (opens chat)
3. **Expected on Device A:** Message shows double tick ✓✓
4. **Expected on Device B logs:**
   ```
   [MessageService] 📖 Marking... messages as read
   [MessageService] ✅ Marked X messages as read
   ```
5. **Should NOT see:** ClassCastException errors

## Troubleshooting

### Issue: Backend Won't Start
```
Error: Could not find or load main class
```
**Solution:** 
- Verify pom.xml has spring-boot-maven-plugin
- Run: `mvn clean compile`
- Check Maven installed: `mvn -v`

### Issue: WebSocket Connection Timeout
```
[ChatDetailScreen] ❌ WebSocket connection failed: WebSocket connection timeout
```
**Solution:**
- Verify backend is running on port 8082
- Check network connectivity between devices
- Verify JWT token is valid

### Issue: Still Seeing ClassCastException
```
java.lang.ClassCastException: class java.lang.Integer cannot be cast to class java.lang.Long
```
**Solution:**
- Verify MessageController.java was rebuilt with fix
- Run: `mvn clean package` again
- Restart social-service

### Issue: No Receiver Logs
```
[RECEIVER] [ChatWebSocketService] logs not appearing
```
**Solution:**
- Verify WebSocket connect() succeeded
- Check: `[ChatDetailScreen] ✅ WebSocket connected for userId=X`
- Ensure subscription was created: Look for `SUBSCRIBING to /user/queue/messages`
- Check backend logs for message routing: `Processing MESSAGE destination=/user/Y/queue/messages`

## Database Verification (Optional)

```sql
-- Check message read status
SELECT id, sender_id, receiver_id, read_at FROM message WHERE id IN (41, 42, 43, 44) ORDER BY id DESC;

-- Expected: read_at should have recent timestamp for received messages
```

## Logs to Monitor

### On Sender Device
```
[SENDER] [ChatWebSocketService] ===== CONFIRMATION RECEIVED =====
[SENDER] [ChatWebSocketService] ✅ Marked... messages as read
[SENDER] [ChatStore] 📊 Unread count for user=X: Y
```

### On Receiver Device
```
[RECEIVER] [ChatWebSocketService] ===== MESSAGE RECEIVED FROM OTHER USER =====
[RECEIVER] [ChatStore] ✅ INSERT new message
[MessageService] 📖 Marking... messages as read
```

### Backend (All Devices)
```
[MessageController] ===== WEBSOCKET MESSAGE RECEIVED =====
[MessageController] Message IDs to mark as read: X
[MessageService] ✅ Marked X messages as read for user Y
```

## Success Criteria

✅ App restart doesn't lose WebSocket connection
✅ No ClassCastException errors in logs
✅ Messages appear in real-time on receiver
✅ Read receipts update from ✓ to ✓✓
✅ No repeated userId=0 profile fetch errors

