# Fix: Calling Screen Not Appearing on Chat Detail Screen (January 10, 2026)

## Problem Identified

When initiating a call from the **ChatDetailScreen**, the calling screen was **not appearing**:
1. User stays on ChatDetailScreen (no visible change)
2. Call state changes to `outgoingCalling` (verified in logs)
3. CallingLoaderScreen should appear but doesn't
4. Only after pressing back button to return to chat list does the calling screen appear
5. **Black screen when ending call** - app gets stuck in ended state

**Root Cause:** The PersistentCallOverlay was structured using a **Stack** that placed the call overlay **BELOW** the chatDetailScreen in the widget hierarchy.

```
Navigation Stack (Top to Bottom):
├─ ChatDetailScreen (pushed via Navigator.push)
│  └─ CallingLoaderScreen should appear here, but...
│     └─ PersistentCallOverlay (where calling screen TRIES to appear)
│        └─ MainApp
│           └─ App root

Issue: ChatDetailScreen is ABOVE PersistentCallOverlay, so overlay is hidden!
```

---

## Solution Applied

**Remove the Stack wrapping and return the call overlay as a direct full-screen replacement:**

Changed from:
```dart
// OLD: Puts call overlay BELOW widget.child in widget tree
return Stack(
  children: [
    widget.child,                              // ← ChatDetailScreen on top
    _buildFullCallOverlay(...),                // ← CallingLoaderScreen hidden below
  ],
);
```

To:
```dart
// NEW: Replaces entire widget tree with call overlay (full screen)
return _buildFullCallOverlay(context, callStateManager);  // ← Full screen, on top!
```

**Also removed Positioned.fill from _buildFullCallOverlay:**

Changed from:
```dart
return Positioned.fill(
  child: Material(
    // ... call screen content
  ),
);
```

To:
```dart
return Material(
  color: Colors.transparent,
  child: Stack(
    // ... call screen content
  ),
);
```

---

## How This Fixes The Issues

### Issue 1: Calling Screen Not Appearing on Chat Detail

**Before Fix:**
```
User on ChatDetailScreen
  ↓ [click call button]
setOutgoingCall() called → state = outgoingCalling
  ↓
PersistentCallOverlay tries to build Stack(widget.child, overlay)
  ↓
ChatDetailScreen is rendered ON TOP of the overlay
  ↓
CallingLoaderScreen hidden behind ChatDetailScreen ❌
```

**After Fix:**
```
User on ChatDetailScreen
  ↓ [click call button]
setOutgoingCall() called → state = outgoingCalling
  ↓
PersistentCallOverlay returns _buildFullCallOverlay directly
  ↓
CallingLoaderScreen replaces entire widget tree
  ↓
Calling screen appears FULL SCREEN on top ✅
```

### Issue 2: Black Screen When Ending Call

**Before Fix:**
```
End call → state = ended
  ↓
Auto-reset after 500ms → state = idle
  ↓
PersistentCallOverlay tries to return Stack(widget.child, overlay) again
  ↓
ChatDetailScreen might still be in navigation stack
  ↓
[BLACK SCREEN] - state cleanup incomplete ❌
```

**After Fix:**
```
End call → state = ended
  ↓
Auto-reset after 500ms → state = idle
  ↓
PersistentCallOverlay directly returns widget.child
  ↓
ChatDetailScreen (from Navigator stack) is visible
  ↓
Smooth return to chat ✅
```

---

## Technical Details

### Widget Tree Structure

**Before Fix (Incorrect):**
```
MyApp
├─ PersistentCallOverlay
│  └─ child: Stack
│     ├─ _buildAuthScreen() [MainApp]
│     │  └─ Navigator stack
│     │     └─ ChatDetailScreen ← On top!
│     └─ _buildFullCallOverlay() ← Below ChatDetailScreen
│        └─ CallingLoaderScreen
└─ Modal screens
```

**After Fix (Correct):**
```
MyApp
├─ When CallState == idle:
│  └─ PersistentCallOverlay.child: Stack
│     ├─ _buildAuthScreen() [MainApp]
│     │  └─ Navigator stack
│     │     └─ ChatDetailScreen
│     └─ Modal screens
│
├─ When CallState != idle:
│  └─ PersistentCallOverlay returns _buildFullCallOverlay()
│     └─ CallingLoaderScreen ← Full screen, replaces everything!
```

### Code Changes

**File:** `lib/src/widgets/persistent_call_overlay.dart`

**Change 1: Lines 157-169** - Return calling overlay as full-screen replacement
```dart
// 🔴 FIX 4: Show full call screen REPLACE the app (not overlay in Stack)
if (callState != CallState.idle) {
  final channelName = payload?['channelName'] as String? ?? '';
  CallNotificationService().cancelCallNotification(channelName);
  
  // Return ONLY the call overlay as full screen replacement
  return _buildFullCallOverlay(context, callStateManager);  // ← NEW
}
```

**Change 2: Lines 428-442** - Remove Positioned.fill wrapper
```dart
// Was: return Positioned.fill(child: Material(...
// Now: return Material(...)
return Material(
  color: Colors.transparent,
  child: Stack(
    // ... content same
  ),
);
```

**Change 3: Lines 479-481** - Remove extra closing parentheses
```dart
// Was: ), ), ); 
// Now: );
        ),
      ),
    );
```

---

## Expected Behavior After Fix

### Scenario 1: Calling from Chat Detail Screen

```
User on ChatDetailScreen with UserB
  ↓ [taps call button]
1. Loading dialog appears (green spinner)
  ↓ [500ms]
2. Loading dialog closes
  ↓
3. CallingLoaderScreen appears FULL SCREEN ✅
   - Shows UserB's profile
   - Shows "Calling..." with spinner
   - Can see back button to minimize
  ↓ [UserB accepts]
4. Both transition to CallScreen ✅
   - Audio/video active
   - Mute/unmute buttons visible
  ↓ [either taps end call]
5. "Call Ended" screen briefly visible
  ↓ [500ms auto-reset]
6. Returns to ChatDetailScreen smoothly ✅
   - No black screen
   - No frozen UI
   - Can continue chatting
```

### Scenario 2: Receiving Call While on Chat Detail Screen

```
User on ChatDetailScreen
  ↓ [receives CALL_INVITE]
1. IncomingCallScreen appears FULL SCREEN ✅
   - Shows caller's profile
   - Shows accept/decline buttons
   - Can hear ringtone
  ↓ [user taps accept]
2. Both transition to CallScreen ✅
  ↓ [call ends]
3. Returns to ChatDetailScreen ✅
   - Previous conversation preserved
```

---

## Test Checklist

- [ ] **On Chat Detail Screen:**
  - [ ] Tap call button → loading dialog appears
  - [ ] Dialog closes after 500ms
  - [ ] Calling screen appears FULL SCREEN
  - [ ] Calling screen covers ChatDetailScreen (not side-by-side)
  - [ ] Remote user profile shows correctly
  - [ ] "Calling..." spinner shows

- [ ] **During Active Call:**
  - [ ] Audio/video works
  - [ ] Mute/unmute buttons work
  - [ ] Minimize button works (goes to floating preview)
  - [ ] Expand button works (returns to full screen)

- [ ] **Ending Call:**
  - [ ] Tap end call button
  - [ ] "Call Ended" message shows briefly (max 1 second)
  - [ ] NO BLACK SCREEN
  - [ ] Smoothly returns to ChatDetailScreen
  - [ ] Previous messages still visible
  - [ ] Can scroll chat history
  - [ ] Can send new messages immediately

- [ ] **Receiving Call:**
  - [ ] IncomingCallScreen appears full screen
  - [ ] Accept button transitions to CallScreen
  - [ ] Decline button returns to ChatDetailScreen
  - [ ] Caller info displays correctly

- [ ] **Rapid Calls:**
  - [ ] End first call
  - [ ] Immediately tap call button again
  - [ ] Second call starts without "already in call" error
  - [ ] State properly reset

---

## Why This Solution Works

### 1. **Simple and Elegant**
- No complex widget tree manipulation
- Just returns the calling screen when active
- Returns widget.child (ChatDetailScreen) when idle

### 2. **Works with All Navigation Stacks**
- ChatDetailScreen is in Navigator stack
- PersistentCallOverlay is ABOVE Navigator in widget tree
- By returning calling screen directly, it appears ON TOP of all navigation

### 3. **Consistent with Material Design**
- Similar to how modals/dialogs work
- Overlay completely replaces screen content when active
- Returns to previous content when dismissed

### 4. **Fixes Black Screen Issue**
- When auto-reset to idle, returns widget.child immediately
- No delay or state confusion
- ChatDetailScreen is already in navigation stack, ready to show

### 5. **Minimization Still Works**
- When _isMinimized = true, Stack with FloatingVideoPreview shows
- Wraps widget.child with floating preview
- Tapping bar expands back to full screen

---

## Comparison: Old vs New Architecture

| Aspect | Before | After |
|--------|--------|-------|
| **Call Screen Position** | Below ChatDetailScreen (hidden) | Above ChatDetailScreen (visible) |
| **Widget When Not Calling** | Stack(child, overlay) | child only |
| **Widget When Calling** | Stack(child, overlay) | overlay only |
| **Appears on Chat Detail** | ❌ No | ✅ Yes |
| **Black Screen Risk** | ⚠️ High | ✅ Low |
| **Navigation Compatibility** | ❌ Bad | ✅ Excellent |
| **Code Complexity** | Medium | Simple |

---

## Files Modified

- ✅ `lib/src/widgets/persistent_call_overlay.dart`
  - Line 157-169: Changed return from Stack to direct overlay
  - Line 428-442: Removed Positioned.fill wrapper
  - Line 479-481: Fixed closing brackets

---

## Rollback Plan

If issues occur:

```bash
# Revert changes
git checkout HEAD -- lib/src/widgets/persistent_call_overlay.dart

# Rebuild
flutter clean && flutter pub get && flutter run
```

This reverts to the previous Stack-based approach (with the loading dialog still present from earlier fixes).

---

## Summary of All Fixes (Cumulative)

| # | Issue | Fix | File | Status |
|---|-------|-----|------|--------|
| 1 | No feedback when initiating call | Loading dialog with spinner | chat_screen.dart | ✅ |
| 2 | Black screen on call end | Auto-reset to idle after 500ms | persistent_call_overlay.dart | ✅ |
| 3 | State sync issues | Improved state transitions | (infrastructure) | ✅ |
| **4** | **Calling screen not on chat detail** | **Return overlay as full-screen replacement** | **persistent_call_overlay.dart** | **✅ NEW** |

---

## Next Steps

1. **Build and deploy:**
   ```bash
   flutter clean
   flutter pub get
   flutter build apk --release
   ```

2. **Test on two Android devices:**
   - Device A: On chat detail screen, tap call button
   - Device B: Accept call
   - Verify calling screen appears full screen (not overlaid side-by-side)
   - Both make/receive calls successfully
   - Verify no black screen when ending

3. **Verify all previous fixes still work:**
   - ✅ Audio works (routing fix intact)
   - ✅ Loading dialog shows (fix #1 intact)
   - ✅ Auto-reset works (fix #2 intact)
   - ✅ State syncs (fix #3 intact)

---

**Status: ✅ Ready for Testing**

This fix addresses the core structural issue of the calling screen not appearing on ChatDetailScreen by changing the widget hierarchy from a Stack-based overlay to a full-screen replacement when calls are active.
