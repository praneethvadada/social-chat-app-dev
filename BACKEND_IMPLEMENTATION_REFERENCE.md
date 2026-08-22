# Backend Implementation Reference

## Files Modified

### 1. MessageController.java
**Location:** `backend/social-service/src/main/java/com/socialmedia/social/controller/MessageController.java`

**New Method Added:**
```java
@MessageMapping("/chat.read")
public void handleReadReceiptViaWebSocket(
        @Payload java.util.Map<String, Object> payload,
        SimpMessageHeaderAccessor headerAccessor)
```

**What It Does:**
- Receives read receipt from Flutter app
- Extracts userId from WebSocket session
- Marks messages as read in database
- Broadcasts read receipt back to original sender

**Message Format (from Flutter):**
```json
{
  "messageIds": [1, 2, 5, 7, 11, 12, 14],
  "otherUserId": 3
}
```

**Broadcast Response (to Sender):**
```json
{
  "type": "read_receipt",
  "fromUserId": 3,
  "toUserId": 2,
  "messageIds": [1, 2, 5, 7, 11, 12, 14],
  "timestamp": "2026-01-08T07:20:36.593Z"
}
```

---

### 2. MessageService.java
**Location:** `backend/social-service/src/main/java/com/socialmedia/social/service/MessageService.java`

**New Method Added:**
```java
@Transactional
public void markMessagesAsRead(List<Long> messageIds, Long readBy)
```

**What It Does:**
- Takes list of message IDs and user ID
- Fetches messages from database
- Verifies current user is the receiver
- Sets `readAt` timestamp
- Saves to database

**Logic:**
```
For each messageId:
  If message.receiverId == readBy AND message.readAt == null:
    message.readAt = LocalDateTime.now()
    save()
```

**Database Impact:**
- Updates `messages.readAt` timestamp
- Only for messages where `receiverId = readBy`
- Only if `readAt` is currently NULL

---

## WebSocket Message Flow

### Sending Message
```
Flutter App                    Backend                        Other Device
    |                            |                                |
    |-- /app/chat.send -------> MessageController               |
    |                       (sendMessageViaWebSocket)           |
    |                            |                               |
    |                       MessageService.send()               |
    |                            |                               |
    |                       Save to DB                          |
    |                            |                               |
    |                       Send to /user/3/queue/messages ----> |
    |                       (via messagingTemplate)             |
    |                            |                       Receive & parse
    |                            |                       Update UI
    |                            |                               |
```

### Reading Message (NEW)
```
Flutter App                    Backend                        Other Device
    |                            |                                |
    |-- /app/chat.read -------> MessageController               |
    |                       (handleReadReceiptViaWebSocket)     |
    |                            |                               |
    |                       MessageService.markMessagesAsRead() |
    |                            |                               |
    |                       Update readAt timestamp             |
    |                            |                               |
    |                       Send to /user/2/queue/messages ----> |
    |                       (via messagingTemplate)             |
    |                            |                       Receive & parse
    |                            |                       Update UI (✓ read)
    |                            |                               |
```

### Typing Indicator
```
Flutter App                    Backend                        Other Device
    |                            |                                |
    |-- /app/chat.typing ----> MessageController               |
    |                       (handleTypingViaWebSocket)          |
    |                            |                               |
    |                       Send to /user/3/queue/typing ----> |
    |                       (via messagingTemplate)             |
    |                            |                       Receive & parse
    |                            |                       Show "is typing..."
    |                            |                               |
```

---

## Database Schema (Messages Table)

```sql
CREATE TABLE messages (
    id BIGINT PRIMARY KEY,
    sender_id BIGINT NOT NULL,
    receiver_id BIGINT NOT NULL,
    content VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    read_at TIMESTAMP NULL,  -- ← This is set by markMessagesAsRead()
    client_message_id VARCHAR(100) UNIQUE,
    status VARCHAR(20),
    deleted_for_initiator BOOLEAN DEFAULT FALSE,
    deleted_for_receiver BOOLEAN DEFAULT FALSE
);
```

**Key Column:** `read_at`
- NULL = Message not read
- Has timestamp = Message read at that time

---

## Configuration (WebSocketConfig.java)

```java
@Configuration
@EnableWebSocketMessageBroker
public class WebSocketConfig implements WebSocketMessageBrokerConfigurer {
    
    @Override
    public void registerStompEndpoints(StompEndpointRegistry registry) {
        // WebSocket endpoint: ws://host:port/ws
        registry.addEndpoint("/ws").setAllowedOrigins("*");
    }

    @Override
    public void configureMessageBroker(MessageBrokerRegistry registry) {
        // Broker destinations
        registry.enableSimpleBroker("/topic", "/queue", "/user");
        
        // Application destinations
        registry.setApplicationDestinationPrefixes("/app");
    }
}
```

**Destinations:**
- `/app/*` → Message handling methods
- `/topic/*` → Broadcast to all subscribers
- `/queue/*` → Private message queues
- `/user/{id}/*` → Private user queues

---

## Testing the Implementation

### 1. Start Backend
```bash
cd backend/social-service
mvn spring-boot:run
```

### 2. Check WebSocket Connection
```bash
# In browser console (Chrome DevTools)
var ws = new WebSocket('ws://localhost:8082/ws');
```

### 3. Send Test Message
```
STOMP command to /app/chat.send with payload:
{
  "clientMessageId": "2_1767856856675_533903",
  "content": "Hello",
  "receiverId": 3
}
```

### 4. Verify Backend Handler
```bash
# Backend should log:
[MessageController] ===== WEBSOCKET MESSAGE RECEIVED =====
[MessageController] Request receiverId: 3
[MessageController] Request content: Hello
```

### 5. Send Read Receipt
```
STOMP command to /app/chat.read with payload:
{
  "messageIds": [1, 2, 3, 4, 5],
  "otherUserId": 2
}
```

### 6. Verify Read Receipt Handler
```bash
# Backend should log:
[MessageController] ===== READ RECEIPT RECEIVED =====
[MessageController] Marked 5 messages as read
[MessageController] ✅ Read receipt broadcasted to user 2
```

---

## Debugging Guide

### Issue: Read receipts not working
**Check:**
1. Is `/app/chat.read` handler registered?
   ```bash
   grep -r "handleReadReceiptViaWebSocket" backend/
   ```
2. Are messageIds coming through?
   ```bash
   # Look for backend log: [MessageController] Message IDs to mark as read: X
   ```
3. Is database updating?
   ```sql
   SELECT * FROM messages WHERE id IN (1,2,3,4,5) AND readAt IS NOT NULL;
   ```

### Issue: Read receipts not received by sender
**Check:**
1. Is read receipt being broadcasted?
   ```bash
   # Backend log should show: ✅ Read receipt broadcasted to user X
   ```
2. Is Flutter app subscribed to /user/{id}/queue/messages?
   ```bash
   # Flutter log: [ChatWebSocketService] Subscribed to /user/2/queue/messages
   ```
3. Is payload format correct?
   ```json
   {
     "type": "read_receipt",
     "messageIds": [...],
     "timestamp": "..."
   }
   ```

---

## Performance Notes

- **Message Limit:** Currently 500 messages per conversation (SharedPreferences)
- **Read Receipt Batch:** All marked messages sent in single operation
- **Database Query:** Optimized with indexed lookups on receiverId and messageIds
- **WebSocket Broadcast:** Uses STOMP convertAndSendToUser for targeted delivery

---

**Status:** ✅ READY FOR PRODUCTION  
**Date:** January 8, 2026  
**Version:** 1.0
