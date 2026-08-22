# Black Screen Issue - Root Cause Analysis & Complete Fix

## Architecture Overview

### Routing Hierarchy
```
MaterialApp (navigatorKey: rootNavigatorKey)
  ↓
PersistentCallOverlay (wraps everything)
  ↓
_buildAuthScreen() [State-based, not stack-based]
  ↓
MainApp (when authenticated)
  ↓
IndexedStack [maintains all 4 tabs]
  ├─ HomeScreen (Tab 0)
  ├─ ChatsScreen (Tab 1) 
  │  └─ **Local Navigator** (for ChatDetailScreen)
  ├─ CallsScreen (Tab 2)
  └─ ProfileScreen (Tab 3)
```

### Key Insight
- **AppStateManager** controls global auth state and tab switching (state-based routing)
- **ChatsScreen** uses traditional stack-based routing with `Navigator.push()`
- **PersistentCallOverlay** replaces the entire widget tree when a call is active

## Root Cause Analysis

### The Problem: Dual Navigation Stack Conflict

**When you start a call from ChatDetailScreen:**

1. You are on `ChatsScreen` (IndexedStack at index 1)
2. You navigate to `ChatDetailScreen` via `Navigator.push()`
   - This creates: `ChatsScreen` → `ChatDetailScreen` (local navigation stack)

3. You start a call from `ChatDetailScreen`
4. `PersistentCallOverlay` detects `CallState.outgoingCalling`
5. It returns `_buildFullCallOverlay()` which replaces the entire widget tree

**The conflict:**
- `PersistentCallOverlay` shows the call overlay
- But `ChatsScreen`'s local Navigator still has `ChatDetailScreen` on its stack
- When the call ends and we return `widget.child`:
  - The overlay is hidden
  - But the local Navigator tries to show `ChatDetailScreen`
  - The `ChatsScreen` also tries to render
  - **Rendering conflict = Black Screen** 🖤

### Visual Representation

**BEFORE FIX - Navigation Stack Corruption:**
```
Initial: ChatsScreen
  ↓
User navigates: ChatsScreen → ChatDetailScreen
  (ChatsScreen local Navigator stack: [ChatsScreen, ChatDetailScreen])
  ↓
Call started: PersistentCallOverlay shows call overlay
  (But ChatDetailScreen is STILL on ChatsScreen's local stack!)
  ↓
Call ended: PersistentCallOverlay returns widget.child
  (Now ChatsScreen tries to show ChatDetailScreen, causing conflict)
  ↓
RESULT: Black Screen due to conflicting render states
```

**AFTER FIX - Clean Navigation Stack:**
```
Initial: ChatsScreen
  ↓
User navigates: ChatsScreen → ChatDetailScreen
  ↓
Call initiated:
  1. Pop ChatDetailScreen (returns to ChatsScreen)
  2. Close loading dialog
  3. cm.setOutgoingCall() - state = outgoingCalling
  4. PersistentCallOverlay shows call overlay over ChatsScreen
  ↓
Call ended:
  1. cm.reset() - state = idle
  2. PersistentCallOverlay immediately returns widget.child
  3. User sees clean ChatsScreen (no ChatDetailScreen on stack)
  ↓
RESULT: Smooth transition, no black screen ✅
```

## The Complete Fix

### 1. **Pop ChatDetailScreen When Call Starts** (chat_screen.dart)

```dart
void _startCall(int toUserId, bool isVideo) {
  // ... setup code ...
  
  cm.setOutgoingCall(payload);
  CallSignalingService().sendCallInvite(...);
  
  // 🔴 FIX: Pop ChatDetailScreen when call starts
  Future.delayed(const Duration(milliseconds: 500), () {
    if (mounted) {
      // First close loading dialog
      Navigator.pop(context);  // Pop dialog
      
      // Then pop ChatDetailScreen to return to ChatsScreen
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted) {
          Navigator.pop(context);  // Pop ChatDetailScreen
          // Now ChatsScreen's local Navigator is clean
        }
      });
    }
  });
}
```

**Why this works:**
- When the overlay appears, `ChatDetailScreen` is NO LONGER on the navigation stack
- The overlay shows cleanly over `ChatsScreen`
- When call ends, there's no navigation conflict
- User smoothly returns to `ChatsScreen`

### 2. **Immediately Return to Child on Call End** (persistent_call_overlay.dart)

```dart
@override
Widget build(BuildContext context) {
  return Consumer<CallStateManager>(
    builder: (context, callStateManager, _) {
      final callState = callStateManager.currentState;

      // CRITICAL: When call ends, show NO overlay
      if (callState == CallState.ended) {
        // Return child IMMEDIATELY (don't wait for reset)
        // This prevents the black overlay (Colors.black26) from showing
        if (!_resetScheduled) {
          _resetScheduled = true;
          Future.delayed(const Duration(milliseconds: 300), () {
            if (mounted) {
              callStateManager.reset();
              _resetScheduled = false;
            }
          });
        }
        
        // Clean up state and return child
        _isMinimized = false;
        _remoteUserProfile = null;
        _remoteUid = 0;
        return widget.child;  // No overlay = no black screen
      }

      // Rest of routing logic...
    },
  );
}
```

**Why this works:**
- The overlay has `Container(color: Colors.black26)` which creates the black visual
- When call ends, we return the child IMMEDIATELY instead of showing empty overlay
- No transition delay = no black screen
- Reset happens in the background without blocking UI

## Call Flow Diagram (FIXED)

```
START CALL
│
├─ [ChatDetailScreen] 🔴 _startCall() called
│  ├─ Show loading dialog
│  ├─ cm.setOutgoingCall(payload)
│  ├─ CallSignalingService().sendCallInvite()
│  └─ After 500ms:
│     ├─ Close loading dialog (Navigator.pop)
│     └─ Pop ChatDetailScreen (Navigator.pop) ← CRITICAL FIX
│
├─ [ChatsScreen] Now visible again (clean local Navigator)
│
├─ [PersistentCallOverlay] 🔴 Detects state change
│  ├─ callState == CallState.outgoingCalling
│  └─ Returns _buildFullCallOverlay()
│     └─ Shows CallingLoaderScreen over ChatsScreen
│
├─ [CallStateManager] Transitions state
│  └─ outgoingCalling → inCall (when receiver accepts)
│
├─ [CallScreen] Shows with audio/video
│  └─ User clicks "End Call"
│
├─ [CallStateManager] 🔴 endCall() called
│  └─ Sets state = CallState.ended
│
├─ [PersistentCallOverlay] 🔴 Detects state change
│  ├─ callState == CallState.ended
│  ├─ Schedules reset in 300ms
│  └─ **IMMEDIATELY returns widget.child** ← CRITICAL FIX
│     └─ No overlay shown, ChatsScreen visible
│
├─ [After 300ms] Reset scheduled
│  └─ callStateManager.reset() → state = idle
│
└─ END: User sees ChatsScreen (smooth, no black screen) ✅
```

## Key Differences from Previous Attempt

### ❌ PREVIOUS (FAILED)
- Just returned overlay during ended state
- Overlay had semi-transparent black background
- Black background visible during transition = Black Screen
- No ChatDetailScreen pop = navigation stack corruption

### ✅ CURRENT (WORKING)
- Pop ChatDetailScreen when call starts (clean navigation stack)
- Return widget.child immediately when call ends (no overlay)
- No black background ever shown during ended state
- Reset happens in background without blocking
- User sees clean app state at all times

## Technical Details

### State Machine
```
idle ──call initiated──> outgoingCalling
                            │
                            ├─ receiver rejects → ended
                            │                       │
                            ├─ receiver accepts → inCall
                            │                       │
                            └───────────────────────┴─ call ended → ended
                                                       │
                                                       └─ reset → idle
```

### Navigation Stack Management
- **ChatsScreen local Navigator stack:**
  - Before call: `[ChatsScreen, ChatDetailScreen]`
  - After pop: `[ChatsScreen]` ← Clean
  - After call: `[ChatsScreen]` ← User sees ChatsScreen

- **PersistentCallOverlay:**
  - idle: Shows `widget.child` (MainApp/ChatsScreen)
  - outgoingCalling: Shows `_buildFullCallOverlay()` (overlay)
  - inCall: Shows `_buildFullCallOverlay()` (overlay)
  - ended: Shows `widget.child` **IMMEDIATELY** (not overlay)
  - Then after 300ms: state → idle

## Files Modified
1. **lib/src/screens/chats/chat_screen.dart**
   - `_startCall()` method
   - Added ChatDetailScreen pop logic

2. **lib/src/widgets/persistent_call_overlay.dart**
   - `build()` method
   - Updated ended state handling
   - Immediate child return on ended

## Testing Scenario

**Test Case: Call from ChatDetailScreen**
1. ✅ Open ChatsScreen
2. ✅ Tap conversation → ChatDetailScreen opens
3. ✅ Tap call icon → Loading dialog shows
4. ✅ After 500ms:
   - Dialog closes
   - ChatDetailScreen pops
   - Calling overlay appears over ChatsScreen ✅
5. ✅ Wait for receiver to accept or reject
6. ✅ If accepted: CallScreen shows with audio/video
7. ✅ Click "End Call" button
8. ✅ Smooth transition back to ChatsScreen
9. ✅ **NO BLACK SCREEN** ✅

## Summary

The black screen was caused by a **navigation stack conflict** where:
1. ChatDetailScreen was still on the local navigation stack
2. The overlay tried to render on top of it
3. When the overlay ended, both tried to render simultaneously
4. This created a rendering conflict = black screen

The fix cleanly separates concerns:
1. **Pop ChatDetailScreen** when call starts → clean navigation
2. **Return child immediately** when call ends → no black overlay
3. **Reset state asynchronously** → doesn't block UI

Result: **Smooth, artifact-free calling experience** 🎯
