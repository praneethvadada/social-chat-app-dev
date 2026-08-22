# Real-Time Chat Testing Checklist

## Pre-Deployment Testing

- [ ] Database migration SQL verified
- [ ] All 9 files have been modified/created
- [ ] Backend code compiles without errors
- [ ] No import errors in new Java files
- [ ] Mobile code compiles without errors
- [ ] Flutter dependencies updated (`flutter pub get`)

---

## Post-Deployment Testing

### Phase 1: Server Health (5 minutes)

- [ ] Backend service started successfully
- [ ] No startup errors in logs
- [ ] Database connection confirmed
- [ ] WebSocket endpoint `/ws` is accessible
- [ ] API Gateway routes messages correctly

### Phase 2: Database Verification (5 minutes)

```bash
# Run these SQL queries and verify results
mysql -u root -p social_media_db
```

- [ ] `SELECT * FROM users LIMIT 1;` - Shows `is_online` and `last_seen_at` columns
- [ ] `UPDATE users SET is_online=false WHERE 1=1;` - Reset all users to offline
- [ ] `SELECT COUNT(*) FROM users WHERE is_online=true;` - Should return 0

### Phase 3: Single Device Test (10 minutes)

**Setup**: One Android device or emulator

- [ ] App installs without errors
- [ ] Login successful
- [ ] Navigate to Chats screen
- [ ] Check backend logs for: `[WS] User [ID] connected`
- [ ] Check backend logs for: `[WS] Subscribed to /user/queue/messages`
- [ ] Send a message to yourself (if available)
  - [ ] Message appears instantly
  - [ ] Timestamp shows "now" (not "5h")
- [ ] Query database: `SELECT isOnline FROM users WHERE userId=[your_id];` - Should return 1 (true)
- [ ] Close app (kill process, not background)
- [ ] Wait 30 seconds
- [ ] Query database: `SELECT isOnline FROM users WHERE userId=[your_id];` - Should return 0 (false)

### Phase 4: Two-Device Real-Time Test (15 minutes)

**Setup**: Device A and Device B (different users)

#### Test A: Message Delivery
1. [ ] Login on Device A (User A) - Chat open
2. [ ] Login on Device B (User B) - Chat open
3. [ ] On Device B, create new chat with User A
4. [ ] Send message from Device B: "Test message 1"
5. **CRITICAL**: On Device A, check if message appears WITHIN 2 SECONDS
   - [ ] YES - Message arrived
   - [ ] NO - Message did NOT arrive (FAILURE - check logs)
6. [ ] Verify message shows correct sender name and profile picture
7. [ ] Verify timestamp shows "now" (NOT hours)
8. [ ] Send message from Device A: "Test message 2"
9. **CRITICAL**: On Device B, check if message appears WITHIN 2 SECONDS
   - [ ] YES - Message arrived
   - [ ] NO - Message did NOT arrive (FAILURE - check logs)
````markdown
# Real-Time Chat Testing Checklist

## Pre-Deployment Testing

- [ ] Database migration SQL verified
- [ ] All 9 files have been modified/created
- [ ] Backend code compiles without errors
- [ ] No import errors in new Java files
- [ ] Mobile code compiles without errors
- [ ] Flutter dependencies updated (`flutter pub get`)

---

## Post-Deployment Testing

### Phase 1: Server Health (5 minutes)

- [ ] Backend service started successfully
- [ ] No startup errors in logs
- [ ] Database connection confirmed
- [ ] WebSocket endpoint `/ws` is accessible
- [ ] API Gateway routes messages correctly

### Phase 2: Database Verification (5 minutes)

```bash
# Run these SQL queries and verify results
mysql -u root -p social_media_db
```

- [ ] `SELECT * FROM users LIMIT 1;` - Shows `is_online` and `last_seen_at` columns
- [ ] `UPDATE users SET is_online=false WHERE 1=1;` - Reset all users to offline
- [ ] `SELECT COUNT(*) FROM users WHERE is_online=true;` - Should return 0

### Phase 3: Single Device Test (10 minutes)

**Setup**: One Android device or emulator

- [ ] App installs without errors
- [ ] Login successful
- [ ] Navigate to Chats screen
- [ ] Check backend logs for: `[WS] User [ID] connected`
- [ ] Check backend logs for: `[WS] Subscribed to /user/queue/messages`
- [ ] Send a message to yourself (if available)
  - [ ] Message appears instantly
  - [ ] Timestamp shows "now" (not "5h")
- [ ] Query database: `SELECT isOnline FROM users WHERE userId=[your_id];` - Should return 1 (true)
- [ ] Close app (kill process, not background)
- [ ] Wait 30 seconds
- [ ] Query database: `SELECT isOnline FROM users WHERE userId=[your_id];` - Should return 0 (false)

### Phase 4: Two-Device Real-Time Test (15 minutes)

**Setup**: Device A and Device B (different users)

#### Test A: Message Delivery
1. [ ] Login on Device A (User A) - Chat open
2. [ ] Login on Device B (User B) - Chat open
3. [ ] On Device B, create new chat with User A
4. [ ] Send message from Device B: "Test message 1"
5. **CRITICAL**: On Device A, check if message appears WITHIN 2 SECONDS
   - [ ] YES - Message arrived
   - [ ] NO - Message did NOT arrive (FAILURE - check logs)
6. [ ] Verify message shows correct sender name and profile picture
7. [ ] Verify timestamp shows "now" (NOT hours)
8. [ ] Send message from Device A: "Test message 2"
9. **CRITICAL**: On Device B, check if message appears WITHIN 2 SECONDS
   - [ ] YES - Message arrived
   - [ ] NO - Message did NOT arrive (FAILURE - check logs)

#### Test B: Online Status
1. [ ] Device A shows Device B status as "Online" in chat header
2. [ ] Device B shows Device A status as "Online" in chat header
3. [ ] Close app on Device A (kill process completely)
4. [ ] Wait 30 seconds
5. [ ] On Device B, refresh conversations or reopen chat
   - [ ] Device A status shows "Offline"
   - [ ] [ ] Database shows: `SELECT isOnline FROM users WHERE userId=[A_id];` returns 0
6. [ ] Reopen app on Device A
7. [ ] Within 2 seconds:
   - [ ] Device B shows Device A as "Online"
   - [ ] Database shows: `SELECT isOnline FROM users WHERE userId=[A_id];` returns 1

#### Test C: Multiple Messages
1. [ ] Device A sends 5 messages rapidly
2. [ ] On Device B, all 5 messages appear within 5 seconds total
3. [ ] Each message shows correct order
4. [ ] Each message has correct timestamp (all show "now")

### Phase 5: Three-Device Test (10 minutes)

**Setup**: Device A, B, C (3 different users)

- [ ] Device A sends to Device B - Device B receives instantly
- [ ] Device B sends to Device C - Device C receives instantly
- [ ] Device C sends to Device A - Device A receives instantly
- [ ] All three show each other as "Online"
- [ ] Close Device B app
- [ ] Device A and C show Device B as "Offline"

### Phase 6: Load Test (Optional - 5 minutes)

**Setup**: Send many messages in quick succession

- [ ] Device A sends 20 messages within 10 seconds
- [ ] Device B receives all 20 messages within 15 seconds
- [ ] No messages lost
- [ ] Messages in correct order

### Phase 7: Edge Cases (10 minutes)

#### Timeout Test
- [ ] Device A closes app (should disconnect within 1 minute)
- [ ] Device B shows Device A as "Offline" within 1 minute
- [ ] After 1 hour of app being open, WebSocket session still works

#### Network Interruption Test (if applicable)
- [ ] Toggle WiFi/data on Device A while in chat
- [ ] WebSocket reconnects automatically
- [ ] Messages resume delivery

#### Large Message Test
- [ ] Send 500 character message
- [ ] Send message with emoji
- [ ] Send message with URL
- [ ] All display correctly

---

## Log Analysis

### What to Look For in Backend Logs

#### SUCCESS Indicators:
```
[WS] User 123 connected
[WS] Subscribed to /user/queue/messages
[MessageService] Message sent to /user/456/queue/messages
[WebSocketEventListener] User 123 connected
```

#### FAILURE Indicators:
```
[JWT FILTER] Token validation failed
[WS] Error parsing message
[MessageService] Error sending via WebSocket
[WebSocketEventListener] Error handling
NumberFormatException
NullPointerException
```

### Commands to Monitor Logs

```bash
# Real-time monitoring
tail -f /var/log/tomcat/catalina.out

# Filter for WebSocket events
grep -i "websocket\|connected\|disconnected" /var/log/tomcat/catalina.out

# Filter for message events
grep -i "message sent\|message received" /var/log/tomcat/catalina.out

# Count connections
grep -c "\[WS\] User .* connected" /var/log/tomcat/catalina.out

# Look for errors
grep -i "error\|exception" /var/log/tomcat/catalina.out | tail -20
```

---

## Database Queries for Verification

```sql
-- Check online users
SELECT userId, username, isOnline, lastSeenAt FROM users;

-- Check specific user
SELECT userId, username, isOnline, lastSeenAt FROM users WHERE userId = 123;

-- Count online users
SELECT COUNT(*) as online_count FROM users WHERE isOnline = true;

-- Check recent activity
SELECT userId, username, lastSeenAt FROM users ORDER BY lastSeenAt DESC LIMIT 5;

-- Messages between two users
SELECT id, senderId, receiverId, content, createdAt, isRead FROM messages 
WHERE (senderId = 123 AND receiverId = 456) 
   OR (senderId = 456 AND receiverId = 123)
ORDER BY createdAt DESC LIMIT 10;
```

---

## Common Issues & Fixes

### Issue: Messages Not Arriving

**Symptom**: Send message, nothing appears on other device

**Diagnosis**:
1. Check backend logs for: `Error sending via WebSocket`
2. Check if userId extraction failed
3. Check if WebSocket subscription failed

**Fix**:
```bash
# 1. Restart backend
systemctl restart social-service

# 2. Check database
mysql -u root -p social_media_db
> SELECT isOnline FROM users WHERE userId = 456;  # Should be 1

# 3. Check if token is valid
# Look for: [JWT FILTER] Token valid

# 4. Rebuild mobile app
flutter clean && flutter pub get && flutter run
```

### Issue: Timestamp Shows Wrong Time

**Symptom**: Messages show "5h" or incorrect hours

**Diagnosis**:
1. Check server time: `date`
2. Check MySQL time: `SELECT NOW();`
3. Check client time on device

**Fix**:
```bash
# Sync server time
sudo ntpdate -s time.nist.gov

# Restart backend
systemctl restart social-service

# Restart mobile app
```

### Issue: User Shows Offline When Online

**Symptom**: Device A is open and using chat, but Device B shows offline

**Diagnosis**:
1. Check WebSocket event listener logs
2. Check if online status update is failing
3. Check database permissions

**Fix**:
```bash
# 1. Check logs for event listener
grep "WebSocketEventListener" /var/log/tomcat/catalina.out

# 2. Restart service
systemctl restart social-service

# 3. Manually update and test
mysql -u root -p social_media_db
> UPDATE users SET isOnline = true WHERE userId = 123;
> SELECT isOnline FROM users WHERE userId = 123;
```

---

## Sign-Off Checklist

Once all tests pass, confirm:

- [ ] All 7 test phases completed successfully
- [ ] No critical errors in backend logs
- [ ] Database shows correct online/offline status
- [ ] Messages deliver in under 2 seconds
- [ ] Timestamps show correct time
- [ ] Multi-device sync works correctly
- [ ] No memory leaks or connection issues
- [ ] Ready for production deployment

---

## Rollback Decision Tree

If tests FAIL:

1. **Messages not arriving?**
   - Check WebSocket logs
   - Check userId extraction
   - Rollback WebSocketSecurityInterceptor
   - Rollback MessageService changes

2. **Online status not working?**
   - Check WebSocketEventListener logs
   - Rollback database changes
   - Rollback UserProfile entity

3. **Timestamp still wrong?**
   - Rollback message.dart changes
````
