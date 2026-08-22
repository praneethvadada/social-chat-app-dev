# Quick Fix Reference - Line-by-Line Changes

## File 1: chat_screen.dart (_startCall method)

### Location: Lines 822-899

**Before:**
```dart
void _startCall(int toUserId, bool isVideo) {
  print('[ChatScreen] 📞 _startCall CLICKED video=$isVideo toUserId=$toUserId myUserId=$_currentUserId');
  if (toUserId <= 0 || _currentUserId <= 0) {
    print('[ChatScreen] ❌ userId or myUserId is invalid');
    return;
  }
  
  final callerId = _currentUserId;
  final channel = 'chat_${callerId}_$toUserId';
  print('[ChatScreen] 📞 channel=$channel callerId=$callerId');

  final cm = CallStateManager();
  print('[ChatScreen] 📞 current state=${cm.currentState}');
  if (cm.currentState != CallState.idle) {
    print('[ChatScreen] ❌ NOT IN IDLE STATE, cannot start call');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('A call is already in progress')),
    );
    return;
  }

  final payload = {
    'fromUserId': callerId,
    'toUserId': toUserId,
    'channelName': channel,
    'isVideo': isVideo,
  };
  print('[ChatScreen] 📞 payload=$payload');

  // ❌ OLD: No loading dialog, user sees nothing happen
  
  // Update state first, then send invite.
  print('[ChatScreen] 📞 calling cm.setOutgoingCall()');
  cm.setOutgoingCall(payload);
  print('[ChatScreen] 📞 calling CallSignalingService().sendCallInvite()');
  CallSignalingService().sendCallInvite(
    fromUserId: callerId,
    toUserId: toUserId,
    channelName: channel,
    isVideo: isVideo,
  );
  print('[ChatScreen] ✅ sendCallInvite sent successfully');
  
  // ❌ OLD: No auto-close of dialog
}
```

**After:**
```dart
void _startCall(int toUserId, bool isVideo) {
  print('[ChatScreen] 📞 _startCall CLICKED video=$isVideo toUserId=$toUserId myUserId=$_currentUserId');
  if (toUserId <= 0 || _currentUserId <= 0) {
    print('[ChatScreen] ❌ userId or myUserId is invalid');
    return;
  }
  
  final callerId = _currentUserId;
  final channel = 'chat_${callerId}_$toUserId';
  print('[ChatScreen] 📞 channel=$channel callerId=$callerId');

  final cm = CallStateManager();
  print('[ChatScreen] 📞 current state=${cm.currentState}');
  if (cm.currentState != CallState.idle) {
    print('[ChatScreen] ❌ NOT IN IDLE STATE, cannot start call');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('A call is already in progress')),
    );
    return;
  }

  final payload = {
    'fromUserId': callerId,
    'toUserId': toUserId,
    'channelName': channel,
    'isVideo': isVideo,
  };
  print('[ChatScreen] 📞 payload=$payload');

  // ✅ NEW: Show loading dialog to indicate call is being initiated
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      backgroundColor: Colors.grey[900],
      content: Row(
        children: [
          const SizedBox(
            width: 30,
            height: 30,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              isVideo ? 'Starting video call...' : 'Starting audio call...',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    ),
  );

  // Update state first, then send invite.
  print('[ChatScreen] 📞 calling cm.setOutgoingCall()');
  cm.setOutgoingCall(payload);
  print('[ChatScreen] 📞 calling CallSignalingService().sendCallInvite()');
  CallSignalingService().sendCallInvite(
    fromUserId: callerId,
    toUserId: toUserId,
    channelName: channel,
    isVideo: isVideo,
  );
  print('[ChatScreen] ✅ sendCallInvite sent successfully');
  
  // ✅ NEW: Close the loading dialog after sending invite
  Future.delayed(const Duration(milliseconds: 500), () {
    if (mounted) {
      Navigator.pop(context);
    }
  });
}
```

**What Changed:**
- Added `showDialog()` that displays loading spinner + text
- Spinner color: Green (matches app theme)
- Text: "Starting video call..." or "Starting audio call..."
- Background: Dark gray (Colors.grey[900])
- Added `Future.delayed()` to auto-close after 500ms

**Dependencies (Already Imported):**
- `Colors` from flutter/material.dart
- `CircularProgressIndicator` from flutter/material.dart
- `AlertDialog` from flutter/material.dart
- `Navigator` from flutter/material.dart

---

## File 2: persistent_call_overlay.dart (build method)

### Location: Lines 70-76

**Before:**
```dart
@override
Widget build(BuildContext context) {
  return Consumer<CallStateManager>(
    builder: (context, callStateManager, _) {
      final callState = callStateManager.currentState;
      final payload = callStateManager.activeCallPayload;

      // When call state changes, load remote user profile
      if (callState != CallState.idle && payload != null) {
        // ... rest of code
```

**After:**
```dart
@override
Widget build(BuildContext context) {
  return Consumer<CallStateManager>(
    builder: (context, callStateManager, _) {
      final callState = callStateManager.currentState;
      final payload = callStateManager.activeCallPayload;

      // ✅ NEW: Automatically reset ended calls to idle after a brief delay
      if (callState == CallState.ended) {
        print('[PersistentCallOverlay] 📵 Call ended - resetting to idle in 500ms');
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            callStateManager.reset();
          }
        });
      }

      // When call state changes, load remote user profile
      if (callState != CallState.idle && payload != null) {
        // ... rest of code
```

**What Changed:**
- Added check: if CallState is `ended`
- Print debug log when call ends
- Schedule `callStateManager.reset()` after 500ms
- Check `if (mounted)` before calling reset (prevent memory leaks)

**Why This Works:**
- When call ends, state transitions to `ended`
- PersistentCallOverlay shows CallEndedScreen briefly
- After 500ms, automatically reset to `idle`
- When state is `idle`, PersistentCallOverlay is hidden
- User is returned to main app (chat screen)

**Dependencies (Already Present):**
- `CallState` enum (already imported)
- `callStateManager` (already available from Consumer)
- `mounted` property (available in State classes)
- `Duration` from dart:core (already imported)

---

## Summary of Changes

### Total Lines Added
- chat_screen.dart: ~27 lines (showDialog + Future.delayed)
- persistent_call_overlay.dart: ~6 lines (CallState.ended check + reset)
- **Total: ~33 lines of code**

### Total Lines Removed
- None (pure additions)

### Backwards Compatibility
- ✅ Fully backwards compatible
- ✅ No breaking changes to API
- ✅ No new dependencies
- ✅ No modifications to state machine
- ✅ All previous fixes remain intact

### Testing Effort
- **Build Time:** ~5-10 minutes
- **First Test:** ~2-3 minutes (hot reload or full build)
- **Full Test:** ~10-15 minutes (end-to-end call on two devices)

---

## Verification Checklist

- [ ] Both files have no syntax errors (run `flutter analyze`)
- [ ] Both files compile successfully (run `flutter build apk --release`)
- [ ] Can make outgoing call and see loading dialog
- [ ] Loading dialog auto-closes after ~500ms
- [ ] Calling screen appears smoothly
- [ ] Receiver can accept call
- [ ] Both see CallScreen with audio/video active
- [ ] Call ends without black screen
- [ ] App returns to chat screen smoothly
- [ ] Can make another call immediately

---

## Exact Line Numbers (For Reference)

| File | Component | Start | End | Type |
|------|-----------|-------|-----|------|
| chat_screen.dart | showDialog() | 851 | 878 | New Code |
| chat_screen.dart | Future.delayed() | 891 | 897 | New Code |
| persistent_call_overlay.dart | if (callState == CallState.ended) | 70 | 76 | New Code |

---

## How to Verify These Exact Changes

```bash
# See what changed
git diff lib/src/screens/chats/chat_screen.dart
git diff lib/src/widgets/persistent_call_overlay.dart

# Count total lines added
git diff --stat lib/src/screens/chats/chat_screen.dart lib/src/widgets/persistent_call_overlay.dart

# Show full diff with context
git show HEAD:lib/src/screens/chats/chat_screen.dart | head -n 900 | tail -n 80
```
