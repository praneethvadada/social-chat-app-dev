# 🧪 Testing Guide - Three Bug Fixes

## Quick Build & Test

```bash
# Clean and rebuild
flutter clean
flutter pub get
flutter run
```

---

## Scenario 1: Bug #1 - No Duplicate Firebase Notification

**Setup**: Two devices - Device A (Sender), Device B (Receiver)

**Test Steps**:
1. Start app on both devices
2. On Device A: Initiate call to Device B
3. Look at Device B notification panel

**Expected Result**:
- ✅ ONE notification appears (the native Android foreground notification with Answer/Decline buttons)
- ❌ NO Firebase push notification overlay/expansion
- ❌ NO duplicate notifications

**What to Check**:
- Notification title shows caller name correctly
- Answer and Decline buttons are visible in notification
- No "Now" app notification showing call duplicate

**Debug Output** (in logcat):
```
[FCM] 🔔 BUG FIX #1: SKIPPING Flutter notification for call
[FCM] type=CALL_INVITE, title=...
[FCM] ⏭️ Using NATIVE Android foreground service instead
```

---

## Scenario 2: Bug #2 - Notification Syncs with Decline Button

**Setup**: Device B (Receiver) with incoming call visible

**Test Steps**:
1. Incoming call showing on Device B
2. Tap the RED **Decline** button on the IncomingCallScreen (Flutter UI)
3. Immediately look at notification panel

**Expected Result**:
- ✅ Notification disappears IMMEDIATELY
- ✅ IncomingCallScreen pops/closes
- ✅ App returns to normal state
- ❌ Notification does NOT remain after decline

**Debug Output** (in logcat):
```
[IncomingCallScreen] 🔔 Removing foreground notification on decline
[CallNotificationPlatform] 📵 Stopping call notification
[CallNotificationPlatform] ✅ Call notification stopped
```

---

## Scenario 3: Bug #2 (Accept) & Bug #3 - Background Notification Appears Immediately

**Setup**: Device B (Receiver) with incoming call visible

**Test Steps**:
1. Incoming call showing on Device B with notification
2. Tap the GREEN **Accept** button on IncomingCallScreen (Flutter UI)
3. Watch the notification area carefully
4. App should transition to CallScreen

**Expected Result - SEQUENCE**:
1. Notification switches from "Incoming Call from [Name]" → "Call in Progress"
2. ✅ Background notification appears IMMEDIATELY (no gap/delay)
3. ✅ Notification is visible while CallScreen is loading/transitioning
4. ✅ No moment without notification between accept and CallScreen

**Debug Output** (in logcat):
```
[IncomingCallScreen] 🔔 Removing foreground notification on accept
[IncomingCallScreen] 📱 Showing background call notification immediately
[CallNotificationPlatform] 📱 Showing background call notification
[CallNotificationPlatform] ✅ Background call notification shown
[CallScreen] 📱 Ensuring background call notification is visible
```

---

## Scenario 4: Full Call Flow (Complete Test)

**Setup**: Two devices (A and B), both running app

### Part A: Receiver Accepts Call
1. On Device A: Initiate call to Device B
2. Device B sees incoming notification (only ONE, native)
3. Device B user taps green **Accept** button
4. **Verify Scenario 3** results above
5. Both devices show "Call in Progress" notification
6. Video/audio call works

### Part B: Call Ends
1. Either device taps hang-up button on CallScreen
2. Call ends
3. **Verify**: All notifications cleared (no orphaned background notification)
4. Both return to normal state

### Part C: Receiver Declines Call
1. On Device A: Initiate call to Device B
2. Device B sees incoming notification
3. Device B user taps red **Decline** button
4. **Verify Scenario 2** results above
5. Device A shows "Call Declined" or similar message

---

## Common Issues & Debugging

### Issue: Still Seeing Firebase Duplicate
**Diagnosis**:
- Check Firebase Cloud Messaging console settings
- Verify notification payload contains correct `type` field
- Check logcat for: `[FCM] 🔔 BUG FIX #1` message

**Solution**:
- If not seeing log message, Firebase payload might not have 'type' field
- Backend may need to send 'type': 'CALL_INVITE' in the data object

### Issue: Notification Not Disappearing on Decline
**Diagnosis**:
- Check for error in logcat
- Verify `stopCallNotification` method called correctly
- Check if IncomingCallScreen.dart import is present

**Solution**:
- Rebuild: `flutter clean && flutter pub get && flutter run`
- Clear app data: Settings → Apps → [App Name] → Storage → Clear All Data

### Issue: Background Notification Appears With Delay
**Diagnosis**:
- Should see `[IncomingCallScreen] 📱 Showing background call notification immediately` in logs
- If not, code change may not have applied

**Solution**:
- Verify lines 387-403 in incoming_call_screen.dart have the new code
- Rebuild with `flutter clean`

### Issue: No Notifications Appearing At All
**Diagnosis**:
- Check Android notification permissions
- Verify CallNotificationService running in Android logs
- Check if notification channel exists

**Solution**:
- Grant POST_NOTIFICATIONS permission
- Check device Settings → Notifications → [App Name] is enabled
- Restart app and device if needed

---

## Logcat Filter Commands

Run these in Android Studio Terminal to see debug logs:

```bash
# All call-related logs
adb logcat | grep -i call

# Bug fix specific logs
adb logcat | grep "🔔\|📱\|BUG FIX"

# Firebase logs
adb logcat | grep "\[FCM\]"

# IncomingCallScreen logs
adb logcat | grep "\[IncomingCallScreen\]"

# Notification platform logs
adb logcat | grep "\[CallNotificationPlatform\]"

# Combined for easier reading
adb logcat | grep -E "\[FCM\]|\[CallNotificationPlatform\]|\[IncomingCallScreen\]"
```

---

## Success Criteria

All three bugs are FIXED when:

✅ **Bug #1**: Only native notification appears (no Firebase duplicate)
✅ **Bug #2**: Declining removes notification immediately  
✅ **Bug #3**: Accepting shows background notification immediately

When all three pass, you can move on to the next feature/bug!
