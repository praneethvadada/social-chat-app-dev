# Call System Debugging Guide

## 🎯 Critical Fixes Applied

### 1. **Removed Duplicate Files** ✅
- **Deleted**: `lib/src/screens/calls/call_screen.dart` (stub/placeholder)
- **Deleted**: `lib/src/services/call_state_manager.dart` (duplicate)
- **Kept**: 
  - `lib/src/screens/call_screen.dart` (REAL implementation with full Agora support)
  - `lib/src/state/call_state_manager.dart` (single source of truth for call state)

### 2. **Fixed Call Screen Navigation** ✅
- MyApp now navigates to the CORRECT CallScreen (the one with full Agora implementation)
- Proper channel name and user ID extraction from payload
- Added `myUserId` to payload for consistency

### 3. **Fixed WebSocket Notification Subscription** ✅
- Notifications queue (`/user/queue/notifications`) is now subscribed **IMMEDIATELY** on WebSocket connect
- Previously subscribed only when listeners were registered (too late!)
- This ensures CALL_INVITE messages are never missed

### 4. **Enhanced State Management** ✅
- CallStateManager is the **SINGLE SOURCE OF TRUTH**
- All state transitions go through CallStateManager
- CallSignalingService only updates state, doesn't manage UI
- MyApp listens to CallStateManager and shows appropriate screens

### 5. **Fixed Agora Lifecycle** ✅
- CallStateManager now handles ALL Agora initialization and cleanup
- Works for both caller AND receiver (receiver joins when accepting call)
- Proper permission handling for camera/microphone
- Complete error handling and logging

### 6. **Comprehensive Logging** ✅
- Every call event is logged with clear markers:
  - `>>>>` = Outgoing signals
  - `<<<<` = Incoming signals
  - `===>` = State transitions
  - `XXXX` = Ignored/rejected events
  - `✓` = Success
  - `✗` = Errors

---

## 📊 Complete Call Flow

### **Caller Side (User A initiates call)**

```
1. User A clicks call icon
   └─> CallsScreen._startCall()
       └─> CallStateManager.setOutgoingCall()
           └─> State: idle -> outgoingCalling
       └─> CallSignalingService.sendCallInvite()
           └─> WebSocket sends CALL_INVITE to backend

2. MyApp detects state = outgoingCalling
   └─> Shows CallingLoaderScreen (ringing animation)

3. User B accepts (or rejects)
   └─> WebSocket receives CALL_ACCEPT notification
       └─> CallSignalingService handles notification
           └─> CallStateManager.setInCall()
               └─> State: outgoingCalling -> inCall
               └─> _initAgoraForPayload()
                   ├─> Request permissions
                   ├─> Fetch Agora token
                   ├─> Initialize AgoraService
                   └─> Join Agora channel

4. MyApp detects state = inCall
   └─> Shows CallScreen (full call UI with video/audio)
   └─> CallScreen attaches to CallStateManager's AgoraService
   └─> Displays remote video when user joins

5. User A ends call
   └─> CallScreen._endCall()
       └─> CallSignalingService.sendCallEnd()
       └─> CallStateManager.endCall()
           └─> State: inCall -> ended
           └─> _cleanupAgora()
               ├─> Leave Agora channel
               └─> Dispose AgoraService

6. MyApp detects state = ended
   └─> Dismisses CallScreen
   └─> CallStateManager.reset()
       └─> State: ended -> idle
```

### **Receiver Side (User B receives call)**

```
1. WebSocket receives CALL_INVITE notification
   └─> CallSignalingService handles notification
       └─> CallStateManager.setIncomingCall()
           └─> State: idle -> incomingRinging

2. MyApp detects state = incomingRinging
   └─> Shows IncomingCallScreen (accept/reject UI)
   └─> Plays ringtone

3. User B clicks Accept
   └─> IncomingCallScreen sends CALL_ACCEPT signal
   └─> CallStateManager.setInCall()
       └─> State: incomingRinging -> inCall
       └─> _initAgoraForPayload()
           ├─> Request permissions
           ├─> Fetch Agora token
           ├─> Initialize AgoraService
           └─> Join Agora channel

4. MyApp detects state = inCall
   └─> Shows CallScreen (full call UI)
   └─> CallScreen attaches to AgoraService
   └─> Displays video when users connect

5. User B ends call (or User A ends remotely)
   └─> Same as caller flow above
```

---

## 🔍 How to Debug Call Issues

### Check Logs in Order:

1. **WebSocket Connection**
   ```
   [WS] CONNECTING user=123
   [WS] CONNECTED user=123
   [WS] SUBSCRIBED /user/queue/notifications (ALWAYS on connect)
   ```

2. **Call Initiation (Caller)**
   ```
   [CallsScreen] Starting video call to user 456
   [CallStateManager] STATE CHANGE: idle -> outgoingCalling
   [CallSignalingService] >>>> SENDING CALL_INVITE from=123 to=456
   ```

3. **Call Reception (Receiver)**
   ```
   [CallSignalingService] <<<< RECEIVED type=CALL_INVITE currentState=idle
   [CallSignalingService] ===> INCOMING CALL (CALL_INVITE) -> setIncomingCall
   [CallStateManager] STATE CHANGE: idle -> incomingRinging
   ```

4. **Call Acceptance**
   ```
   [IncomingCall] accepting call, transitioning to inCall state
   [CallSignalingService] >>>> SENDING CALL_ACCEPT
   [CallStateManager] STATE CHANGE: incomingRinging -> inCall
   ```

5. **Agora Initialization**
   ```
   [CallStateManager] _initAgoraForPayload START
   [CallStateManager] Channel: chat_123_456, isVideo: true
   [CallStateManager] Requesting permission: Permission.camera
   [CallStateManager] Permission granted: Permission.camera
   [CallStateManager] Fetching Agora token
   [AgoraService] Initializing with appId: ...
   [AgoraService] ✓ Engine initialized
   [AgoraService] Joining channel: chat_123_456 with uid: 12345
   [AgoraService] ✓ joinChannel API call completed
   [AgoraService] ✓ onJoinChannelSuccess: channel=chat_123_456
   [CallStateManager] ✓ Successfully joined Agora channel
   ```

6. **Remote User Joins**
   ```
   [AgoraService] ✓ onUserJoined: remoteUid=67890
   [CallScreen] Remote UID changed: 67890
   ```

7. **Call Ending**
   ```
   [CallScreen] _endCall called
   [CallSignalingService] >>>> SENDING CALL_END
   [CallStateManager] STATE CHANGE: inCall -> ended
   [CallStateManager] _cleanupAgora START
   [AgoraService] Leaving channel
   [AgoraService] ✓ Left channel
   [CallStateManager] STATE CHANGE: ended -> idle
   ```

---

## 🐛 Common Issues & Solutions

### Issue 1: Receiver doesn't get incoming call notification
**Symptoms**: Caller sees "Calling..." but receiver app doesn't show anything

**Debug**:
```bash
# Check receiver logs for:
[WS] NOTIFICATION_IN raw={...}
[CallSignalingService] <<<< RECEIVED type=CALL_INVITE
```

**If missing**:
- Check WebSocket connection status on receiver
- Verify `/user/queue/notifications` subscription in logs
- Check backend is sending notification to correct user

**If present but ignored**:
```
[CallSignalingService] XXXX IGNORED CALL_INVITE (currentState=inCall not idle)
```
- Receiver is already in another call
- CallStateManager didn't reset properly from previous call

### Issue 2: Call connects but no video/audio
**Symptoms**: Both users in call but can't see/hear each other

**Debug**:
```bash
# Check for Agora join success:
[AgoraService] ✓ onJoinChannelSuccess
[AgoraService] ✓ onUserJoined: remoteUid=...
```

**If user not joining**:
- Check permissions were granted
- Check Agora token is valid (not expired)
- Check both users joined same channel name
- Verify Agora App ID matches in backend

**If joined but no video**:
- Check `isVideo` flag in payload
- Verify camera permission granted
- Check `enableVideo()` was called

### Issue 3: App crashes when accepting call
**Symptoms**: App crashes or shows error when receiver accepts

**Debug**:
- Check for null pointer exceptions
- Verify `myUserId` is set in payload
- Check Agora SDK is properly initialized

**Solution**: Already fixed - payload now includes `myUserId` consistently

### Issue 4: Call doesn't end properly
**Symptoms**: Call UI stuck on screen, can't make new calls

**Debug**:
```bash
# Check state transitions:
[CallStateManager] STATE CHANGE: inCall -> ended
[CallStateManager] STATE CHANGE: ended -> idle
```

**If stuck**:
- Manually call `CallStateManager().reset()` to recover
- Check for uncaught exceptions in cleanup
- Verify Agora dispose is being called

### Issue 5: Permission denied errors
**Symptoms**: Black screen or no video/audio

**Debug**:
```bash
[CallStateManager] ERROR: Permission denied: Permission.camera
```

**Solution**:
- Request permissions manually on Android/iOS
- Check AndroidManifest.xml and Info.plist have permission declarations
- Test on real device (permissions don't work well on some emulators)

---

## 🧪 Testing Checklist

### Basic Call Flow
- [ ] User A can call User B (video)
- [ ] User A can call User B (audio only)
- [ ] User B receives incoming call notification
- [ ] User B can accept call
- [ ] User B can reject call
- [ ] Both users see video/hear audio
- [ ] User A can end call
- [ ] User B can end call
- [ ] Both users return to idle state

### Edge Cases
- [ ] User B rejects incoming call → User A sees rejection
- [ ] User A cancels outgoing call before User B answers
- [ ] User B doesn't answer (timeout handling)
- [ ] User receives call while already in call → new call ignored
- [ ] Network disconnection during call
- [ ] App goes to background during call
- [ ] App is killed during call

### UI/UX
- [ ] Ringtone plays on incoming call
- [ ] Ringtone stops when accepting/rejecting
- [ ] Call timer shows during active call
- [ ] Mute button works
- [ ] Camera switch works (front/back)
- [ ] Video on/off toggle works
- [ ] UI updates when remote user joins/leaves
- [ ] Navigation works correctly (can't go back during call)

### Performance
- [ ] No memory leaks (Agora properly disposed)
- [ ] No duplicate listeners
- [ ] Call state resets properly after each call
- [ ] Multiple calls in sequence work
- [ ] Low latency (< 1 second for signals)

---

## 🔧 Quick Fixes

### Reset call state manually (for development):
```dart
// In any screen, add temporary button:
ElevatedButton(
  onPressed: () {
    CallStateManager().reset();
    Navigator.of(context).popUntil((route) => route.isFirst);
  },
  child: Text('RESET CALL STATE'),
)
```

### Force reconnect WebSocket:
```dart
final ws = ChatWebSocketService();
final token = await ApiService.getToken();
final userId = await ApiService.getUserId();
await ws.reconnect(token!, userId!);
```

### Test call signaling without Agora:
Comment out Agora initialization in CallStateManager to test just signaling flow.

---

## 📱 Platform-Specific Notes

### Android
- Ensure `CAMERA`, `RECORD_AUDIO`, `INTERNET` permissions in AndroidManifest.xml
- Test on API level 23+ for runtime permissions
- Check if call UI works with screen locked

### iOS
- Ensure `NSCameraUsageDescription`, `NSMicrophoneUsageDescription` in Info.plist
- Test CallKit integration if needed for native call UI
- Check background modes for VoIP

---

## 🎓 WhatsApp/Instagram-like Features

### Implemented:
✅ Global call state management  
✅ WebSocket-based signaling (fast, real-time)  
✅ Agora for media (industry-standard like WhatsApp)  
✅ Incoming call overlay (works from any screen)  
✅ Proper lifecycle management  
✅ Call history logging  

### To Add (Optional Enhancements):
- [ ] Push notifications for calls when app is closed
- [ ] CallKit integration (iOS native call UI)
- [ ] Group calls support
- [ ] Call recording
- [ ] Screen sharing
- [ ] Reactions/emojis during call
- [ ] Call quality indicators
- [ ] Network reconnection handling

---

## 📞 Support

If calls still don't work after these fixes:

1. **Share complete logs** from both sender and receiver
2. **Check backend** - verify WebSocket is broadcasting notifications correctly
3. **Test Agora** - verify credentials and token generation
4. **Check network** - ensure both devices can reach backend and Agora servers

Good luck! 🚀
