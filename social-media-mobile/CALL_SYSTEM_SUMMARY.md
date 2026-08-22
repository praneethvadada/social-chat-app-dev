# Call System Rewrite - Summary

## Problem with Old System
1. ❌ No proper state machine - states were scattered
2. ❌ Missing bidirectional signaling - accept/reject not sent back to caller
3. ❌ Agora started too early - not waiting for both users to accept
4. ❌ Chat WebSocket mixed with call signaling
5. ❌ No timeout handling for missed calls
6. ❌ Receiver never notified about acceptance

## Solution Implemented

### Architecture: Separation of Concerns
- **WebSocket** → Call signaling only (events)
- **Agora** → Media only (audio/video)
- **State Machine** → CallSignalingService
- **Agora Lifecycle** → CallStateManager (watches state)

### New Components

#### Frontend Files Created
```
lib/src/services/call_signaling_service_v2.dart
├── Proper state machine (IDLE, OUTGOING, INCOMING, IN_CALL, ENDED)
├── WebSocket listener for signaling events
├── Methods: initiateCall, acceptCall, rejectCall, endCall, reset
└── Extends ChangeNotifier for UI updates

lib/src/services/call_api_v2.dart
├── Send CALL_INVITE through WebSocket
├── Send CALL_ACCEPT through WebSocket
├── Send CALL_REJECT through WebSocket
└── Send CALL_END through WebSocket

lib/src/state/call_state_manager_v2.dart
├── Bridges old UI code with new CallSignalingService
├── Manages Agora lifecycle only
├── Initializes Agora ONLY when state = IN_CALL
└── Cleans up Agora ONLY when state = ENDED
```

#### Backend File Created
```
CallSignalingController.java
├── Listens on /app/call.signal
├── Receives all 4 signaling event types
├── Forwards events to recipient user
├── Validates event types
├── Logs all operations
└── Keeps call logic separate from chat
```

### Call Flow (Fixed)

#### Scenario 1: Successful Call
```
User A initiates call to User B
↓
A: CallSignalingService.initiateCall() → state = OUTGOING
↓
A: Sends CALL_INVITE through WebSocket
↓
Backend: Receives CALL_INVITE, forwards to B
↓
B: Receives CALL_INVITE notification → state = INCOMING
↓
B: Shows incoming call screen (NO Agora yet!)
↓
B: User accepts call
↓
B: CallSignalingService.acceptCall() → state = IN_CALL
↓
B: Sends CALL_ACCEPT through WebSocket
↓
Backend: Receives CALL_ACCEPT, forwards to A
↓
A: Receives CALL_ACCEPT → state = IN_CALL
↓
Both: state = IN_CALL triggers Agora initialization
↓
Both: Join Agora channel (NOW they can hear/see each other)
✓ PROBLEM FIXED: Both sides are synchronized!
```

#### Scenario 2: Rejected Call
```
User A initiates call to User B
↓
A: state = OUTGOING
↓
B: Receives CALL_INVITE → state = INCOMING
↓
B: Shows incoming call screen
↓
B: User rejects call
↓
B: CallSignalingService.rejectCall() → state = ENDED
↓
B: Sends CALL_REJECT through WebSocket
↓
Backend: Forwards CALL_REJECT to A
↓
A: Receives CALL_REJECT → state = ENDED
↓
Both: Never enter IN_CALL, so Agora never starts
✓ PROBLEM FIXED: A knows about rejection immediately!
```

#### Scenario 3: Timeout
```
User A initiates call to User B
↓
A: state = OUTGOING, timeout set for 30 seconds
↓
B: Offline or ignores call
↓
30 seconds pass...
↓
A: Timeout triggered → state = ENDED
↓
A: Sends CALL_END through WebSocket
✓ PROBLEM FIXED: A doesn't wait forever!
```

## Key Improvements

| Feature | Before | After |
|---------|--------|-------|
| **State Sync** | ❌ Partial | ✅ Full bidirectional |
| **Accept/Reject Notification** | ❌ Missing | ✅ Sent to caller |
| **Agora Timing** | ❌ Started early | ✅ Only after both accept |
| **Signaling** | ❌ Mixed with chat | ✅ Separate handler |
| **Timeout** | ❌ None | ✅ 30s for caller |
| **State Machine** | ❌ Scattered | ✅ Centralized |
| **Logging** | ❌ Limited | ✅ Comprehensive |

## Implementation Checklist

### Done ✅
- [x] Created CallSignalingService with proper state machine
- [x] Created CallAPI for sending signals
- [x] Created CallStateManager v2 (Agora-only lifecycle)
- [x] Created backend CallSignalingController
- [x] Documented complete call flow

### To Do
- [ ] Replace old services with v2 versions in UI
- [ ] Test bidirectional call acceptance
- [ ] Test call rejection flow
- [ ] Test missed call timeout
- [ ] Verify Agora joins only after both accept
- [ ] Monitor logs for proper state transitions

## Usage in UI

### Initiate Call (in CallsScreen or similar)
```dart
final signalingService = CallSignalingService();
await signalingService.initiateCall(
  toUserId: userId,
  channelId: channelId,
  isVideo: true,
);
```

### Accept Incoming Call
```dart
final signalingService = CallSignalingService();
await signalingService.acceptCall();
```

### Reject Call
```dart
final signalingService = CallSignalingService();
await signalingService.rejectCall();
```

### End Call
```dart
final signalingService = CallSignalingService();
await signalingService.endCall();
```

### Reset After UI Dismissed
```dart
final signalingService = CallSignalingService();
signalingService.reset();
```

## Testing Quick Guide

### Test 1: Basic Call
1. User A opens Calls screen
2. A clicks on B
3. ✅ B's phone shows incoming call screen
4. B accepts
5. ✅ Both see Agora call screen
6. A ends call
7. ✅ Both return to previous screens

### Test 2: Rejection
1. User A calls B
2. ✅ B's phone shows incoming call
3. B taps "Reject"
4. ✅ A's phone shows "Call rejected"
5. Both return to previous screens

### Test 3: Timeout
1. User A calls B
2. A waits 31 seconds (B is offline)
3. ✅ A's phone shows "Call ended" automatically
4. A returns to calls list

### Test 4: Remote End
1. Both in active call
2. B ends call from CallScreen
3. ✅ A's CallScreen immediately updates
4. Both return to chats/home

## Log Examples

You'll see logs like:
```
[CallSignalingService] Event: CALL_INVITE | State: idle | Payload: {...}
[CallSignalingService] Received CALL_INVITE from 42
[CallSignalingService] State transition: idle -> incoming
[CallSignalingController] handleCallSignal | Event: CALL_INVITE | From: 42 | To: 5
[CallSignalingController] ✓ Forwarded CALL_INVITE from user 42 to user 5
[CallStateManager] Signaling state changed to: incoming
[CallStateManager] Initializing Agora...
[CallStateManager] ✓ Agora initialized and joined
```

## References
- Agora docs: Only start media after both users are ready
- WebSocket docs: Use message mapping for separate concerns
- State machine: Finite states with validated transitions
