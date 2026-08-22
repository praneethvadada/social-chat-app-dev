# Call Signaling Controller Analysis

## Overview
The `CallSignalingController` handles WebSocket-based call signaling events for voice/video calls in the social media application. It routes call signaling messages (CALL_INVITE, CALL_ACCEPT, CALL_REJECT, CALL_END) between users via STOMP WebSocket protocol.

---

## 1. Message Flow & Event Handling

### Message Flow Architecture
```
Caller App → WebSocket → /app/call.signal → CallSignalingController 
                                           → SimpMessagingTemplate
                                           → /user/{recipientId}/queue/notifications
                                           → Receiver App
```

### Event Types Handled
| Event Type | Direction | Purpose |
|-----------|-----------|---------|
| `CALL_INVITE` | Caller → Receiver | Initiate call request |
| `CALL_ACCEPT` | Receiver → Caller | Accept incoming call |
| `CALL_REJECT` | Receiver → Caller | Reject incoming call |
| `CALL_END` | Either → Other | End active call |

### Handler Method
**Endpoint:** `/app/call.signal`  
**Method:** `handleCallSignal()`  
**Location:** [CallSignalingController.java](backend/social-service/src/main/java/com/socialmedia/social/controller/CallSignalingController.java)

---

## 2. Message Payload Structure

### Incoming Message Format (Client → Backend)
```java
{
  "type": "CALL_INVITE",  // or CALL_ACCEPT, CALL_REJECT, CALL_END
  "toUserId": 2,          // recipient user ID
  "payload": {
    "calleeId": 2,
    "channelId": "channel_123",
    "isVideo": true,
    "offerSdp": "v=0\r\no=...",  // for CALL_INVITE
    "answerSdp": "v=0\r\no=..."   // for CALL_ACCEPT
  }
}
```

### Outgoing Message Format (Backend → Client)
```java
{
  "type": "CALL_INVITE",
  "payload": {
    "fromUserId": 1,       // sender ID (added by backend)
    "type": "CALL_INVITE",
    "toUserId": 2,
    "calleeId": 2,
    "channelId": "channel_123",
    "isVideo": true,
    "offerSdp": "v=0\r\no=..."
  }
}
```

**Destination:** `/user/{recipientId}/queue/notifications`

---

## 3. Message Routing Implementation

### Queue Naming Convention
- **Format:** `/user/{userId}/queue/notifications`
- **Routing Method:** `convertAndSendToUser()`
- **Configured in:** [WebSocketConfig.java](backend/social-service/src/main/java/com/socialmedia/social/config/WebSocketConfig.java)

### Message Routing Logic (Lines 33-93)
```java
// Step 1: Extract sender from session
Long senderUserId = extractUserIdFromSession(headerAccessor);

// Step 2: Extract event type
String eventType = (String) message.get("type");

// Step 3: Extract recipient from message
Long recipientUserId = extractRecipientUserId(message);

// Step 4: Prepare payload with sender info
payload.put("fromUserId", senderUserId);
payload.put("type", eventType);

// Step 5: Forward to recipient's queue
messagingTemplate.convertAndSendToUser(
    recipientUserId.toString(),
    "/queue/notifications",
    response
);
```

### Recipient ID Extraction (Lines 127-156)
The controller checks two locations for recipient ID (in priority order):

1. **Direct field:** `toUserId` in root message
2. **Nested field:** `payload.toUserId` 

```java
// Try direct toUserId field
Object toUserIdObj = message.get("toUserId");

// Try from payload
Object payloadObj = message.get("payload");
if (payloadObj instanceof Map) {
    Map<String, Object> payload = (Map<String, Object>) payloadObj;
    Object toUserIdPayload = payload.get("toUserId");
}
```

---

## 4. User Authentication & Authorization

### Authentication Flow
**Location:** [WebSocketSecurityInterceptor.java](backend/social-service/src/main/java/com/socialmedia/social/config/WebSocketSecurityInterceptor.java)

#### Step 1: WebSocket Connection (CONNECT Command)
```java
if (StompCommand.CONNECT.equals(accessor.getCommand())) {
    List<String> authHeaders = accessor.getNativeHeader("Authorization");
    String token = authHeader.substring(7); // Remove "Bearer "
    
    if (jwtTokenProvider.validateToken(token)) {
        Long userId = jwtTokenProvider.getUserIdFromToken(token);
        accessor.getSessionAttributes().put("userId", userId);
    }
}
```

#### Step 2: Session Validation in CallSignalingController
```java
Long senderUserId = extractUserIdFromSession(headerAccessor);
if (senderUserId == null) {
    logError("handleCallSignal", "Sender userId not found in session");
    return;
}
```

### Current Authentication Details
- **Token Type:** JWT
- **Header:** `Authorization: Bearer <token>`
- **Validation:** Done during WebSocket CONNECT
- **Storage:** Session attributes (not per-message)
- **Expiration:** 24 hours (access token)

---

## 5. Security Analysis

### ✅ What's Implemented
1. **JWT Token Validation** - Tokens validated on WebSocket connection
2. **User ID Extraction** - User ID extracted from JWT and stored in session
3. **Session-based Auth** - User authenticated before receiving messages
4. **Event Type Validation** - Only valid event types accepted
5. **Null Safety Checks** - Null checks for all extracted fields

### ❌ Critical Issues & Vulnerabilities

#### **Issue #1: No Per-Message Authorization** 🔴 CRITICAL
**Problem:** Only WebSocket connection is authenticated, not individual messages.

**Risk:** A malicious user could:
- Connect with their own token (valid)
- Send forged messages impersonating other users
- Hijack conversations/calls

**Example Attack:**
```
User A connects with token → authenticated ✓
User A sends: toUserId=3, type=CALL_INVITE  
- Backend trusts session userId from CONNECT
- But USER A is impersonating USER B by manipulating the message
```

**Code Vulnerable Section:**
```java
// Line 39-44: Session auth happens ONCE during CONNECT
Long senderUserId = extractUserIdFromSession(headerAccessor);

// Line 99-106: Uses this senderUserId for ALL messages without re-validation
payload.put("fromUserId", senderUserId);
messagingTemplate.convertAndSendToUser(
    recipientUserId.toString(),
    "/queue/notifications",
    response
);
```

---

#### **Issue #2: No Blocking Check** 🔴 CRITICAL
**Problem:** No verification that caller & receiver haven't blocked each other.

**Risk:** 
- Blocked users can still send call invites
- Violates privacy/security expectations
- Receiver receives notifications they explicitly tried to prevent

**Evidence:**
- `BlockService.java` has `isEitherBlocked()` method
- `PostService.java` and `UserProfileService.java` use blocking checks
- `CallSignalingController.java` **does NOT use it**

**Example:**
```
User A blocks User B
User B connects (valid token)
User B sends CALL_INVITE to User A
User A still receives the invite ❌
```

---

#### **Issue #3: No Recipient Existence Validation** 🟡 MEDIUM
**Problem:** No check if recipient user exists or is active.

**Risk:**
- Messages routed to non-existent users silently fail
- No error feedback to caller
- Can't distinguish between "user offline" vs "user invalid"

**Current Code:**
```java
// Line 88-96: Blindly routes without validation
messagingTemplate.convertAndSendToUser(
    recipientUserId.toString(),
    "/queue/notifications",
    response
);
// No validation that recipientUserId exists!
```

---

#### **Issue #4: Session Hijacking Risk** 🟡 MEDIUM
**Problem:** Session attributes never updated after CONNECT; no token refresh.

**Risk:**
- If token expires, session still active
- No way to re-authenticate during long-lived connection
- Tokens aren't validated per-message

**Current Limitations:**
```java
// WebSocketSecurityInterceptor.java - Only runs on CONNECT
if (StompCommand.CONNECT.equals(accessor.getCommand())) {
    // Auth happens here once
}
// No re-validation on SUBSCRIBE, SEND, or other commands
```

---

#### **Issue #5: Weak Recipient ID Extraction** 🟡 MEDIUM
**Problem:** Accepts `toUserId` from either root or nested payload without validation.

**Risk:**
- Inconsistent message structure accepted
- Could confuse message routing
- No canonical message format enforced

---

#### **Issue #6: No Rate Limiting** 🟡 MEDIUM
**Problem:** No limits on message frequency.

**Risk:**
- User could spam call invites to recipients
- DDoS-like attack via WebSocket messages
- No protection against call spam

---

#### **Issue #7: Inadequate Logging** 🟡 MEDIUM
**Problem:** Using `System.out.println()` instead of proper logging.

**Risk:**
- Logs not persisted reliably
- Can't audit call attempts
- Security incidents not tracked
- Production debugging difficult

**Current:**
```java
System.out.println("[CallSignalingController] Event: " + eventType);
```

**Should Be:**
```java
log.info("[CallSignaling] Event: {} | From: {} | To: {}", eventType, senderUserId, recipientId);
```

---

## 6. Integration Points

### WebSocket Configuration
**File:** [WebSocketConfig.java](backend/social-service/src/main/java/com/socialmedia/social/config/WebSocketConfig.java)

```java
@Override
public void configureMessageBroker(MessageBrokerRegistry config) {
    config.enableSimpleBroker("/topic", "/queue", "/user");
    config.setApplicationDestinationPrefixes("/app");
    config.setUserDestinationPrefix("/user");
}

@Override
public void registerStompEndpoints(StompEndpointRegistry registry) {
    registry.addEndpoint("/ws")
            .setAllowedOriginPatterns("*")
            .withSockJS();
}
```

### Security Interceptor Registration
```java
@Override
public void configureClientInboundChannel(ChannelRegistration registration) {
    registration.interceptors(webSocketSecurityInterceptor);
}
```

### Mobile Client Integration
**Files:**
- [ChatWebSocketService.dart](social-media-mobile/lib/src/services/chat_websocket_service.dart#L608-L630)
- [CallSignalingService.dart](social-media-mobile/lib/src/services/call_signaling_service_v2.dart)

**Client sends:**
```dart
final body = <String, dynamic>{'type': type, 'payload': payload};
_stompClient.send(
    destination: '/app/call.signal',
    body: json.encode(body),
);
```

### Related Services
- **BlockService.java** - Has blocking logic but not used
- **CallLogRepository.java** - Stores call history
- **CallLog.java** - Entity for call records
- **NotificationService.java** - Similar messaging pattern for notifications

---

## 7. Payload Structure Issues

### Problem: Redundant Event Type
**Current:**
```java
payload.put("type", eventType);          // Line 70
response.put("type", eventType);         // Line 80
```

**Issue:** Type appears twice in output message, redundant.

### Problem: Map Mutation
**Current:**
```java
Map<String, Object> payload = (Map<String, Object>) message.getOrDefault("payload", new java.util.HashMap<>());
if (payload instanceof java.util.HashMap) {
    payload = new java.util.HashMap<>(payload);  // Defensive copy
}
payload.put("fromUserId", senderUserId);  // Mutates original data
```

**Issue:** Creates copy but mutation may not be necessary.

---

## 8. Recommended Fixes

### Priority 1: Critical Security (Do First)
```java
// 1. Add blocking check before routing
private void validateRecipientAcceptance(Long senderId, Long recipientId) {
    if (blockService.isEitherBlocked(senderId, recipientId)) {
        throw new SecurityException("Recipient blocked");
    }
}

// 2. Verify recipient exists
private void validateRecipientExists(Long recipientId) {
    if (!userService.userExists(recipientId)) {
        throw new UserNotFoundException("Recipient not found");
    }
}

// 3. Use proper logging
private static final Logger log = LoggerFactory.getLogger(CallSignalingController.class);
```

### Priority 2: Message Validation
```java
// Enforce canonical message structure
private static final Set<String> VALID_EVENTS = Set.of(
    "CALL_INVITE", "CALL_ACCEPT", "CALL_REJECT", "CALL_END"
);

// Single location for recipient extraction
private Long getRecipientId(Map<String, Object> message) {
    Object toUserId = message.get("toUserId");
    if (toUserId == null) {
        throw new IllegalArgumentException("Missing toUserId");
    }
    return toLong(toUserId);
}
```

### Priority 3: Rate Limiting
```java
// Add rate limiter
private final RateLimiter rateLimiter = 
    RateLimiter.create(/* max calls per minute */);

if (!rateLimiter.tryAcquire(senderUserId)) {
    logError("handleCallSignal", "Rate limit exceeded for user " + senderUserId);
    return;
}
```

### Priority 4: Improved Logging
```java
log.info(
    "[CallSignal] Event: {} | From: {} | To: {} | Status: OK",
    eventType, senderUserId, recipientUserId
);
```

---

## 9. Data Model

### CallLog Entity
**File:** [CallLog.java](backend/social-service/src/main/java/com/socialmedia/social/entity/CallLog.java)

```java
@Entity
@Table(name = "call_logs")
public class CallLog {
    @Id
    private Long id;
    
    private Long initiatorId;    // Who started the call
    private Long callerId;       // Calling party
    private Long calleeId;       // Receiving party
    private String type;         // "audio" | "video"
    private String status;       // "started" | "ended"
    private String channel;      // Agora channel name
    private Long duration;       // Duration in seconds
    private String recordingUrl;
    private Instant createdAt;
}
```

**Status:** Entity exists but **not used** by CallSignalingController

---

## 10. Missing Features

1. **Call State Validation** - No state machine to prevent invalid transitions
   - Should reject CALL_ACCEPT without prior CALL_INVITE
   - Should reject multiple CALL_INVITE while already in call

2. **Call Logging** - No persistence of call attempts
   - Can't audit who called whom and when
   - No record of rejected calls

3. **Timeout Handling** - No call expiration
   - Unreceived calls don't auto-expire
   - Recipients not notified if caller disconnects

4. **Presence Awareness** - No check if recipient is online
   - Messages sent to offline users silently fail
   - No notification if user comes online

5. **Error Feedback** - No way to notify caller of failures
   - Blocked user: caller doesn't know why call failed
   - Non-existent user: no error response

---

## Summary Table

| Aspect | Status | Issues |
|--------|--------|--------|
| Authentication | ✅ Implemented | No per-message validation |
| Authorization | ❌ Missing | No blocking checks |
| Message Routing | ✅ Working | Weak recipient validation |
| Payload Structure | ⚠️ Loose | Accepts multiple formats |
| Rate Limiting | ❌ Missing | Can spam invites |
| Logging | ⚠️ Weak | Using println, not persisted |
| State Machine | ❌ Missing | No call state tracking |
| Error Handling | ⚠️ Basic | Limited error feedback |
| Security | 🔴 CRITICAL | 7 issues identified |

---

## Code Locations Quick Reference

| Component | File | Lines |
|-----------|------|-------|
| Call Handler | [CallSignalingController.java](backend/social-service/src/main/java/com/socialmedia/social/controller/CallSignalingController.java) | 33-96 |
| Auth Interceptor | [WebSocketSecurityInterceptor.java](backend/social-service/src/main/java/com/socialmedia/social/config/WebSocketSecurityInterceptor.java) | 23-62 |
| WS Config | [WebSocketConfig.java](backend/social-service/src/main/java/com/socialmedia/social/config/WebSocketConfig.java) | 18-35 |
| Block Service | [BlockService.java](backend/social-service/src/main/java/com/socialmedia/social/service/BlockService.java) | 53-60 |
| Client Send | [ChatWebSocketService.dart](social-media-mobile/lib/src/services/chat_websocket_service.dart) | 608-630 |
| Client Receive | [CallSignalingService.dart](social-media-mobile/lib/src/services/call_signaling_service_v2.dart) | 23-110 |

