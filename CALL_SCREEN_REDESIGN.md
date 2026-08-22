# Call Screen Redesign - Complete Implementation

## Overview
Completely redesigned the call screen from scratch with WhatsApp-style call history display. Clean logic:
- **One log per call** (created when invite is sent)
- **Status updates** as events happen (rejected, accepted, ended)
- **No duplicates** - each call appears once with one clear status
- **Dynamic updates** via WebSocket when calls change
- **Simple UI** with clear status indicators

---

## Key Changes

### 1. Backend - Call Log Management

#### Updated `CallLog` Entity
- Added `updatedAt` timestamp field to track status changes
- Status values: `initiated`, `accepted`, `rejected`, `ended`, `missed`
- Status & duration setters now auto-update `updatedAt`

#### New Endpoints

**Log Call (POST /api/calls)**
```json
{
  "callerId": 6,
  "calleeId": 7,
  "type": "audio",
  "status": "initiated",
  "channel": "chat_6_7"
}
```

**Update Status (PUT /api/calls/{callId}/status)**
```json
{
  "status": "rejected"
}
```

#### New Repository Method
```java
Optional<CallLog> findFirstByChannelOrderByCreatedAtDesc(String channel);
```

---

### 2. Mobile - Clean Logging

#### Call Signaling Service Changes
- **Log ONCE** when `sendCallInvite()` is called with status `"initiated"`
- **Remove duplicate logging** from `CallStateManager` and `CallScreen`
- `sendCallReject()` no longer logs (call was already logged at invite time)
- Added `_logCall()` helper to centralize logging logic

#### Call API Updates
- Added `updateCallStatus(callId, status, duration)` method
- `logCall()` now only logs calls at initiation time

#### CallScreen Changes
- Removed `logCall` invocation from `_endCall()`
- Call is now created at invite time, not at end
- Status is updated via signaling events

---

### 3. Mobile UI - CallsScreenV2

#### Complete Redesign
New file: `calls_screen_v2.dart` - simple, clean implementation

**Status Indicators:**
- 🟢 **Outgoing** (green up arrow) - call initiated by user
- 🔵 **Incoming** (blue down arrow) - incoming call that was answered
- 🔴 **Missed** (red down arrow) - incoming call not answered (status=initiated or duration=0)
- ⚫ **Rejected** (gray down arrow) - incoming call that was rejected

**Features:**
- Simple `FutureBuilder` to fetch call history
- One-time log per call with clear status
- Pull-to-refresh to reload history
- WebSocket listener to auto-refresh when calls are updated
- User profile caching for performance
- Proper text overflow handling with `Expanded` + `ellipsis`

#### Status Determination Logic
```dart
final isOutgoing = userId == callerId;
final isMissed = status == 'initiated' || (status == 'ended' && duration == 0);
final isRejected = status == 'rejected';
```

**Display Rules:**
- Outgoing call → show "Outgoing audio/video call"
- Incoming call + answered → show "Incoming audio/video call • duration"
- Incoming call + not answered → show "Missed audio/video call" (red)
- Call was rejected → show "Rejected call" (gray)

---

### 4. Database Schema

#### Migration Needed
```sql
ALTER TABLE call_logs ADD COLUMN updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;

-- Update status values
UPDATE call_logs SET status = 'initiated' WHERE status = 'started';
UPDATE call_logs SET status = 'ended' WHERE status = 'ended';
```

---

## Call Flow - How It Works

### When User Makes a Call

1. **User clicks call button** on calls screen
   - Calls `_startCall()` in CallsScreenV2
   - Shows `CallingLoaderScreen`

2. **CallSignalingService.sendCallInvite()** is called
   - Sends WebSocket signal to other user
   - **Logs call to DB** with status `"initiated"` ✅
   - No duplicate logging later

3. **Other user receives invite**
   - Shown `IncomingCallScreen`
   - Can accept or reject

4. **If rejected**
   - `sendCallReject()` is called
   - Call already exists in DB, just needs status update (future feature)
   - WebSocket notifies caller
   - CallsScreen refreshes via listener

5. **If accepted and call completes**
   - Both users join Agora
   - CallScreen shown
   - User clicks end button
   - `_endCall()` is called
   - Sends `CALL_END` signal via WebSocket
   - **No logging here** (already logged at invite)
   - CallsScreen refreshes dynamically

6. **CallsScreen updates**
   - WebSocket listener detects change
   - Calls `_refresh()` after 500ms (for DB write)
   - Displays updated call with correct status & duration

---

## Eliminated Issues

### ❌ Duplicate Calls
**Before:** Calls appeared multiple times (once for initiated, once for ended)
**After:** One log created at invite, status updated as events happen

### ❌ Missed Call Detection
**Before:** Complex logic checking status != 'ended' && duration == 0
**After:** Simple check: status == 'initiated' OR (status == 'ended' && duration == 0)

### ❌ Manual Refresh Needed
**Before:** Had to manually refresh or tap "Calls" tab
**After:** WebSocket listener auto-refreshes when calls are updated

### ❌ Text Overflow
**Before:** Subtitle text overflowed the UI
**After:** Using `Expanded` with `TextOverflow.ellipsis` and `maxLines: 1`

---

## Testing Checklist

- [ ] Make a call → appears in history as "Outgoing"
- [ ] Receive a call and answer → appears as "Incoming" with duration
- [ ] Receive a call and reject → appears as "Rejected" with gray icon
- [ ] Call times out (not answered) → appears as "Missed" with red icon
- [ ] No duplicate calls in history
- [ ] Pull-to-refresh updates the list
- [ ] Call list updates dynamically when call ends (no manual refresh)
- [ ] Timestamps display correctly
- [ ] User profiles load and display correctly

---

## Files Modified

### Backend
- `CallLog.java` - Added `updatedAt`, status constants
- `CallLogRepository.java` - Added `findFirstByChannelOrderByCreatedAtDesc()`
- `CallsController.java` - Added `updateCallStatus()` endpoint

### Mobile
- **New:** `calls_screen_v2.dart` - Complete rewrite of call history UI
- `call_signaling_service.dart` - Log once at invite time
- `call_api.dart` - Added `updateCallStatus()` method
- `call_screen.dart` - Removed duplicate logging
- `call_state_manager.dart` - Removed duplicate logging
- `main_app.dart` - Switched from `CallsScreen` to `CallsScreenV2`

---

## Architecture Principles

1. **Single Source of Truth**: One call log entry per call
2. **Status-Driven**: State machine (initiated → accepted/rejected → ended)
3. **Event-Based Updates**: WebSocket pushes changes, UI reacts
4. **No Manual Refresh**: Automatic updates via listeners
5. **Clean Separation**: Logging ≠ State management ≠ UI rendering
