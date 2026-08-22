# Typing Indicator - Frame Reception Debugging

**Issue:** Backend sends typing → Frontend doesn't receive on `/user/queue/typing`

## Changes Made:

### Frontend (Flutter)
1. Added callback wrapper logging to show when typing subscription callback is triggered
2. Added connection state logging (current user ID, STOMP connected status)
3. Set up STOMP error listener to capture frame errors

### Backend (Java)
1. Need to add logging to confirm message is being sent to the correct user

## What to Look For in Logs:

### ✅ Successful Flow:
```
[ChatWebSocketService] 📝 SUBSCRIBING to typing indicators at /user/queue/typing...
[ChatWebSocketService]    ├─ Current User ID: 2
[ChatWebSocketService]    └─ STOMP Connected: true
[ChatWebSocketService] ✅ Subscribed to /user/queue/typing
[ChatWebSocketService]    ├─ Subscription ID: sub-typing-2
[ChatWebSocketService]    ├─ Handler stored: true
[ChatWebSocketService]    └─ Active subscriptions: 3

[ChatWebSocketService] 🚨🚨🚨 TYPING CALLBACK FIRED 🚨🚨🚨
[ChatWebSocketService] 🔔 TYPING FRAME RECEIVED - processing...
[ChatWebSocketService]    ├─ Headers: {...}
[ChatWebSocketService]    └─ Body: {...}
[ChatWebSocketService] ⌨️✅ Typing indicator PROCESSED: user=3 isTyping=true
```

### ❌ Problem Indicators:
1. Subscription logs appear BUT no callback fired → **Frame not reaching subscription**
2. No "TYPING CALLBACK FIRED" in entire log → **Message lost in transit**
3. Connection shows STOMP not connected → **Connection issue**
4. Subscription ID mismatches → **STOMP routing issue**

## Next Steps:

1. **Restart Flutter app** with new logging
2. **Have User 3 type a message**
3. **Share logs focused on**:
   - Connection setup (look for "SUBSCRIING to typing indicators")
   - Typing sent (look for "Typing indicator sent")
   - Backend processing (look for "/app/chat.typing" in server logs)
   - Frontend receiving (look for "TYPING CALLBACK FIRED")

## Backend Addition (Recommended):

Add detailed logging in `MessageController.handleTypingViaWebSocket()`:

```java
@MessageMapping("/chat.typing")
public void handleTypingViaWebSocket(@Payload TypingRequest request,
                                     SimpMessageHeaderAccessor headerAccessor) {
    try {
        // ... existing code ...
        
        Long userId = Long.parseLong(userIdObj.toString());
        if (userId != null && request.getReceiverId() != null) {
            // ... build payload ...
            
            System.out.println("[MessageController] 🔔 TYPING SEND DEBUG");
            System.out.println("[MessageController]    ├─ From: " + userId);
            System.out.println("[MessageController]    ├─ To: " + request.getReceiverId());
            System.out.println("[MessageController]    ├─ Destination: /user/" + request.getReceiverId() + "/queue/typing");
            System.out.println("[MessageController]    └─ Payload: " + payload);
            
            messagingTemplate.convertAndSendToUser(
                request.getReceiverId().toString(), 
                "/queue/typing", 
                payload
            );
            
            System.out.println("[MessageController] ✅ TYPING MESSAGE SENT");
        }
    } catch (Exception e) {
        System.out.println("[MessageController] ❌ TYPING ERROR: " + e.getMessage());
        e.printStackTrace();
    }
}
```

## Critical Questions:

1. Does subscription establish successfully? (check for "✅ Subscribed to /user/queue/typing")
2. Is connection maintained? (check STOMP Connected: true)
3. Does backend send? (check server logs for "/app/chat.typing" and convertAndSendToUser)
4. Does frame arrive at frontend? (check for "TYPING CALLBACK FIRED")

If #3 succeeds but #4 fails → **STOMP routing issue between backend and frontend**
If #2 is false → **Connection dropped before receiving**
If #1 is false → **Subscription registration failed**
