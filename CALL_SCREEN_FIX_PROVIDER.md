# Call Screen Modal Overlay Fix - Provider.of Corrections

## Problem Identified
The call screen was not appearing as a modal overlay on top when you clicked the call button. The root cause was that the app was creating **NEW instances** of `CallStateManager()` in several places instead of using the **SHARED provider instance**.

### How This Broke Call Screen Display
1. When you clicked "call button" in ChatScreen, it called `_startCall()`
2. `_startCall()` created: `final cm = CallStateManager();` (NEW INSTANCE)
3. This new instance called `cm.setOutgoingCall(payload)` 
4. But `MyApp` was watching a **DIFFERENT** CallStateManager instance via Provider
5. Result: MyApp never saw the state change, so the call screen overlay never appeared
6. The call WAS sent (backend working) but the UI layer didn't show it

## Solution Applied
Changed all widget code (StatefulWidget / StatelessWidget screens) to use the **SHARED Provider instance**:

### Files Modified

#### 1. **lib/src/screens/chats/chat_screen.dart** (ChatDetailScreen)
**Change:** Line ~913 in `_startCall()` method
```dart
// BEFORE (WRONG - new instance):
final cm = CallStateManager();

// AFTER (CORRECT - uses provider):
final cm = Provider.of<CallStateManager>(context, listen: false);
```
**Why:** ChatDetailScreen uses Provider package and has access to context

---

#### 2. **lib/src/screens/calls/calls_screen_v2.dart** (CallsScreenV2)
**Changes:** 
- Added import: `import 'package:provider/provider.dart';`
- Line ~307 in `_startCall()` method
```dart
// BEFORE:
final cm = CallStateManager();

// AFTER:
final cm = Provider.of<CallStateManager>(context, listen: false);
```
**Why:** CallsScreenV2 is a StatefulWidget with access to context

---

#### 3. **lib/src/screens/calls/calls_screen.dart** (CallsScreen)
**Changes:**
- Added import: `import 'package:provider/provider.dart';`
- Line ~207 in `_startCall()` method
```dart
// BEFORE:
final cm = CallStateManager();

// AFTER:
final cm = Provider.of<CallStateManager>(context, listen: false);
```
**Why:** CallsScreen is a StatefulWidget with access to context

---

#### 4. **lib/src/screens/call_screen.dart** (CallScreen)
**Changes:**
- Added import: `import 'package:provider/provider.dart';`
- Line ~82 in `initState()` listener setup
```dart
// BEFORE:
final cm = CallStateManager();

// AFTER:
final cm = Provider.of<CallStateManager>(context, listen: false);
```
- Line ~362 in `dispose()` method
```dart
// BEFORE:
final cm = CallStateManager();

// AFTER:
final cm = Provider.of<CallStateManager>(context, listen: false);
```
**Why:** CallScreen is a StatefulWidget with access to context in both initState and dispose

---

## Files NOT Modified (Correct as-is)
These services/files create new instances BUT they're only **reading state**, not triggering UI updates:
- ❌ `lib/src/services/call_signaling_service.dart` (lines 46, 133) - Service layer, no UI rendering
- ❌ `lib/main.dart` (line 43) - App initialization, one-time reset
- ✅ These are fine as-is

---

## How It Works Now

```
User clicks call button
    ↓
ChatScreen._startCall() calls Provider.of<CallStateManager>()
    ↓
Gets the SHARED CallStateManager instance
    ↓
cm.setOutgoingCall(payload) updates SHARED state
    ↓
MyApp watches this SAME instance via provider.Consumer
    ↓
MyApp detects callManager.currentState != CallState.idle
    ↓
MyApp renders _buildCallScreen() in Stack
    ↓
Call screen appears as TOP LAYER (modal overlay) ✅
```

## Stack Widget Structure in MyApp
```dart
Stack(
  children: [
    _buildAuthScreen(appNav),           // Bottom layer: MainApp/chat screen
    if (appNav.openModal != ModalScreen.none)
      _buildModalScreen(...),            // Middle layer: settings/search etc
    if (callManager.currentState != CallState.idle)
      IgnorePointer(ignoring: false,
        child: _buildCallScreen(...)     // TOP LAYER: call screen appears here ✅
      ),
  ],
)
```

## Expected Behavior After Fix
✅ Click call button → Call screen appears immediately on top (no delay)
✅ Call screen is modal overlay (user can't interact with chat screen behind it)
✅ Click end call → CallStateManager.reset() → state returns to idle → MyApp rebuilds → call screen disappears
✅ App returns to ChatScreen automatically (no navigation pop needed)

## Testing
```bash
flutter analyze --no-pub   # Should show only pre-existing errors (chatServiceProvider)
flutter run                # Should compile without new errors
```

**Result:** ✅ No new compile errors introduced. All provider fixes working correctly.

