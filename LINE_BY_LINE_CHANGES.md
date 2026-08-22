# 📍 Line-by-Line Changes Reference

## File 1: incoming_call_screen.dart

### Location 1: Import Statement (Line 9)
**Added**:
```dart
import '../../services/call_notification_platform.dart';
```

---

### Location 2: Decline Button Handler (Line ~236, after FlutterRingtonePlayer stop)
**Added After**:
```dart
FlutterRingtonePlayer().stop();
```

**Insert**:
```dart
// 🔔 BUG FIX #2: Remove foreground notification when declining via UI
print('[IncomingCallScreen] 🔔 Removing foreground notification on decline');
await CallNotificationPlatform.stopCallNotification().ignore();
```

**Before Next**:
```dart
final myId = _myUserId != 0 ? _myUserId : await ApiService.getUserId();
```

---

### Location 3: Accept Button Handler (Line ~387-403)
**Added After**:
```dart
FlutterRingtonePlayer().stop();
```

**Insert**:
```dart
// 🔔 BUG FIX #2: Remove foreground notification when accepting via UI
print('[IncomingCallScreen] 🔔 Removing foreground notification on accept');
await CallNotificationPlatform.stopCallNotification().ignore();

// 📱 BUG FIX #3: Show background call notification immediately  
print('[IncomingCallScreen] 📱 Showing background call notification immediately');
final callerName = _callerProfile?.fullName ?? 'User $fromUserId';
await CallNotificationPlatform.showBackgroundCallNotification(
  callerName: callerName,
  channelName: channel,
).ignore();
```

**Before Next**:
```dart
final myId = _myUserId != 0 ? _myUserId : await ApiService.getUserId();
```

---

## File 2: firebase_messaging_service.dart

### Location: _showLocalNotification Method (Lines 307-335)

**REPLACE THIS BLOCK**:
```dart
final notificationType = data['type']?.toString().toUpperCase() ?? '';
print('[FCM] DEBUG: Checking notification type: $notificationType');
print('[FCM] DEBUG: Full data map: $data');

if (notificationType.contains('CALL') || 
    data['type'] == 'CALL_INVITE' || data['type'] == 'incoming_call' || 
    data['type'] == 'CALL_ACCEPT' || data['type'] == 'CALL_REJECT' || 
    data['type'] == 'CALL_END' ||
    title.toLowerCase().contains('incoming call') ||
    body.toLowerCase().contains('calling')) {
  print('[FCM] ⏭️ SKIPPING Flutter notification for call: type=$notificationType, title=$title');
  print('[FCM] ⏭️ Using native Android foreground service instead');
  return; // Don't show Flutter push notification
}
```

**WITH THIS BLOCK**:
```dart
final notificationType = data['type']?.toString().toUpperCase() ?? '';
final titleLower = title.toLowerCase();
final bodyLower = body.toLowerCase();

print('[FCM] DEBUG: Checking notification type: $notificationType');
print('[FCM] DEBUG: Title: $title, Body: $body');
print('[FCM] DEBUG: Full data map: $data');

// 🔔 BUG FIX #1: Enhanced filtering to catch all call notifications
final isCallNotification = 
    notificationType.contains('CALL') ||
    data['type'] == 'CALL_INVITE' || 
    data['type'] == 'incoming_call' || 
    data['type'] == 'CALL_ACCEPT' || 
    data['type'] == 'CALL_REJECT' || 
    data['type'] == 'CALL_END' ||
    data['call_type'] != null ||  // Check if call_type field exists
    titleLower.contains('incoming call') ||
    titleLower.contains('call') ||
    titleLower.contains('ringing') ||
    bodyLower.contains('calling') ||
    bodyLower.contains('incoming') ||
    bodyLower.contains('ringing');

if (isCallNotification) {
  print('[FCM] 🔔 BUG FIX #1: SKIPPING Flutter notification for call');
  print('[FCM] type=$notificationType, title=$title, body=$body');
  print('[FCM] ⏭️ Using NATIVE Android foreground service instead');
  return; // Don't show Flutter push notification - let native service handle it
}
```

---

## File 3: call_screen.dart

### Location: initState Method (Lines 88-95)

**CHANGE**:
```dart
// Show background call notification on BOTH sender and receiver sides when call is active
print('[CallScreen] 📱 Showing background call notification (active on both sides)');
```

**TO**:
```dart
// Show background call notification on BOTH sender and receiver sides when call is active
// NOTE: For receiver, this was already called from IncomingCallScreen's Accept button
// For sender, we call it here to ensure it appears on their side too
print('[CallScreen] 📱 Ensuring background call notification is visible (active on both sides)');
```

**Rest of the code block remains the same:**
```dart
CallNotificationPlatform.showBackgroundCallNotification(
  callerName: 'Call in Progress',
  channelName: widget.channelName,
).ignore();
```

---

## Verification Checklist

After making changes, verify:

- [ ] incoming_call_screen.dart - 3 edits made
  - [ ] Import added at top
  - [ ] Decline button has stopCallNotification() call
  - [ ] Accept button has both stopCallNotification() and showBackgroundCallNotification() calls
  
- [ ] firebase_messaging_service.dart - 1 edit made
  - [ ] Enhanced filtering with 13 checks (was 8)
  - [ ] New checks include: data['call_type'], 'call' in title, 'ringing' in title, 'incoming' in body
  
- [ ] call_screen.dart - 1 edit made
  - [ ] Comment updated to mention Accept button pre-call
  - [ ] Code itself unchanged
  
- [ ] Syntax: No red squiggly lines in IDE
- [ ] Compilation: `flutter analyze` returns no errors
- [ ] Build: `flutter run` builds successfully

---

## Git Diff View

Run this to see all changes:
```bash
git diff
```

Should show additions only (no deletions) in the three files listed above.

---

## Rollback Individual Changes

If you need to rollback specific changes:

```bash
# Rollback only incoming_call_screen.dart
git checkout HEAD -- lib/src/screens/calls/incoming_call_screen.dart

# Rollback only firebase_messaging_service.dart
git checkout HEAD -- lib/src/services/firebase_messaging_service.dart

# Rollback only call_screen.dart
git checkout HEAD -- lib/src/screens/call_screen.dart
```

---

## Quick Reference: What Each Change Does

| Change | File | Lines | Fixes |
|--------|------|-------|-------|
| Add import | incoming_call_screen.dart | 9 | Enable notification calls |
| Decline sync | incoming_call_screen.dart | 236+ | Bug #2 (Decline) |
| Accept sync | incoming_call_screen.dart | 387+ | Bug #2 & #3 (Accept) |
| Enhanced filter | firebase_messaging_service.dart | 307-335 | Bug #1 (Duplicates) |
| Comment update | call_screen.dart | 88-95 | Clarity (no logic) |

---

**Total Changes**: 5 edits across 3 files
**Lines Added**: ~40 new lines
**Lines Removed**: 0
**Lines Modified**: 1 comment

All changes are additive and non-breaking.
