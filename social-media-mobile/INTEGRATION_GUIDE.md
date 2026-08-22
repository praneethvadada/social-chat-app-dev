# Integration Guide - Replacing Old Call System with New One

## Step 1: Replace CallStateManager in main.dart

**Current (old):**
```dart
provider.ChangeNotifierProvider.value(value: CallStateManager()),
```

**New (with old reference for logging):**
```dart
// Use the new v2 version which has proper state machine + Agora lifecycle
provider.ChangeNotifierProvider(create: (_) => CallStateManager()),
```

The `CallStateManager` should now import from `call_state_manager_v2.dart`:
```dart
import 'src/state/call_state_manager_v2.dart';
```

## Step 2: Add New Services to Imports

In any screen that handles calls, add:
```dart
import '../../services/call_signaling_service_v2.dart';
```

## Step 3: Update CallsScreen (or Similar) to Initiate Calls

**Find where calls are initiated** (likely in a onTap or button callback):

**Old code:**
```dart
// Navigate to call screen (wrong approach)
GoRouter.of(context).push('/call', extra: {...});
```

**New code:**
```dart
final signalingService = CallSignalingService();
try {
  await signalingService.initiateCall(
    toUserId: selectedUserId,
    channelId: channelIdAsNumber, // Pass as int, not string
    isVideo: true, // Set based on call type
  );
  // Don't navigate anywhere - CallStateManager will trigger UI update
  // via AppState monitoring
} catch (e) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Failed to initiate call: $e')),
  );
}
```

## Step 4: Update IncomingCallScreen

**Old (if using GoRouter):**
```dart
onAccept: () {
  GoRouter.of(context).push('/call', extra: callData);
},
```

**New (using CallSignalingService):**
```dart
onAccept: () async {
  try {
    final signalingService = CallSignalingService();
    await signalingService.acceptCall();
    // UI update handled by CallStateManager listening to CallSignalingService
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Failed to accept call: $e')),
    );
  }
},
onReject: () async {
  try {
    final signalingService = CallSignalingService();
    await signalingService.rejectCall();
    // UI will update to show rejection
  } catch (e) {
    print('Error rejecting call: $e');
  }
},
```

## Step 5: Update CallScreen

**Old (if managing state with GoRouter):**
```dart
onEndCall: () {
  GoRouter.of(context).go('/home');
},
```

**New (using CallSignalingService):**
```dart
onEndCall: () async {
  try {
    final signalingService = CallSignalingService();
    await signalingService.endCall();
    // Don't navigate - state change will trigger UI to dismiss
  } catch (e) {
    print('Error ending call: $e');
  }
},
```

## Step 6: Update CallOverlayManager (or wherever call UI is shown)

The call screens should be shown/hidden based on `CallStateManager.currentState`.

In `MainApp` or wherever you render call screens:

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  // Watch call state
  final callState = ref.watch(
    appStateProvider.select((state) => state)
  );
  
  // Also watch if there's an active call
  return provider.Consumer<CallStateManager>(
    builder: (context, callStateManager, child) {
      // Show appropriate UI based on call state
      if (callStateManager.currentState == CallState.incoming) {
        return Stack(
          children: [
            child!,
            IncomingCallScreen(
              payload: callStateManager.activeCallPayload ?? {},
            ),
          ],
        );
      } else if (callStateManager.currentState == CallState.outgoing) {
        return Stack(
          children: [
            child!,
            CallingLoaderScreen(
              payload: callStateManager.activeCallPayload ?? {},
            ),
          ],
        );
      } else if (callStateManager.currentState == CallState.inCall) {
        return Stack(
          children: [
            child!,
            CallScreen(
              channelName: callStateManager.activeCallPayload?['channelId']?.toString() ?? '',
              otherUserId: callStateManager.activeCallPayload?['toUserId'] as int? ?? 0,
              isVideo: callStateManager.activeCallPayload?['isVideo'] as bool? ?? true,
            ),
          ],
        );
      }
      
      return child!;
    },
    child: child,
  );
}
```

## Step 7: Backend Setup

### Create CallSignalingController

Add the new `CallSignalingController.java` file to:
```
backend/social-service/src/main/java/com/socialmedia/social/controller/
```

### Ensure WebSocket Session Has userId

In your WebSocket configuration (likely in a `WebSocketConfig` or `WebSocketEventListener`):

```java
@Component
public class WebSocketEventListener {
    
    @EventListener
    public void handleWebSocketConnectListener(SessionConnectedEvent event) {
        StompHeaderAccessor headerAccessor = StompHeaderAccessor.wrap(event.getMessage());
        String userId = headerAccessor.getNativeHeader("userId").get(0);
        
        if (userId != null && !userId.isEmpty()) {
            headerAccessor.getSessionAttributes().put("userId", Long.parseLong(userId));
        }
    }
}
```

### Frontend Must Send userId on Connection

In `ChatWebSocketService` during WebSocket connect:

```dart
// When connecting to WebSocket, include userId
final client = SockJSClient(...)
  ..connect(
    'http://your-backend/ws',
    headers: {
      'userId': userId.toString(), // Ensure this is sent
    },
  );
```

## Step 8: Verify Cleanup

Make sure when user logs out, the CallSignalingService resets:

```dart
// In SettingsScreen handleLogout or wherever logout happens
await ApiService.logout();
CallSignalingService().reset(); // Reset call state
ref.read(appStateProvider.notifier).logout(); // Change app state
```

## Step 9: Testing Checklist

### Test 1: Outgoing Call
- [ ] User A opens calls list
- [ ] User A clicks "Call" button
- [ ] Check logs: `[CallSignalingService] State transition: idle -> outgoing`
- [ ] Check logs: `[CallSignalingController] ✓ Forwarded CALL_INVITE from user X to user Y`
- [ ] User B receives notification
- [ ] Check logs on B's device: `[CallSignalingService] State transition: idle -> incoming`

### Test 2: Accept Call
- [ ] User B sees incoming call screen
- [ ] User B taps "Accept"
- [ ] Check logs on B: `[CallSignalingService] State transition: incoming -> inCall`
- [ ] Check logs on B: `[CallStateManager] Initializing Agora...`
- [ ] Check logs on A: `[CallSignalingService] State transition: outgoing -> inCall`
- [ ] Both users see call screen
- [ ] Both can hear/see each other (Agora working)

### Test 3: Reject Call
- [ ] User A calls User B
- [ ] User B sees incoming call
- [ ] User B taps "Reject"
- [ ] Check logs on B: `[CallSignalingService] State transition: incoming -> ended`
- [ ] Check logs on A: `[CallSignalingService] State transition: outgoing -> ended`
- [ ] Both return to previous screens

### Test 4: End During Call
- [ ] Both in active call
- [ ] User A taps end call
- [ ] Check logs on A: `[CallStateManager] Cleaning up Agora...`
- [ ] Check logs on B: `[CallSignalingService] State transition: inCall -> ended`
- [ ] Both see call ended
- [ ] Can make another call immediately

## Troubleshooting

### "CALL_INVITE not received by B"
1. Check backend logs: Is `CallSignalingController` being called?
2. Check B's WebSocket is connected: Look for `[ChatWebSocketService]` logs
3. Check userId in session: Should be in `handleCallSignal` logs
4. Check recipient queue: `/user/{userId}/queue/notifications`

### "Call accepted but Agora doesn't start"
1. Check CallStateManager logs: Does state transition to `inCall`?
2. Check Agora initialization: Look for `[CallStateManager] Initializing Agora...`
3. Check permissions: Microphone/camera requested?
4. Check channel name: Is it the same on both sides?

### "Receiver side doesn't show incoming call"
1. Check CALL_INVITE forwarded by backend
2. Check notification listener in `CallSignalingService`
3. Check `_setupSignalingListener()` was called
4. Check WebSocket `isConnected` flag

### "State changes but UI doesn't update"
1. Check `CallStateManager` extends `ChangeNotifier`
2. Check `notifyListeners()` is called after state change
3. Check UI is watching `CallStateManager` via provider
4. Check call screens are in the widget tree

## Quick Reference

| Action | Code |
|--------|------|
| Start call | `CallSignalingService().initiateCall(...)` |
| Accept call | `CallSignalingService().acceptCall()` |
| Reject call | `CallSignalingService().rejectCall()` |
| End call | `CallSignalingService().endCall()` |
| Reset state | `CallSignalingService().reset()` |
| Watch state | `ref.watch(callStateProvider)` |
| Current state | `CallStateManager().currentState` |
| Call data | `CallStateManager().activeCallPayload` |

## Files to Keep for Reference
- Old `call_state_manager.dart`
- Old `call_signaling_service.dart`
- Old `call_api.dart`

These can be deleted after new system is thoroughly tested.
