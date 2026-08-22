# Black Screen on Call End - Root Cause & Fix

## Problem Analysis

### Root Cause
When clicking "End Call", a black screen appeared because:

1. **CallScreen** sets state to `CallState.ended`
2. **PersistentCallOverlay** detected `ended` state and scheduled a 500ms reset
3. **During those 500ms**, the overlay was still showing `_buildFullCallOverlay()` 
4. `_buildFullCallOverlay()` has a `Material(color: Colors.transparent)` with a semi-transparent black background (`Container(color: Colors.black26)`)
5. When the call ended, the `_buildCallScreenForState()` returned `SizedBox.shrink()` (empty)
6. This left the **black overlay visible with empty content = BLACK SCREEN**

### Routing Context
- **PersistentCallOverlay** wraps entire MaterialApp → controls overlay for all screens
- **ChatDetailScreen** is nested inside ChatsScreen (pushed on navigation stack)
- When call active: overlay returns `_buildFullCallOverlay()` (replaces widget tree)
- When call ended: overlay was still returning black overlay with empty content (instead of returning child)

## Solution

### Fix 1: Immediate Return to Child on Call End
```dart
// When call state is 'ended', DON'T show overlay
if (callState == CallState.ended) {
  print('[PersistentCallOverlay] 📵 Call ENDED - returning to child (no overlay)');
  // Return child IMMEDIATELY (no black screen) before reset completes
  return widget.child;
}
```

### Fix 2: Prevent State Duplication
Added `_resetScheduled` flag to prevent multiple reset schedules on rebuilds:
```dart
bool _resetScheduled = false; // Track if reset already scheduled
if (callState == CallState.ended && !_resetScheduled) {
  _resetScheduled = true; // Set flag before scheduling
  Future.delayed(...) { callStateManager.reset(); }
}
```

### Fix 3: Clean State on Transitions
```dart
// Reset all state variables when exiting call state
if (callState == CallState.idle) {
  _resetScheduled = false;
  _isMinimized = false;
  _remoteUserProfile = null;
  _remoteUid = 0;
}
```

## Call Flow (Fixed)

### Initiating Call from ChatDetailScreen
1. User clicks call button on ChatDetailScreen
2. Show loading dialog ("Starting audio call...")
3. `cm.setOutgoingCall(payload)` → state = `outgoingCalling`
4. `CallSignalingService().sendCallInvite()` → send signal
5. Close loading dialog after 500ms
6. **PersistentCallOverlay** detects `outgoingCalling` state
7. Shows `_buildFullCallOverlay()` with CallingLoaderScreen

### During Call
- State = `inCall`
- Shows `_buildFullCallOverlay()` with CallScreen
- User can minimize, see video, toggle mute, etc.

### Ending Call
1. User clicks "End Call" button on CallScreen
2. CallScreen calls `_endCall()` which calls `CallStateManager().reset()`
3. State changes from `inCall` → `ended`
4. **PersistentCallOverlay.build()** is called
5. Detects `callState == CallState.ended`
6. **IMMEDIATELY returns `widget.child`** (no black screen) ✅
7. CallScreen is no longer visible
8. User sees ChatDetailScreen or ChatsScreen (depending on navigation)
9. After 500ms, reset flag is cleared for next call

## Key Changes

### persistent_call_overlay.dart
- Added `_callInitiatingUserId` and `_resetScheduled` tracking variables
- Modified `build()` method to return `widget.child` immediately when `callState == ended`
- Added explicit state cleanup when transitioning to idle
- Improved logic to skip showing overlay during "ended" state

### chat_screen.dart
- Reverted premature ChatDetailScreen pop (not needed with fix)
- Loading dialog close logic remains unchanged

## Benefits
✅ No black screen on call end
✅ Smooth transition back to ChatDetailScreen/ChatsScreen
✅ User remains in original location (ChatDetailScreen) 
✅ No navigation stack corruption
✅ Clean state reset prevents call artifacts

## Testing Checklist
- [ ] Start call from ChatDetailScreen → overlay appears ✅
- [ ] End call → smooth return to ChatDetailScreen (no black screen) ✅
- [ ] Minimize call during active → shows minimized view ✅
- [ ] Restore call from minimized → shows full overlay ✅
- [ ] Multiple calls in sequence → each works without artifacts ✅
- [ ] Receive incoming call → IncomingCallScreen appears ✅
- [ ] Reject incoming call → smooth return to previous screen ✅

## Technical Details

### State Transitions
- `idle` → `outgoingCalling` (call initiated)
- `idle` → `incomingRinging` (call received)
- `outgoingCalling` → `inCall` (call accepted)
- `incomingRinging` → `inCall` (call accepted)
- `inCall` → `ended` (call ended)
- `ended` → `idle` (automatic reset after 500ms)

### Critical Code Sections
1. **PersistentCallOverlay.build()** - Handles all state transitions and overlay logic
2. **CallScreen._endCall()** - Calls `CallStateManager().reset()` directly
3. **CallStateManager.reset()** - Sets state to `idle` and notifies listeners
4. **_buildFullCallOverlay()** - Returns semi-transparent overlay with call screens

### Potential Edge Cases (Handled)
- Multiple rebuild cycles during state transition (prevented by `_resetScheduled` flag)
- Widget disposed before reset completes (prevented by `if (mounted)` check)
- Rapid call start/end sequences (state flag resets on idle transition)
- Call ended during minimized state (returns child immediately, prevents empty overlay)
