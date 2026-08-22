# Real-Time Call System - Implementation Guide

## Overview
This document describes the new proper call signaling system that separates Agora media handling from WebSocket signaling.

## Architecture

### Call State Machine
```
IDLE
  ↓
  ├─ [Receive CALL_INVITE] → INCOMING (receiver waits)
  │                            ├─ [Accept] → IN_CALL
  │                            └─ [Reject] → ENDED
  │
  └─ [Initiate Call] → OUTGOING (caller waits)
                         ├─ [Receive CALL_ACCEPT] → IN_CALL
                         ├─ [Receive CALL_REJECT] → ENDED
                         └─ [Timeout 30s] → ENDED

IN_CALL
  ├─ [Receive CALL_END] → ENDED
  └─ [User ends] → ENDED

ENDED
  ├─ UI dismissed
  └─ Reset → IDLE
```

### Components

#### Frontend (Flutter)

**1. `CallSignalingService` (lib/src/services/call_signaling_service_v2.dart)**
- Singleton global service
- Manages call state machine independently of UI
- Listens to WebSocket notifications
- Handles all signaling events
- Methods:
  - `initiateCall()` - Start outgoing call
  - `acceptCall()` - Accept incoming call
  - `rejectCall()` - Reject incoming call
  - `endCall()` - End active call
  - `reset()` - Reset to idle (after UI dismissed)

**2. `CallAPI` (lib/src/services/call_api_v2.dart)**
- Sends WebSocket messages for signaling
- Methods:
  - `sendCallInvite()` - Send CALL_INVITE
  - `sendCallAccept()` - Send CALL_ACCEPT
  - `sendCallReject()` - Send CALL_REJECT
  - `sendCallEnd()` - Send CALL_END

**3. `CallStateManager` (lib/src/state/call_state_manager_v2.dart)**
- Legacy ChangeNotifier wrapper for backward compatibility
- Bridges old UI code with new CallSignalingService
- Manages Agora lifecycle:
  - Initializes Agora ONLY when state = IN_CALL
  - Cleans up Agora ONLY when state = ENDED or IDLE
- No longer handles signaling logic

#### Backend (Spring Boot)

**4. `CallSignalingController` (CallSignalingController.java)**
- Receives WebSocket `/app/call.signal` messages
- Extracts sender and recipient user IDs
- Validates event type
- Forwards events to recipient via `/user/{id}/queue/notifications`
- Logs all signaling events

### Call Flow Examples

#### Caller Initiating Call
```
1. Caller opens calls list, clicks on user
2. UI calls CallSignalingService.initiateCall()
3. CallSignalingService:
   - Sends CALL_INVITE to caller's ID
   - Updates state to OUTGOING
   - Notifies listeners (UI updates to show "Calling...")
4. Backend receives CALL_INVITE on /app/call.signal
5. Backend forwards to receiver via /user/{receiverId}/queue/notifications
6. Receiver's app receives CALL_INVITE notification
7. CallSignalingService on receiver side:
   - Updates state to INCOMING
   - Notifies listeners (UI shows incoming call screen)
8. Receiver accepts call
9. UI calls CallSignalingService.acceptCall()
10. CallSignalingService:
    - Sends CALL_ACCEPT to caller's ID
    - Updates state to IN_CALL
    - Notifies listeners
    - CallStateManager sees state = IN_CALL
    - CallStateManager initializes Agora
11. Backend forwards CALL_ACCEPT to caller
12. Caller's CallSignalingService:
    - Receives CALL_ACCEPT
    - Updates state to IN_CALL
    - Notifies listeners
    - CallStateManager initializes Agora
13. Both users are now in Agora call
14. Either user ends call
15. UI calls CallSignalingService.endCall()
16. CallSignalingService:
    - Sends CALL_END to remote user
    - Updates state to ENDED
    - Notifies listeners
17. Remote user receives CALL_END
18. Remote CallSignalingService:
    - Updates state to ENDED
    - Notifies listeners
19. Both CallStateManagers:
    - See state = ENDED
    - Clean up Agora
    - UI dismisses call screens
20. UI calls CallSignalingService.reset()
21. State returns to IDLE
```

## Migration Steps

### Step 1: Replace CallStateManager
The old `call_state_manager.dart` should be kept for reference but replaced with `call_state_manager_v2.dart`

### Step 2: Add New Services
- Add `call_signaling_service_v2.dart`
- Add `call_api_v2.dart`

### Step 3: Update UI to Use New Services
In screens that initiate calls (like CallsScreen):
```dart
final signalingService = CallSignalingService();
await signalingService.initiateCall(
  toUserId: userId,
  channelId: channelId,
  isVideo: true,
);
```

In screens that accept calls (like IncomingCallScreen):
```dart
final signalingService = CallSignalingService();
await signalingService.acceptCall();
```

In screens that reject calls:
```dart
final signalingService = CallSignalingService();
await signalingService.rejectCall();
```

When ending call (like in CallScreen):
```dart
final signalingService = CallSignalingService();
await signalingService.endCall();
```

### Step 4: Backend Changes
- Add `CallSignalingController.java` to backend
- Remove old call signaling logic from `MessageController.java`
- Ensure WebSocket session has `userId` attribute set on connection

### Step 5: Test Signaling Events
Test both directions:
1. A calls B → B receives invite → B accepts → Both in call
2. A calls B → B receives invite → B rejects → Both return to idle
3. A calls B → B never responds → A timeout after 30s
4. During call → A ends → B receives end event
5. During call → B ends → A receives end event

## Key Differences from Old Implementation

| Aspect | Old | New |
|--------|-----|-----|
| State Management | Scattered across services | Centralized in CallSignalingService |
| WebSocket | Mixed with chat logic | Separate call signaling handler |
| Agora Lifecycle | Started eagerly | Started only when IN_CALL |
| State Machine | Not enforced | Enforced with transitions |
| Bidirectional | Missing (accept/reject not sent back) | Full bidirectional signaling |
| Error Handling | Limited | Comprehensive with logging |

## Logging
All components have detailed logging with `[ServiceName]` prefix:
- `[CallSignalingService]` - State machine logic
- `[CallAPI]` - WebSocket sends
- `[CallStateManager]` - Agora lifecycle
- `[CallSignalingController]` - Backend forwarding

## No UI Changes Required
- IncomingCallScreen remains the same
- CallingLoaderScreen remains the same
- CallScreen remains the same
- Just update the calls from CallStateManager to use new services

## Files Created/Modified

### New Files
- `lib/src/services/call_signaling_service_v2.dart`
- `lib/src/services/call_api_v2.dart`
- `lib/src/state/call_state_manager_v2.dart`
- `backend/.../CallSignalingController.java`

### Modified Files
- Update main.dart if CallStateManager needs new initialization
- Update any screens that initiate/manage calls

### Kept For Reference
- Old `lib/src/services/call_signaling_service.dart`
- Old `lib/src/services/call_api.dart`
- Old `lib/src/state/call_state_manager.dart`

## Next Steps
1. Replace old services with v2 versions
2. Add CallSignalingController to backend
3. Test signaling in both directions
4. Monitor logs for proper state transitions
5. Verify Agora joins only after both users accept
